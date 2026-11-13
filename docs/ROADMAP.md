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
- [ ] Installed on real hardware: a dedicated SSD beside the Windows disk,
  NVIDIA, the picker, splash and session on screen

Until the broker (milestone 5), agents run as the user, who has passwordless
sudo. Snapshots before every pacman transaction are the safety net, and
`AGENTS.md` requires agents to say what they will run before using `sudo`.

## 2. Local source
- [ ] `/src` tree; this repo at `/src/denden`
- [ ] `den src get|build|diff|rebase|drop`
- [ ] `[local]` overlay repo ranked above all others
- [ ] Rebase-on-update for modified packages, with an agent session on conflicts

## 3. Read-only contract
- [ ] `dend` daemon (Rust) on a Varlink socket
- [ ] `den` CLI (`--json` everywhere): `machine inspect`, `package query`, `service status`, `history query`
- [ ] MCP server exposing the same operations

## 4. Agent sessions
- [ ] `den session create|list|review|commit|discard`
- [ ] Workspace snapshots, bubblewrap sandbox, cgroup limits
- [ ] Brokered secrets for model API keys

## 5. Broker
- [ ] Capability grants per session, polkit policy, audit log
- [ ] Mutations (`package install`, `service enable`, …) with automatic root snapshots and rollback

## 6. History & memory
- [ ] Event log fed by pacman hooks, snapper, journald, broker audit
- [ ] Persistent per-agent memory

## 7. Agent desktops
- [ ] Headless Wayland output per session for computer use
- [ ] Supervisor view in the human shell (Niri-based)
