# Den Den

You are running on Den Den, an Arch Linux-based system built for coding
agents working under a human's supervision. This file is the system contract
and a map of the system: read it before changing anything outside your
project. Every part of Den Den is meant to be changed by asking an agent, so
when the user asks to change how the computer looks, starts or behaves, find
the part below and change it.

## The machine

- Arch Linux with CachyOS repositories and the `linux-cachyos` kernel
  (`linux-cachyos-lts` is the fallback in the recovery menu).
- Package repositories in priority order: `[denden]` (this system's own
  packages), `[cachyos]`, then Arch's `core` and `extra`.
- Btrfs. Root (`/`) is snapshotted before and after every pacman transaction;
  `/home` and `/src` are snapshotted hourly. `snapper list-configs` and
  `snapper -c root list` show them, and the recovery menu (hold a key as Den
  Den starts) can boot any root snapshot.
- Toolchains: Node (npm, pnpm), Bun, Rust, Python (`uv`), .NET, and Docker
  with Compose and Buildx. The user is in the `docker` group. A project that
  needs other versions pins them in its `mise.toml` (`mise use node@22`);
  mise's shims are on `PATH` ahead of the system's, so pinned versions win
  inside that project.
- Inbound network connections are refused except over Tailscale. To expose a
  dev server to the user's other devices, bind it and give them the
  machine's Tailscale address (`tailscale ip`); don't open firewall ports.
- You run as the user. `sudo` works without a password.
- The user's GitHub repositories are in `~/Projects` (their own as
  `~/Projects/<repo>`, an organisation's as `~/Projects/<org>/<repo>`).
  `denden-repos` clones new ones and fast-forwards clean ones every hour; it
  never touches a repository with uncommitted changes.

## Rules

1. Use the narrowest change that does the job: inside the project before
   per-user, per-user before system-wide.
2. Before any `sudo` command, tell the user what you are about to run and why.
3. Never partition, format or overwrite a disk (`fdisk`, `parted`, `mkfs`,
   `wipefs`, `dd` to a device, …) without the user's explicit go-ahead for that
   specific disk in this conversation.
4. Install software with pacman from the repositories above. Don't use AUR
   helpers, `curl | sh` installers, or `sudo npm -g` / `sudo pip`.
5. Change system configuration with drop-in files (`/etc/<name>.d/`) where the
   program supports them, and tell the user which files you changed.
6. Don't delete snapshots or backups, or disable snap-pac or the backup
   timers. If the system needs rolling back, tell the user which snapshot and
   let them decide.
7. Screens the user sees should look like a product: no terminal windows or
   technical text on normal paths, no taglines.

## Map of the system

Each part, what runs it, where to change it, and the Den Den package that
ships it (its source is `/src/denden/packages/<package>`). Per-user files
override the system ones, so try a change there first.

| Part | What runs it | Change it in | Package |
| --- | --- | --- | --- |
| Start: OS picker, recovery menu, splash | rEFInd → Limine → Plymouth | `denden-boot-update` writes `/boot/EFI/denden/refind.conf`; `/boot/limine.conf`, `/etc/default/limine`; kernel options in `/etc/kernel/cmdline` (then `limine-update`); splash theme `/usr/share/plymouth/themes/denden` | `denden-boot` |
| Login | greetd, logging the user straight in | `/etc/greetd/config.toml` | `denden-installer` |
| Windows and shortcuts | niri | `~/.config/niri/config.kdl` (copy of `/etc/niri/config.kdl`; reloads live; `niri msg` for state) | `denden-desktop` |
| Taskbar, launcher, quick settings, notifications, wallpaper, lock screen | Noctalia, started by `denden-shell` | `~/.config/noctalia/config.toml` (wins), Den Den's defaults in `/usr/share/denden/noctalia/denden.toml`, palette `DenDen.json`; reloads live; `noctalia msg …` | `denden-desktop` |
| Terminal | foot | `~/.config/foot/foot.ini` | `denden-desktop` |
| Browser and default apps | Helium | `~/.config/mimeapps.list` over `/etc/xdg/mimeapps.list` | `denden-desktop` |
| GTK app theme | dconf | `gsettings set org.gnome.desktop.interface …`; defaults in `/etc/dconf/db/local.d/00-denden` | `denden-desktop` |
| Agents | T3 Code (desktop app, `t3`), Claude Code, Codex | this file: `/etc/denden/AGENTS.md`, linked as each agent's user-level instructions | `denden-base`, `t3code-*` |
| Shell environment | bash, mise | `/etc/profile.d/denden.sh` (login shells), `/usr/lib/environment.d/50-denden.conf` (desktop session) | `denden-base` |
| GitHub repositories | `denden-repos` (user timer) | `denden-repos.service`/`.timer` | `denden-base` |
| Network and remote access | NetworkManager, Tailscale (`denden-tailscale`), `denden-firewall` | `/usr/share/denden/firewall.nft` | `denden-base` |
| Backups | `denden-backup` (restic to the Den Den USB stick) | `/usr/share/denden/backup-excludes`; `denden-backup.timer` | `denden-base` |
| Lid and power | systemd-logind | `/usr/lib/systemd/logind.conf.d/50-denden.conf` (override in `/etc/systemd/logind.conf.d/`) | `denden-base` |
| Installer and live USB | `denden-install`, archiso | `/src/denden/archiso` | `denden-installer` |

## Changing Den Den itself

Den Den is built from `/src/denden`, a git clone of github.com/Lungren2/denden:

- `packages/<name>/` holds each package's PKGBUILD and the files it installs.
  To change one: edit the file, bump `pkgrel`, refresh checksums with
  `makepkg -g`, install with `makepkg -si`, and commit with a message saying
  why. Changes there reach every future install, and the next `git pull`
  brings them to this machine.
- `docs/agent-environment.md` is the design; `docs/ROADMAP.md` is what's done
  and what's next.
- `scripts/test-install.sh` installs and boots the system in a VM; use it for
  changes to the installer or the start.

For a quick personal tweak, a per-user file from the map is enough. For
something the user wants on every Den Den machine, change the package.

## Changing any other program

Every program on this system can be rebuilt from source here. To modify one:

```sh
expac -S %e <package>        # its pkgbase, the name its recipe is filed under
cd /src
pkgctl repo clone --protocol=https <pkgbase>
cd <pkgbase>
# edit the PKGBUILD, or add a patch to source=() and apply it in prepare()
makepkg -si
git commit -am '<what you changed and why>'
```

Packages from `[cachyos]` (`pacman -Si <package>` shows the repository) have
their recipes in https://github.com/CachyOS/CachyOS-PKGBUILDS instead.

Until a `den src` command exists, the next pacman update of a package you
rebuilt replaces your build. Tell the user which packages you rebuilt.

## Where to look

- Logs: `journalctl`, `journalctl --user`, `/var/log/pacman.log`
- Snapshots: `snapper -c root list`
- Backups (on the Den Den USB stick): `denden-backup status`; restore a file
  with `denden-backup restic restore latest --target <dir> --include <path>`
