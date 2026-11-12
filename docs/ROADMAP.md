# Roadmap

Goal: an environment where AI agents can do real work on the machine
effectively and safely, under human supervision, and where every part of the
system can be modified from local source. The design is in
[agent-environment.md](agent-environment.md).

Each item lands as its own commit against the vanilla baseline.

## 0. Baseline
- [x] Import vanilla `releng` profile (archiso v92)
- [x] Stock ISO builds in Arch WSL and is flashed to USB
- [ ] Stock ISO boots on real hardware
- [ ] Pick a name; set `iso_name`, `iso_label`, `iso_publisher`, `iso_application`

## 1. Agent-ready base
- [x] CachyOS repo and `linux-cachyos` kernel in the live image (generic x86-64)
- [x] `packages/` PKGBUILDs built into a local repo the ISO installs from
- [x] T3 Code (`t3code-cli`) in the image
- [ ] `t3code-cli` built from source (prebuilt kept as `t3code-cli-bin`)
- [ ] Toolchain for local builds in the image: `base-devel`, `devtools` (`pkgctl`), `git`
- [ ] `bubblewrap`, `snapper` in the image
- [ ] Installer that lays the system out on Btrfs and picks CachyOS v3/v4/znver4 repos per CPU
- [ ] `/etc/denden/AGENTS.md`: the system contract agents load

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
