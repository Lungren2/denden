#Requires -RunAsAdministrator
<#
.SYNOPSIS
  Write an ISO to a USB drive from Windows (WSL can't reach USB devices).

.DESCRIPTION
  Writes the ISO byte-for-byte (DD mode), then reads it back and compares
  SHA-256 hashes. Refuses anything that isn't a USB disk or that Windows boots
  from.

  A Den Den stick can also hold backups, in a partition named DENDEN_DATA after
  the image (denden-backup sets it up). Flashing keeps that partition: only the
  image is rewritten, then the partition is put back into the new partition
  table. -Erase wipes the whole stick instead.

.EXAMPLE
  Get-Disk   # find the USB disk's number
  .\flash.ps1 -IsoPath \\wsl.localhost\archlinux\home\<user>\denden\out\denden-<date>-x86_64.iso -DiskNumber 3
#>
param(
  [Parameter(Mandatory)] [string] $IsoPath,
  [Parameter(Mandatory, ParameterSetName = 'Disk')] [int] $DiskNumber,
  # Write to a disk image file instead of a disk (for testing this script).
  [Parameter(Mandatory, ParameterSetName = 'Image')] [string] $ImageFile,
  # Wipe the whole stick, backups included.
  [switch] $Erase,
  # Skip the typed confirmation.
  [switch] $Force
)
$ErrorActionPreference = 'Stop'
$DataName = 'DENDEN_DATA'

Add-Type -TypeDefinition @'
using System;
using System.IO;
using System.Runtime.InteropServices;
using Microsoft.Win32.SafeHandles;

public static class DenDenDisk {
  [DllImport("kernel32.dll", SetLastError = true, CharSet = CharSet.Unicode)]
  static extern SafeFileHandle CreateFile(string name, uint access, uint share, IntPtr sa, uint disposition, uint flags, IntPtr template);
  [DllImport("kernel32.dll", SetLastError = true)]
  static extern bool DeviceIoControl(SafeFileHandle h, uint code, IntPtr inBuf, uint inSize, IntPtr outBuf, uint outSize, out uint returned, IntPtr overlapped);

  // Lock and dismount a volume so the disk's sectors under it can be written.
  // The returned handle keeps the lock until it is closed.
  public static SafeFileHandle LockVolume(string path) {
    var h = CreateFile(path, 0xC0000000, 3, IntPtr.Zero, 3, 0, IntPtr.Zero);
    if (h.IsInvalid) throw new IOException("Can't open " + path + " (error " + Marshal.GetLastWin32Error() + ")");
    uint n;
    if (!DeviceIoControl(h, 0x00090018, IntPtr.Zero, 0, IntPtr.Zero, 0, out n, IntPtr.Zero))
      throw new IOException("Can't lock " + path + " (error " + Marshal.GetLastWin32Error() + ")");
    DeviceIoControl(h, 0x00090020, IntPtr.Zero, 0, IntPtr.Zero, 0, out n, IntPtr.Zero);
    return h;
  }

  static readonly uint[] Table = MakeTable();
  static uint[] MakeTable() {
    var t = new uint[256];
    for (uint i = 0; i < 256; i++) {
      uint c = i;
      for (int k = 0; k < 8; k++) c = (c & 1) != 0 ? 0xEDB88320u ^ (c >> 1) : c >> 1;
      t[i] = c;
    }
    return t;
  }
  public static uint Crc32(byte[] data, int offset, int count) {
    uint c = 0xFFFFFFFFu;
    for (int i = offset; i < offset + count; i++) c = Table[(c ^ data[i]) & 0xFF] ^ (c >> 8);
    return c ^ 0xFFFFFFFFu;
  }
}
'@

function Read-Sectors($stream, [long]$lba, [int]$count) {
  $buf = New-Object byte[] ($count * $script:sector)
  [void]$stream.Seek($lba * $script:sector, 'Begin')
  $got = 0
  while ($got -lt $buf.Length) {
    $n = $stream.Read($buf, $got, $buf.Length - $got)
    if ($n -le 0) { throw "Short read at LBA $lba" }
    $got += $n
  }
  return ,$buf
}
function Write-Sectors($stream, [long]$lba, [byte[]]$buf) {
  [void]$stream.Seek($lba * $script:sector, 'Begin')
  $stream.Write($buf, 0, $buf.Length)
}

# The GPT on the target: header fields and the raw entry array, or $null.
function Read-Gpt($stream) {
  $hdr = Read-Sectors $stream 1 1
  if ([Text.Encoding]::ASCII.GetString($hdr, 0, 8) -ne 'EFI PART') { return $null }
  $entriesLba = [BitConverter]::ToUInt64($hdr, 72)
  $count = [BitConverter]::ToUInt32($hdr, 80)
  $size = [BitConverter]::ToUInt32($hdr, 84)
  $sectors = [int][math]::Ceiling($count * $size / $script:sector)
  [pscustomobject]@{
    Header = $hdr; Entries = (Read-Sectors $stream $entriesLba $sectors)
    Count = [int]$count; Size = [int]$size; EntrySectors = $sectors
  }
}
function Get-EntryName([byte[]]$entries, [int]$offset) {
  [Text.Encoding]::Unicode.GetString($entries, $offset + 56, 72).TrimEnd([char]0)
}

if ($PSCmdlet.ParameterSetName -eq 'Disk') {
  $disk = Get-Disk -Number $DiskNumber
  if ($disk.BusType -ne 'USB') { throw "Disk $DiskNumber is $($disk.BusType), not USB; refusing." }
  if ($disk.IsBoot -or $disk.IsSystem) { throw "Disk $DiskNumber is a boot/system disk; refusing." }
  $device = "\\.\PhysicalDrive$DiskNumber"
  $sector = [int]$disk.LogicalSectorSize
  $diskSize = [long]$disk.Size
  $name = "disk $DiskNumber  $($disk.FriendlyName)"
} else {
  $device = (Resolve-Path -LiteralPath $ImageFile).ProviderPath
  $sector = 512
  $diskSize = (Get-Item -LiteralPath $device).Length
  $name = "image $device"
}
$iso = Get-Item -LiteralPath $IsoPath
if ($iso.Length -gt $diskSize) { throw "ISO ($($iso.Length) bytes) is larger than the target ($diskSize bytes)." }
$diskSectors = [long]($diskSize / $sector)

# A backup partition to keep: found by name, and only if the new image ends
# before it starts.
$keep = $null
$probe = New-Object IO.FileStream($device, [IO.FileMode]::Open, [IO.FileAccess]::Read, [IO.FileShare]::ReadWrite, 4096)
try {
  $old = Read-Gpt $probe
  if ($old) {
    for ($i = 0; $i -lt $old.Count; $i++) {
      $off = $i * $old.Size
      if ((Get-EntryName $old.Entries $off) -eq $DataName) {
        $entry = New-Object byte[] $old.Size
        [Array]::Copy($old.Entries, $off, $entry, 0, $old.Size)
        $keep = [pscustomobject]@{ Entry = $entry; First = [BitConverter]::ToUInt64($entry, 32); Last = [BitConverter]::ToUInt64($entry, 40) }
      }
    }
  }
} finally { $probe.Dispose() }
if ($keep -and $Erase) { $keep = $null }
if ($keep -and ($keep.First * $sector -lt $iso.Length)) {
  throw "The new image ($([math]::Round($iso.Length / 1GB, 2)) GB) would overwrite the backup partition, which starts at $([math]::Round($keep.First * $sector / 1GB, 2)) GB. Use -Erase to wipe the stick instead."
}

Write-Host "Target : $name  $([math]::Round($diskSize / 1GB, 1)) GB"
Write-Host "Source : $($iso.FullName)  $([math]::Round($iso.Length / 1GB, 2)) GB"
if ($keep) {
  Write-Host "Keeping: the backup partition ($([math]::Round(($keep.Last - $keep.First + 1) * $sector / 1GB, 1)) GB)"
  $prompt = "The Den Den image on the stick will be replaced; backups are kept. Type FLASH to continue"
  $word = 'FLASH'
} else {
  $prompt = "Everything on the target will be destroyed. Type ERASE to continue"
  $word = 'ERASE'
}
if (-not $Force) {
  $answer = Read-Host $prompt
  if ($answer -cne $word) { Write-Host 'Aborted.'; exit 1 }
}

Write-Host 'Hashing ISO...'
$isoHash = (Get-FileHash -LiteralPath $iso.FullName -Algorithm SHA256).Hash

$locks = @()
if ($PSCmdlet.ParameterSetName -eq 'Disk') {
  if ($keep) {
    # Release Windows' hold on the stick's volumes without touching the
    # partition table, which Clear-Disk would wipe along with the end of the
    # backup partition.
    foreach ($p in Get-Partition -DiskNumber $DiskNumber -ErrorAction SilentlyContinue) {
      foreach ($path in $p.AccessPaths | Where-Object { $_ -like '\\?\Volume*' }) {
        $locks += [DenDenDisk]::LockVolume($path.TrimEnd('\').Replace('\\?\', '\\.\'))
      }
    }
  } else {
    # Drop the partitions so Windows releases its volume locks. (Taking the
    # disk offline would be safer, but Windows refuses that for removable media.)
    Clear-Disk -Number $DiskNumber -RemoveData -RemoveOEM -Confirm:$false
  }
}

try {
  $bufSize = 4MB
  $buf = New-Object byte[] $bufSize
  $src = [IO.File]::OpenRead($iso.FullName)
  try {
    $dst = New-Object IO.FileStream($device, [IO.FileMode]::Open, [IO.FileAccess]::Write, [IO.FileShare]::ReadWrite, $bufSize, [IO.FileOptions]::WriteThrough)
    try {
      $written = 0L
      while (($n = $src.Read($buf, 0, $bufSize)) -gt 0) {
        # Raw device writes must be whole sectors; zero-pad the final chunk.
        $len = [int]([math]::Ceiling($n / $sector) * $sector)
        if ($len -gt $n) { [Array]::Clear($buf, $n, $len - $n) }
        $dst.Write($buf, 0, $len)
        $written += $n
        Write-Progress -Activity 'Writing' -Status "$([math]::Round($written / 1MB)) MB" -PercentComplete ($written * 100 / $iso.Length)
      }
      $dst.Flush()
    } finally { $dst.Dispose() }
  } finally { $src.Dispose() }
  Write-Progress -Activity 'Writing' -Completed

  Write-Host 'Verifying...'
  $sha = [Security.Cryptography.SHA256]::Create()
  $rd = New-Object IO.FileStream($device, [IO.FileMode]::Open, [IO.FileAccess]::Read, [IO.FileShare]::ReadWrite, $bufSize)
  try {
    $remaining = $iso.Length
    while ($remaining -gt 0) {
      $want = [int][math]::Min($bufSize, [math]::Ceiling($remaining / $sector) * $sector)
      $n = $rd.Read($buf, 0, $want)
      if ($n -le 0) { throw 'Unexpected end of device during verification.' }
      $use = [int][math]::Min($n, $remaining)
      [void]$sha.TransformBlock($buf, 0, $use, $null, 0)
      $remaining -= $use
    }
    [void]$sha.TransformFinalBlock($buf, 0, 0)
  } finally { $rd.Dispose() }
  $diskHash = -join ($sha.Hash | ForEach-Object { $_.ToString('X2') })
  if ($diskHash -ne $isoHash) { throw "Verification FAILED: disk $diskHash != ISO $isoHash" }
  Write-Host "Verified SHA-256 $isoHash"

  if ($keep) {
    # The image brought its own partition table, sized to the image. Extend it
    # to the whole stick and add the backup partition back, then write the
    # backup copy of the table at the end of the stick.
    $rw = New-Object IO.FileStream($device, [IO.FileMode]::Open, [IO.FileAccess]::ReadWrite, [IO.FileShare]::ReadWrite, 4096, [IO.FileOptions]::WriteThrough)
    try {
      $gpt = Read-Gpt $rw
      if (-not $gpt) { throw 'The new image has no GPT; the backup partition was not added back.' }
      $slot = -1
      for ($i = 0; $i -lt $gpt.Count; $i++) {
        $off = $i * $gpt.Size
        $used = $false
        for ($b = 0; $b -lt 16; $b++) { if ($gpt.Entries[$off + $b] -ne 0) { $used = $true; break } }
        if ($used) {
          if ([BitConverter]::ToUInt64($gpt.Entries, $off + 40) -ge $keep.First) { throw 'A partition in the new image overlaps the backup partition.' }
        } elseif ($slot -lt 0) { $slot = $i }
      }
      if ($slot -lt 0) { throw 'No free slot in the new partition table.' }
      [Array]::Copy($keep.Entry, 0, $gpt.Entries, $slot * $gpt.Size, $gpt.Size)

      $last = $diskSectors - 1
      $backupEntriesLba = $last - $gpt.EntrySectors
      if ($keep.Last -gt $backupEntriesLba - 1) { throw 'The backup partition runs past the end of the stick.' }
      $entriesCrc = [DenDenDisk]::Crc32($gpt.Entries, 0, $gpt.Count * $gpt.Size)

      $h = $gpt.Header
      $hsize = [BitConverter]::ToUInt32($h, 12)
      function Set-U64([byte[]]$b, [int]$o, [uint64]$v) { [Array]::Copy([BitConverter]::GetBytes($v), 0, $b, $o, 8) }
      function Set-U32([byte[]]$b, [int]$o, [uint32]$v) { [Array]::Copy([BitConverter]::GetBytes($v), 0, $b, $o, 4) }
      function Seal([byte[]]$b) { Set-U32 $b 16 0; Set-U32 $b 16 ([DenDenDisk]::Crc32($b, 0, $hsize)) }

      Set-U64 $h 32 $last                    # alternate (backup) header LBA
      Set-U64 $h 48 ($backupEntriesLba - 1)  # last usable LBA
      Set-U32 $h 88 $entriesCrc
      Seal $h
      $backup = [byte[]]$h.Clone()
      Set-U64 $backup 24 $last               # this header's LBA
      Set-U64 $backup 32 1                   # the other header's LBA
      Set-U64 $backup 72 $backupEntriesLba   # this copy's entry array
      Seal $backup

      # The protective MBR covers the whole stick, as GPT tools expect.
      $mbr = Read-Sectors $rw 0 1
      if ($mbr[450] -eq 0xEE) { Set-U32 $mbr 458 ([uint32][math]::Min([long]$last, [long][uint32]::MaxValue)); Write-Sectors $rw 0 $mbr }

      Write-Sectors $rw ([BitConverter]::ToUInt64($h, 72)) $gpt.Entries
      Write-Sectors $rw 1 $h
      Write-Sectors $rw $backupEntriesLba $gpt.Entries
      Write-Sectors $rw $last $backup
      $rw.Flush()
    } finally { $rw.Dispose() }
    Write-Host 'Backup partition kept.'
  }
} finally {
  foreach ($l in $locks) { $l.Dispose() }
}
if ($PSCmdlet.ParameterSetName -eq 'Disk') { Update-Disk -Number $DiskNumber }
Write-Host 'Done.'
