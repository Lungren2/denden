# archdev

A personal Arch Linux–based distro tuned for an AI-assisted development
workflow. Built with [archiso](https://gitlab.archlinux.org/archlinux/archiso).

> `archdev` is a working name. Rename the repo and set `iso_name` /
> `iso_label` in `archiso/profiledef.sh` once a name is picked.

## Layout

| Path | What it is |
| --- | --- |
| `archiso/` | The archiso profile. Started as a verbatim copy of upstream `configs/releng` (see below). |
| `archiso/packages.x86_64` | Packages installed into the live image. |
| `archiso/airootfs/` | Files overlaid onto the image's root filesystem. |
| `archiso/profiledef.sh` | ISO name, boot modes, compression, file permissions. |
| `scripts/build.sh` | Builds the ISO into `out/`. |
| `docs/ROADMAP.md` | What makes this distro different from vanilla Arch. |

## Upstream baseline

The first commit (tagged `baseline`) is an unmodified import of `configs/releng` from archiso
**v92** (`8e3ead17e1e5cfde503534d23be918b8787d3dd3`). Every later commit is a
deliberate divergence, so `git diff baseline -- archiso/` always shows
exactly how this distro differs from stock Arch.

To see what changed upstream when bumping archiso:

```sh
git fetch --depth 1 https://gitlab.archlinux.org/archlinux/archiso.git tag v93
git diff v92:configs/releng v93:configs/releng
```

## Building

mkarchiso only runs on Arch Linux, as root. From Windows, use the Arch WSL
distro (`wsl --install archlinux`), then build from a clone on the Linux
filesystem — a checkout on NTFS loses the exec bits and symlinks the profile
depends on:

```sh
sudo pacman -Syu --needed archiso git
git clone /mnt/e/archdev ~/archdev
cd ~/archdev
sudo ./scripts/build.sh
```

Test the result without real hardware:

```sh
sudo pacman -S --needed qemu-desktop edk2-ovmf
run_archiso -u -i out/*.iso
```

## Working on this repo from Windows

The repo's git config sets `core.autocrlf=false` and `core.symlinks=true`, and
`.gitattributes` forces LF endings. Developer Mode must stay enabled for git to
create symlinks. When editing on Windows, make sure your editor saves with LF.
