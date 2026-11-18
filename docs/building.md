# Building, testing and flashing

## Layout

| Path | What it is |
| --- | --- |
| `archiso/` | The archiso profile. Started as a verbatim copy of upstream `configs/releng` (see below). |
| `archiso/packages.x86_64` | Packages installed into the live image. |
| `archiso/airootfs/` | Files overlaid onto the image's root filesystem. |
| `archiso/profiledef.sh` | ISO name, boot modes, compression, file permissions. |
| `archiso/pacman.conf` | Repos the image is built from: local `denden`, `cachyos`, then Arch. |
| `packages/` | PKGBUILDs for this distro's own packages: T3 Code, the `denden-base` and `denden-desktop` meta packages, the startup screens (`denden-boot`), the installer. |
| `scripts/setup-build-host.sh` | One-time setup of an Arch build host. |
| `scripts/build.sh` | Builds `packages/` into a local repo, then the ISO into `out/`. |
| `scripts/test-install.sh` | Installs the newest ISO onto a virtual disk in a VM, then boots it. |
| `docs/agent-environment.md` | Design of the agent environment: the reason this distro exists. |
| `docs/ROADMAP.md` | Milestones, in build order. |

## Upstream baseline

The first commit (tagged `baseline`) is an unmodified import of
`configs/releng` from archiso **v92**
(`8e3ead17e1e5cfde503534d23be918b8787d3dd3`). Every later commit is a
deliberate divergence, so `git diff baseline -- archiso/` always shows exactly
how this distro differs from stock Arch.

To see what changed upstream when bumping archiso:

```sh
git fetch --depth 1 https://gitlab.archlinux.org/archlinux/archiso.git tag v92 tag v93
git diff v92:configs/releng v93:configs/releng
```

## Building

mkarchiso only runs on Arch Linux, as root: on Den Den itself, or in the Arch
WSL distro (`wsl --install archlinux`) with the repo on the Linux filesystem —
never a Windows drive, where the exec bits and symlinks the profile depends on
are lost:

```sh
sudo pacman -Syu --needed git github-cli
gh repo clone Lungren2/denden ~/denden
cd ~/denden
sudo ./scripts/setup-build-host.sh   # once: archiso, makepkg, CachyOS key + mirrorlist
sudo ./scripts/build.sh
```

`build.sh` first builds every `packages/*/PKGBUILD` into a local pacman repo
(`repo/x86_64/`, as your user), then builds the ISO from Arch, CachyOS and
that local repo.

## Testing in a VM

```sh
sudo pacman -S --needed qemu-desktop edk2-ovmf
run_archiso -u -i out/*.iso          # boot the live image
sudo pacman -S --needed qemu-base qemu-hw-display-virtio-vga \
  qemu-hw-display-virtio-gpu edk2-ovmf socat \
  limine gptfdisk dosfstools mtools
./scripts/test-install.sh            # install to a virtual disk, then boot it
./scripts/test-install.sh windows    # boot it and pick Windows at startup
```

`test-install.sh` runs `denden-install` unattended in a KVM VM against a blank
virtual disk, with a second small disk that looks like a Windows disk to the
startup picker. It boots the result and saves screenshots of the start (every
2 s) and the desktop. A VM without a GPU can't show the Niri session (niri
won't render in software), so check the session in the guest's journal; the
script shuts the VM down cleanly for that.

## Flashing

From Linux (Den Den itself, or any Arch system), `scripts/flash.sh` writes the
ISO byte for byte and verifies it by SHA-256. Find the stick by model and bus,
not by name alone:

```sh
lsblk -o NAME,MODEL,TRAN,SIZE
scripts/flash.sh out/denden-<date>-x86_64.iso /dev/sdX
```

It refuses anything that isn't a whole USB disk, or that has a mounted
partition, and asks you to type a word first. A stick that holds backups
(`denden-backup setup`) keeps them: only the image is replaced, and the
DENDEN_DATA partition is put back into the new partition table (`--erase`
wipes everything). It can also write to a disk image file, for testing.

From Windows (WSL can't see USB drives directly), `scripts/flash.ps1` does the
same, and `-Erase` wipes everything. Run it from an elevated PowerShell; the
ISO is reachable at `\\wsl$\archlinux\home\<user>\denden\out\`:

```powershell
Get-Disk   # note the USB disk's Number
pwsh -ExecutionPolicy Bypass -File .\scripts\flash.ps1 -IsoPath <iso> -DiskNumber <n>
```

Rufus (DD mode) or balenaEtcher work too, but they erase the backups.

## What the installer does

`denden-install` asks for a disk and whether to erase it or install into its
largest free space, keeping the partitions already there (e.g. beside
Windows). Then it asks for a hostname, user and time zone, and confirms before
touching anything. It creates a 4 GiB boot partition and a Btrfs partition
with the subvolumes `@`, `@home`, `@src`, `@snapshots`, `@log`, `@pkg` and
`@docker`, and installs `denden-desktop` plus drivers for the GPU it finds.

The start is a rEFInd picker showing Den Den and, if Windows is on any disk,
Windows (it remembers the last choice; with Den Den alone it goes straight
on), then a Plymouth splash. Limine sits behind it as the recovery menu (hold
a key as Den Den starts) with every root snapshot and the LTS kernel. If
Windows goes on another disk later, run `sudo denden-boot-update` to add it to
the picker.
