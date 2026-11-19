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
- Package repositories in priority order: `[denden-local]` (programs changed on
  this machine with `den src`), `[denden]` (this system's own packages),
  `[cachyos]`, then Arch's `core` and `extra`.
- Btrfs. Root (`/`) is snapshotted before and after every pacman transaction;
  `/home` and `/src` are snapshotted hourly. `snapper list-configs` and
  `snapper -c root list` show them, and the recovery menu (hold a key as Den
  Den starts) can boot any root snapshot.
- Toolchains: Node (npm, pnpm), Bun, Rust, Python (`uv`), .NET, and Docker
  with Compose and Buildx. The user is in the `docker` group. A project that
  needs other versions pins them in its `mise.toml` (`mise use node@22`);
  mise's shims are on `PATH` ahead of the system's, so pinned versions win
  inside that project.
- Inbound network connections, to the machine and to containers' published
  ports, are refused except over Tailscale. To expose a
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
8. Leave nothing behind from your own testing: delete the test files,
   scratch repositories, sessions, branches, containers, images and build
   output you made, and don't commit tests that only checked a one-off
   change.

## Map of the system

Each part, what runs it, where to change it, and the Den Den package that
ships it (its source is `/src/denden/packages/<package>`). Per-user files
override the system ones, so try a change there first.

| Part | What runs it | Change it in | Package |
| --- | --- | --- | --- |
| Start: OS picker, recovery menu, splash | rEFInd → Limine → Plymouth | `denden-boot-update` writes `/boot/EFI/denden/refind.conf`; `/boot/limine.conf`, `/etc/default/limine`; kernel options in `/etc/kernel/cmdline` (then `limine-update`); splash theme `/usr/share/plymouth/themes/denden` | `denden-boot` |
| Login | greetd, logging the user straight in | `/etc/greetd/config.toml` | `denden-installer` |
| Windows and shortcuts | niri | `~/.config/niri/config.kdl` (copy of `/etc/niri/config.kdl`; reloads live; `niri msg` for state) | `denden-desktop` |
| Taskbar, launcher, quick settings, notifications, wallpaper, lock screen | Noctalia (Den Den's patched build), started by `denden-shell`; styled after T3 Code's design system (its colours, Inter, glass, radii) | `~/.config/noctalia/config.toml` (wins), Den Den's defaults in `/usr/share/denden/noctalia/denden.toml`, palette `DenDen.json`; reloads live; `noctalia msg …` | `denden-desktop`, `noctalia` |
| First-run setup (GitHub, Tailscale, backups) | `denden-setup`, a page on Electron in T3 Code's dialog style; opens at the first login until finished | `/usr/lib/denden-setup`; done marker `~/.local/state/denden/setup-done` | `denden-setup` |
| Terminal | Ghostty running fish, with a starship prompt | `~/.config/ghostty/config.local` over Den Den's `/usr/share/denden/ghostty/config`; `~/.config/fish/config.fish` over `/usr/share/fish/vendor_conf.d/denden.fish`; prompt `~/.config/starship.toml` over `/usr/share/denden/starship.toml` | `denden-desktop` |
| Browser and default apps | Helium | `~/.config/mimeapps.list` over `/etc/xdg/mimeapps.list` | `denden-desktop` |
| GTK app theme | dconf | `gsettings set org.gnome.desktop.interface …`; defaults in `/etc/dconf/db/local.d/00-denden` | `denden-desktop` |
| Agents | T3 Code (desktop app, `t3`), Claude Code, Codex | this file: `/etc/denden/AGENTS.md`, linked as each agent's user-level instructions. It is written from Den Den's `/usr/share/denden/AGENTS.md` plus this machine's own rules in `/etc/denden/AGENTS.local.md`: put a rule for this machine there (with sudo), never in `AGENTS.md`, which every update rewrites; it is merged in at once and survives updates | `denden-base`, `t3code-*` |
| Shell environment | bash (login shell; fish in the terminal starts from it), mise | `/etc/profile.d/denden.sh` (login shells), `/usr/lib/environment.d/50-denden.conf` (desktop session) | `denden-base` |
| GitHub repositories | `denden-repos` (user timer) | `denden-repos.service`/`.timer` | `denden-base` |
| Network and remote access | NetworkManager, Tailscale (`denden-tailscale`), `denden-firewall` | `/usr/share/denden/firewall.nft` | `denden-base` |
| Machine API (`den doctor`, `den machine`/`package`/`service`/`history`, the `den` MCP tools) | `dend` (socket-activated system service, read-only) | interfaces in `/usr/share/varlink/io.denden.*.varlink`; MCP registration: `/etc/codex/config.toml`, and `claude mcp add --scope user` once per user (`den-claude-mcp.service`) | `dend`, `den` |
| Agent sessions (`den session`, `den secret`) | bubblewrap in a systemd scope (`den-sessions.slice`); workspaces are Btrfs snapshots | sessions in `~/.local/share/den/sessions`, project bases in `~/.cache/den/bases`, log `~/.local/share/den/sessions.log`; sandbox and limits in `/usr/lib/den/session.py`; secrets in the Secret Service | `den` |
| Package updates | `denden-update`, pacman | `denden-update check` reports recipe, release and runtime changes; after reviewing recipes, `denden-update apply` builds, publishes to `/var/lib/denden/repo`, then runs a full upgrade; daily check: `denden-updates.timer` (user); new upstream releases: `denden-update bump`, daily from `denden-recipes.timer`, which leaves a failed build on branch `recipe-update/<package>-<version>` (log in `~/.local/state/denden/recipe-updates/`): commit the fix on that branch, then `denden-update bump <package>` builds, lands and publishes it | `denden-updates` |
| Backups | `denden-backup` (restic to the Den Den USB stick) | `/usr/share/denden/backup-excludes`; `denden-backup.timer` | `denden-base` |
| Lid and power | systemd-logind | `/usr/lib/systemd/logind.conf.d/50-denden.conf` (override in `/etc/systemd/logind.conf.d/`) | `denden-base` |
| Installer and live USB | `denden-install`, archiso | `/src/denden/archiso` | `denden-installer` |

## Changing Den Den itself

Den Den is built from `/src/denden`, a git clone of github.com/Lungren2/denden:

- `packages/<name>/` holds each package's PKGBUILD and the files it installs.
  To change one: edit the file, bump `pkgrel`, refresh checksums with
  `makepkg -g`, install with `makepkg -si`, and commit with a message saying
  why. Changes there reach every future install, and the next `git pull`
  brings them to this machine. After reviewing recipe changes, run
  `denden-update apply` as the user to build installed Den Den packages, publish
  them into the local repo, and run a full pacman upgrade. Do not use sudo for
  the build itself. Bump `pkgrel` when rebuilding the same upstream version.
- `docs/agent-environment.md` is the design; `docs/ROADMAP.md` is what's done
  and what's next.
- `scripts/test-install.sh` installs and boots the system in a VM; use it for
  changes to the installer or the start.

For a quick personal tweak, a per-user file from the map is enough. For
something the user wants on every Den Den machine, change the package.

## Changing any other program

Every program on this system can be changed from its source with `den src`:

```sh
den src get <package>     # recipe + source of the installed version → /src/<pkgbase>
cd /src/<pkgbase>         # a git repo: edit the source under src/, or the PKGBUILD
git commit -am '<what you changed and why>'
den src build <package>   # build, publish to [denden-local], install
den src diff <package>    # your changes against the distro's package
den src drop <package>    # back to the distro's package; the tree stays
```

The tree's `upstream` branch is the package exactly as the distro builds it
(the recipe plus the source after `prepare()`); `main` is that plus your
commits. Builds go to the `[denden-local]` repo, ranked above every other repo, so
your build stays installed through updates. When the distro ships a newer
version, `den src list` and the daily update check say so; `den src rebase
<package>` carries your commits onto it (on conflicts it stops for you to
resolve them with git), then `den src build`. Tell the user which packages
you changed.

Den Den's own packages are not fetched this way: their recipes are in
`/src/denden/packages` (see above).

## Agent sessions

For work that should be sandboxed and reviewed before it lands, use a
session rather than the project directly:

```sh
den session create ~/Projects/<repo> [--secret ANTHROPIC_API_KEY]   # prints the session name
den session run <session> -- <command>…   # in the sandbox, at /workspace
den session review <session>              # commits, changes, diff
den session commit <session> [--merge]    # back to the project as branch den/<session>
den session discard <session>
```

The workspace is a Btrfs snapshot of the project at its last commit with its
dependencies installed (ready in well under a second). Inside the sandbox the
system and the project are read-only, `sudo` doesn't work, the home directory
is hidden except the package caches and the agents' settings, `$PORT` (and
`$DEN_PORTS`, 100 ports) and `$COMPOSE_PROJECT_NAME` are the session's own,
the machine API is at `/system`, and granted secrets are in the environment
and `/secrets`. Docker is out of reach unless the session is created with
`--docker`; its socket is root on this machine, so such a session isn't
sandboxed from it (until milestone 6's rootless Docker): use it only when the
task needs containers. `den secret set NAME` stores a secret (an API key) that
sessions can be granted. At most `$DEN_SESSIONS_MAX` sessions run at once.
A project's dependencies install with its lockfile's tool, or its executable
`.den/setup` if it has one.

## Where to look

Ask the machine first: `den doctor` says whether it's healthy and what needs
a look (disk space and health, failed services, T3 Code, Tailscale, backups,
snapshots, updates). The same API answers, read-only and with `--json`:

```sh
den machine inspect                    # hardware, kernel, firmware, disks, free space
den package query <name>…              # installed/available versions, repo, source tree
den package query --search <text>
den service status <unit>… [--user]    # or no units: every failed one
den history query [text] --since 3d -v # package changes with their root snapshots, boots
```

In Claude Code and Codex these are MCP tools too (`den` server:
`machine_doctor`, `machine_inspect`, `package_query`, `service_status`,
`history_query`); prefer them to parsing shell output. They come from
`dend`, a Varlink service on `/run/den/io.denden` (`varlinkctl introspect
/run/den/io.denden`).

- Logs: `journalctl`, `journalctl --user`, `/var/log/pacman.log`
- Snapshots: `snapper -c root list`
- Backups (on the Den Den USB stick): `denden-backup status`; restore a file
  with `denden-backup restic restore latest --target <dir> --include <path>`
