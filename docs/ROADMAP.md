# Roadmap

Goal: an environment where AI agents can do real work on the machine
effectively and safely, under human supervision, and where every part of the
system can be modified from local source. The design is in
[agent-environment.md](agent-environment.md).

Each item lands as its own commit against the vanilla baseline.

## 0. Baseline
- [x] Import vanilla `releng` profile (archiso v92)
- [x] Stock ISO builds in Arch WSL and is flashed to USB
- [x] Den Den ISO (linux-cachyos, t3code-cli) boots on real hardware
- [x] Pick a name (Den Den); set `iso_name`, `iso_label`, `iso_publisher`, `iso_application`

## 1. Agent-ready base
- [x] CachyOS repo and `linux-cachyos` kernel in the live image (generic x86-64)
- [x] `packages/` PKGBUILDs built into a local repo the ISO installs from
- [x] T3 Code (`t3code-cli`) in the image
- [x] `t3code-cli` built from source (prebuilt kept as `t3code-cli-bin`)
- [x] Codex (`openai-codex`, built from source by Arch) and Claude Code
  (`claude-code` from CachyOS: the vendor binary, since its source isn't
  public) in the live image
- [x] `denden-base`: the agents, toolchains (Node/npm/pnpm, Bun, Rust,
  Python/uv, .NET), Docker Engine with Compose and Buildx, `base-devel`,
  `devtools`, snapper, snap-pac, bubblewrap
- [x] `/etc/denden/AGENTS.md`, loaded by Claude Code (`/etc/claude-code/CLAUDE.md`)
  and Codex (`~/.codex/AGENTS.md` via `/etc/skel`)
- [x] `t3code-desktop`: the T3 Code desktop app built from source against
  Arch's Electron 44
- [x] `denden-desktop`: a Niri session that logs in automatically to T3 Code
  full screen; PipeWire; NVIDIA (`linux-cachyos-nvidia-open`); Godot, Blender
- [x] `denden-install`: Btrfs subvolumes (`@`, `@home`, `@src`, `@snapshots`,
  `@log`, `@pkg`, `@docker`), Limine with bootable snapshots, snap-pac, hourly
  snapshots of `/home` and `/src`, CachyOS v3/v4/znver4 repos per CPU, this
  repo cloned to `/src/denden`
- [x] Installer tested in a VM (`scripts/test-install.sh`): whole-disk install,
  boot, autologin into Niri with T3 Code; the session checked nested in WSLg
- [x] `denden-boot`: no text on a normal start. A rEFInd picker with Den Den
  and Windows icons (Windows found on any disk), Limine hidden behind it as
  the recovery menu with bootable snapshots, a Plymouth splash; the live USB
  boots without a menu
- [x] Installed on real hardware (Ryzen 5 5600X, RTX 3050): a dedicated SATA
  SSD beside the Windows NVMe; the picker offers both systems

Until the broker (milestone 6), agents run as the user, who has passwordless
sudo. Snapshots before every pacman transaction are the safety net, and
`AGENTS.md` requires agents to say what they will run before using `sudo`.

## 2. Daily driver
What the machine needs before it is the one you work on every day.
- [ ] Microsoft Edge as the default browser (`microsoft-edge-stable-bin`: no
  public source), Helium as the alternative (from source, prebuilt kept as
  `-bin`); Firefox removed
- [ ] `linux-cachyos-lts` beside `linux-cachyos`, as the fallback kernel in
  the recovery menu
- [ ] Reachable from anywhere: T3 Code's server runs as a user service that
  starts at boot without a login (`t3 service install`), paired with T3
  Connect; Tailscale for SSH and direct routes; inbound traffic refused except
  over Tailscale
- [ ] Agent CLIs found from a non-interactive login shell, which is what T3
  Code's background service uses
- [ ] Per-project runtimes with mise (a project's `mise.toml` wins over the
  system toolchains)
- [ ] Terminal tools: fzf, zoxide, lazygit, git-delta, btop, dust, duf,
  hyperfine, yq, tmux
- [ ] Backups with restic of `/home`, `/src` and T3 Code's state
  (`~/.t3/userdata`), leaving out caches, worktrees and Docker; a restore
  tested, not just a backup
- [ ] Stays awake on AC power, so remote sessions don't vanish

## 3. Local source
- [ ] `/src` tree; this repo at `/src/denden`
- [ ] `den src get|build|diff|rebase|drop`
- [ ] `[local]` overlay repo ranked above all others
- [ ] Rebase-on-update for modified packages, with an agent session on conflicts

## 4. Read-only contract
- [ ] `dend` daemon (Rust) on a Varlink socket
- [ ] `den` CLI (`--json` everywhere): `machine inspect`, `package query`, `service status`, `history query`
- [ ] `den doctor`: disk space, SSD health, failed units, T3 Code service,
  Tailscale, age of the last backup
- [ ] MCP server exposing the same operations

## 5. Agent sessions
- [ ] `den session create|list|review|commit|discard`
- [ ] Workspace snapshots, bubblewrap sandbox, cgroup limits
- [ ] Storage measured on the real workload (many parallel worktrees with
  dependencies installed): Btrfs snapshots and reflinks against plain
  worktrees, with XFS on VDO as the comparison; the result decides the
  session workspace
- [ ] Shared package caches (pnpm store, Cargo, uv, npm); each session gets
  its own ports, Compose project name and databases
- [ ] A cap on concurrent sessions, so a build storm doesn't stall the desktop
- [ ] Brokered secrets for model API keys

## 6. Broker
- [ ] Capability grants per session, polkit policy, audit log
- [ ] Mutations (`package install`, `service enable`, …) with automatic root snapshots and rollback
- [ ] Agents lose the `docker` group (it is root by another name); sessions
  get rootless Docker

## 7. History & memory
- [ ] Event log fed by pacman hooks, snapper, journald, broker audit
- [ ] `den why <file|unit|package>`: who changed it, in which session, and why
- [ ] `den session diff|undo|replay <id>`
- [ ] Memory in two tiers: a small set always loaded (you, this machine), and
  everything else searched on demand (full-text over history and past
  sessions)
- [ ] Skills: a session that solved something can be saved as a procedure the
  next session reuses

## 8. Agent desktops
- [ ] Headless Wayland output per session for computer use, with its own
  virtual input: an agent's clicks can only reach its own desktop
- [ ] Supervisor view in the human shell (Niri-based): live views of every
  agent desktop; watching grants no input, Take Control does, until you leave
- [ ] Zoomed-out overview of the whole desktop and the agents' desktops, to
  pick a place and fly into it
- [ ] Each desktop session recorded into history: what the agent saw, did and
  changed

## 9. Boot drive
The USB stick becomes the portable half of the machine: install, repair and
carry your environment to new hardware.
- [ ] Graphical start menu on the live USB: Install, Live desktop, Recovery,
  Hardware diagnostics, Secure erase
- [ ] Graphical installer, then a conversational one: a chat that compiles a
  machine profile you review before it builds the machine
- [ ] Machine profiles: a reproducible recipe (packages, configuration,
  dotfiles revision) captured from a running machine and rebuilt on another
- [ ] Encrypted vault on the drive: preferences, agent memory and machine
  profiles. Credentials stay in their own stores; the vault holds references
- [ ] Failed-start recovery: a start that doesn't finish offers the last good
  snapshot and lists what changed since

## 10. Stable releases
- [ ] Update channels: a tested Stable snapshot of Arch and CachyOS ahead of
  machines, and Bleeding for following upstream directly
- [ ] Release tests: install, boot, desktop and recovery in a VM on every
  build, then on real hardware
- [ ] Secure Boot keys enrolled by the installer (sbctl); optional disk
  encryption with TPM unlock and a recovery key
- [ ] A reference laptop (Framework) on which every part works: suspend,
  battery limits, fingerprint, displays, firmware updates
- [ ] Fixes go upstream (kernel, Mesa, Niri, CachyOS) rather than living as
  local patches

## Later
Not scheduled; kept so the direction is written down.
- Framework's community-supported distro tier, then preinstalled machines
- A vault drive as hardware (a Framework expansion card)
- Home devices as context: presence, rooms and their history, behind the same
  broker as everything else
- A tablet
