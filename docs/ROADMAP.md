# Roadmap

Goal: an environment where AI agents can do real work on the machine
effectively and safely, under human supervision. The design is in
[agent-environment.md](agent-environment.md).

Each item lands as its own commit against the vanilla baseline.

## 0. Baseline
- [x] Import vanilla `releng` profile (archiso v92)
- [x] Stock ISO builds in Arch WSL and is flashed to USB
- [ ] Stock ISO boots on real hardware
- [ ] Pick a name; set `iso_name`, `iso_label`, `iso_publisher`, `iso_application`

## 1. Agent-ready base
- [ ] Agent CLIs preinstalled (Claude Code, Codex) plus the daily dev toolchain
- [ ] `bubblewrap`, `btrfs-progs`, `snapper` in the image
- [ ] Installer that lays the system out on Btrfs subvolumes
- [ ] `/etc/ethan/AGENTS.md`: the system contract agents load
- [ ] `packages/` with PKGBUILDs for the OS layer, and a local repo the ISO pulls from

## 2. Read-only contract
- [ ] `ethand` daemon on a Varlink socket
- [ ] `ethan` CLI (`--json` everywhere): `machine inspect`, `package query`, `service status`, `history query`
- [ ] MCP server exposing the same operations

## 3. Agent sessions
- [ ] `ethan session create|list|review|commit|discard`
- [ ] Workspace snapshots, bubblewrap sandbox, cgroup limits
- [ ] Brokered secrets for model API keys

## 4. Broker
- [ ] Capability grants per session, polkit policy, audit log
- [ ] Mutations (`package install`, `service enable`, …) with automatic root snapshots and rollback

## 5. History & memory
- [ ] Event log fed by pacman hooks, snapper, journald, broker audit
- [ ] Persistent per-agent memory

## 6. Agent desktops
- [ ] Headless Wayland output per session for computer use
- [ ] Supervisor view in the human shell (Niri-based)
