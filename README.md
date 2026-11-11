# archdev

A personal Arch Linux–based distro built as an environment for AI agents to
work in effectively. It uses CachyOS's kernel and packages on top of Arch, and
is built with [archiso](https://gitlab.archlinux.org/archlinux/archiso).

> `archdev` is a working name. Rename the repo and set `iso_name` /
> `iso_label` in `archiso/profiledef.sh` once a name is picked.

## Layout

| Path | What it is |
| --- | --- |
| `archiso/` | The archiso profile. Started as a verbatim copy of upstream `configs/releng` (see below). |
| `archiso/packages.x86_64` | Packages installed into the live image. |
| `archiso/airootfs/` | Files overlaid onto the image's root filesystem. |
| `archiso/profiledef.sh` | ISO name, boot modes, compression, file permissions. |
| `archiso/pacman.conf` | Repos the image is built from: local `archdev`, `cachyos`, then Arch. |
| `packages/` | PKGBUILDs for this distro's own packages (e.g. `t3code-cli`). |
| `scripts/setup-build-host.sh` | One-time setup of an Arch build host. |
| `scripts/build.sh` | Builds `packages/` into a local repo, then the ISO into `out/`. |
| `docs/agent-environment.md` | Design of the agent environment: the reason this distro exists. |
| `docs/ROADMAP.md` | Milestones, in build order. |

## Upstream baseline

The first commit (tagged `baseline`) is an unmodified import of `configs/releng` from archiso
**v92** (`8e3ead17e1e5cfde503534d23be918b8787d3dd3`). Every later commit is a
deliberate divergence, so `git diff baseline -- archiso/` always shows
exactly how this distro differs from stock Arch.

To see what changed upstream when bumping archiso:

```sh
git fetch --depth 1 https://gitlab.archlinux.org/archlinux/archiso.git tag v92 tag v93
git diff v92:configs/releng v93:configs/releng
```

## Building

mkarchiso only runs on Arch Linux, as root. Development happens in the Arch
WSL distro (`wsl --install archlinux`), with the repo on the Linux filesystem —
never a Windows drive, where the exec bits and symlinks the profile depends on
are lost:

```sh
sudo pacman -Syu --needed git github-cli
gh repo clone Lungren2/archdev ~/archdev
cd ~/archdev
sudo ./scripts/setup-build-host.sh   # once: archiso, makepkg, CachyOS key + mirrorlist
sudo ./scripts/build.sh
```

`build.sh` first builds every `packages/*/PKGBUILD` into a local pacman repo
(`repo/x86_64/`, as your user), then builds the ISO from Arch, CachyOS and
that local repo.

Test the result without real hardware:

```sh
sudo pacman -S --needed qemu-desktop edk2-ovmf
run_archiso -u -i out/*.iso
```

## Flashing

WSL can't see USB drives directly, so write the ISO from Windows. The ISO is
reachable at `\\wsl$\archlinux\home\<user>\archdev\out\`.

`scripts/flash.ps1` wipes a USB disk, writes the ISO in DD mode and verifies it
by SHA-256. Run it from an elevated PowerShell; it refuses non-USB and boot
disks and asks you to type `ERASE` first:

```powershell
Get-Disk   # note the USB disk's Number
pwsh -ExecutionPolicy Bypass -File .\scripts\flash.ps1 -IsoPath <iso> -DiskNumber <n>
```

Rufus (DD mode) or balenaEtcher work too.

## License

Original work in this repo is licensed under the [MIT License](LICENSE).

Everything under `archiso/` is derived from
[archiso](https://gitlab.archlinux.org/archlinux/archiso)'s `releng` profile and
remains under **GPL-3.0-or-later** (see
[`LICENSES/GPL-3.0-or-later.txt`](LICENSES/GPL-3.0-or-later.txt)). Changes made
to files in that directory are distributed under the same license.
