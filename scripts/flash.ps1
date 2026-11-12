#Requires -RunAsAdministrator
<#
.SYNOPSIS
  Write an ISO to a USB drive from Windows (WSL can't reach USB devices).

.DESCRIPTION
  Wipes the target disk, writes the ISO byte-for-byte (DD mode), then reads it
  back and compares SHA-256 hashes. Refuses anything that isn't a USB disk or
  that Windows boots from.

.EXAMPLE
  Get-Disk   # find the USB disk's number
  .\flash.ps1 -IsoPath \\wsl.localhost\archlinux\home\<user>\denden\out\denden-<date>-x86_64.iso -DiskNumber 3
#>
param(
  [Parameter(Mandatory)] [string] $IsoPath,
  [Parameter(Mandatory)] [int] $DiskNumber,
  # Skip the typed confirmation.
  [switch] $Force
)
$ErrorActionPreference = 'Stop'

$iso = Get-Item -LiteralPath $IsoPath
$disk = Get-Disk -Number $DiskNumber
if ($disk.BusType -ne 'USB') { throw "Disk $DiskNumber is $($disk.BusType), not USB; refusing." }
if ($disk.IsBoot -or $disk.IsSystem) { throw "Disk $DiskNumber is a boot/system disk; refusing." }
if ($iso.Length -gt $disk.Size) { throw "ISO ($($iso.Length) bytes) is larger than disk $DiskNumber ($($disk.Size) bytes)." }

$letters = (Get-Partition -DiskNumber $DiskNumber -ErrorAction SilentlyContinue |
  Where-Object DriveLetter | ForEach-Object { "$($_.DriveLetter):" }) -join ', '
Write-Host "Target : disk $DiskNumber  $($disk.FriendlyName)  $([math]::Round($disk.Size / 1GB, 1)) GB  [$letters]"
Write-Host "Source : $($iso.FullName)  $([math]::Round($iso.Length / 1GB, 2)) GB"
if (-not $Force) {
  $answer = Read-Host "Everything on disk $DiskNumber will be destroyed. Type ERASE to continue"
  if ($answer -cne 'ERASE') { Write-Host 'Aborted.'; exit 1 }
}

Write-Host 'Hashing ISO...'
$isoHash = (Get-FileHash -LiteralPath $iso.FullName -Algorithm SHA256).Hash

# Drop the partitions so Windows releases its volume locks. (Taking the disk
# offline would be safer, but Windows refuses that for removable media.)
Clear-Disk -Number $DiskNumber -RemoveData -RemoveOEM -Confirm:$false

$device = "\\.\PhysicalDrive$DiskNumber"
$sector = [int]$disk.LogicalSectorSize
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
Write-Host "Done. Verified SHA-256 $isoHash"
