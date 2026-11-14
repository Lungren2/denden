# Den Den

You are running on Den Den, an Arch Linux-based system built for coding
agents working under a human's supervision. This file is the system contract.
Read it before changing anything outside your project.

## The machine

- Arch Linux with CachyOS repositories and the `linux-cachyos` kernel.
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
6. Don't delete snapshots or disable snap-pac. If the system needs rolling
   back, tell the user which snapshot and let them decide.

## Changing a program

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
their recipes in https://github.com/CachyOS/CachyOS-PKGBUILDS instead. Den
Den's own packages are in `/src/denden/packages`.

Until a `den src` command exists, the next pacman update of a package you
rebuilt replaces your build. Tell the user which packages you rebuilt.

## Where to look

- Logs: `journalctl`, `/var/log/pacman.log`
- Snapshots: `snapper -c root list`
- How this system is designed: `/src/denden/docs/agent-environment.md`
