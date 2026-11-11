# Agent environment

The point of this distro: a machine designed for AI agents to work on
effectively, with a human supervising. Everything else (desktop, hardware
profiles, recovery) serves that.

## Principles

1. **Capabilities, not god mode.** Agents run unprivileged. Anything that
   changes the system goes through a broker that authorizes, executes and
   audits it.
2. **Structured first, pixels last.** Prefer the narrowest interface that can
   do the job:
   `ethan` API → app-specific API → shell → accessibility → visual computer use.
3. **A small, predictable world.** An agent sees a consistent layout and a
   short system contract, and descends into raw Linux only when it needs to
   (and is allowed to).
4. **Every change is reviewable.** Agent work happens in a session that ends in
   *review → commit* or *discard*, for files and system changes alike.
5. **History is recorded, not remembered.** What happened on the machine is an
   append-only event log agents can query, not something a model reconstructs.

## What agents actually consume

The agents in use (Claude Code and Codex, orchestrated from T3 Code) already
speak four things: a shell, files, git, and **MCP tools**, plus instruction
files (`AGENTS.md` / `CLAUDE.md`). So the environment is delivered through
those channels instead of inventing a new one:

| Channel | What the OS provides |
| --- | --- |
| Instructions | `/etc/ethan/AGENTS.md`: the system contract, loaded into every session |
| Tools | `ethan` MCP server: the same operations as the CLI, typed |
| Shell | `ethan` CLI with `--json` on every command |
| Files | A fixed session layout (below) |

## Architecture

```
agents (Claude Code, Codex, …)  ← supervised from T3 Code / terminal
        │  MCP · `ethan` CLI · AGENTS.md
        ▼
ethand  (system daemon, Varlink socket)
  ├─ broker    capability grants per session, polkit policy, audit
  ├─ sessions  sandbox + workspace snapshot + cgroup slice
  ├─ history   append-only event log (SQLite)
  └─ adapters  pacman · systemd · btrfs/snapper · journald · niri IPC (later)
        ▼
Linux
```

The human shell and the agent API both read the same daemon state. Neither
mutates the system on its own.

## Agent sessions

An agent session is the unit of work: one task, one sandbox, one reviewable
result.

| Part | Implementation |
| --- | --- |
| Workspace | Btrfs snapshot of the project (or a git worktree), so discard is free |
| Sandbox | bubblewrap inside a transient systemd scope (resource limits, killed with the session) |
| Network | Allowed by default for package registries and model APIs; per-session policy later |
| Secrets | Brokered: API keys are injected per-session by `ethand`, never written to disk in the sandbox |
| Privilege | None. System changes are requests to the broker, recorded against the session |

Inside a session the agent sees:

```
/workspace   the project, writable (snapshot)
/system      ethan API socket; the computer it may ask to change
/history     read-only event log
/memory      persistent notes and skills across sessions
/secrets     brokered credentials (tmpfs)
/desktop     headless Wayland output for computer use (later)
```

Lifecycle: `create → run → review → commit | discard`. Review shows the
workspace diff plus every brokered system change. Before applying any system
change, the broker takes a Btrfs snapshot of root, so a bad change is undone
with one rollback.

## The `ethan` contract (first cut)

Read-only operations come first. Mutations are added only once they go
through the broker.

```
ethan machine inspect              hardware, kernel, firmware, health
ethan package query|install|remove
ethan service status|enable|disable
ethan snapshot list|create|rollback
ethan history query "<text>" [--since 3d]
ethan session create|list|review|commit|discard
```

Every command takes `--json`, and the MCP server exposes the same schema as
tools.

## Where it's built

- The OS layer ships as **Arch packages** (`packages/` PKGBUILDs) that install
  on any Arch system. The ISO just includes them. The same layer can later sit
  on top of CachyOS repos without changing anything here.
- **Develop in Arch WSL.** Systemd, bubblewrap, pacman and the daemon all work
  there. Btrfs features can use a loopback Btrfs image. Only agent desktops and
  hardware features need real hardware.

## Milestones

1. **Agent-ready base:** agent CLIs and the dev toolchain in the image, a
   Btrfs-on-install layout, and `/etc/ethan/AGENTS.md`.
2. **Read-only contract:** `ethand` + `ethan` CLI + MCP server for `machine`,
   `package query`, `service status`, `history query`.
3. **Sessions:** sandboxed agent sessions with workspace snapshots and
   review/commit/discard.
4. **Broker:** capability grants and audited system mutations with automatic
   root snapshots.
5. **History & memory:** event log fed by pacman hooks, snapper, journald and
   broker audit, plus per-agent memory.
6. **Agent desktops:** headless Wayland per session for computer use, and a
   supervisor view in the human shell.
