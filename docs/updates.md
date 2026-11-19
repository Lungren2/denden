# Updates, the machine API and local source

## Package updates

`denden-update check` reports differences between installed Den Den packages,
the local repository, and recipes in `/src/denden`. It also checks the latest
stable T3 Code and Noctalia releases, and the runtime versions embedded by
T3 builds. `--json` returns the same report for agents. The user timer
`denden-updates.timer` checks daily and sends a notification when the report
changes; a failed lookup is reported, never treated as “up to date”.

### New upstream releases

New stable T3 Code and Noctalia releases don't wait for a person:
`denden-recipes.timer` runs `denden-update bump` daily. It moves each recipe
to the new release on its own branch (`recipe-update/<package>-<version>`) in
a separate worktree, with fresh checksums, and builds it if the package is
installed. A build that works is fast-forwarded into `main` and published, so
it installs with the next full upgrade; one that fails, usually a patch that
no longer applies, stays on its branch with the build log in
`~/.local/state/denden/recipe-updates/` and a notification asking for an
agent to finish it: commit the fix on that branch, and the next run (or
`denden-update bump <package>`) builds it again and lands it. A branch that
builds while `/src/denden` has uncommitted changes waits for the next run;
if `main` has moved, the update is rebased onto it first.

### Applying

After reviewing and updating recipes, run `denden-update apply` as your user.
It first performs a full system upgrade, then builds installed Den Den packages
under a memory/CPU limit, publishes completed packages into
`/var/lib/denden/repo`, and performs another full upgrade to install them.
Build dependencies and publication use sudo; makepkg runs as the user. Failed
builds stop before publication. Cached packages are reused; bump `pkgrel` when
rebuilding the same upstream version. Builds and sources stay outside the
checkout; package archives live in its ignored `repo/` directory.

To build a subset: `scripts/build-packages.sh denden-base denden-desktop`.
`sudo denden-publish PACKAGE…` publishes completed archives. Existing archives
are retained; a different archive with the same filename is refused, and an
older version cannot replace a newer repository entry. Publication places
archives before updating the database. The installed `[denden]` repository
already has priority over CachyOS and Arch, including for our patched Noctalia.

### What it never does

Checks do not refresh pacman's live sync databases or install anything.
Upstream releases still need a recipe bump, checksum refresh, patch review and
successful build. This is a local repository, not a signed remote distribution
service. No new upstream versions or recipe code are installed unattended.
The GitHub repository timer can fast-forward a clean checkout; the updater
never pulls or rewrites your working tree.

## The machine API

`den doctor` checks the machine's health: disk space and SMART health,
failed services, T3 Code, Tailscale, the last backup, snapshots and package
updates. `den machine inspect`, `den package query`, `den service status`
and `den history query` answer the rest (every one takes `--json`), and
`den mcp` serves the same operations to agents as MCP tools; Codex gets it
from `/etc/codex/config.toml` and each user's Claude Code at first login.

They're clients of `dend`: a read-only Varlink service on
`/run/den/io.denden`, started on demand by `dend.socket` and running as root
in a read-only sandbox so it can read SMART data, snapper and each user's
services. Its interfaces are `io.denden.Machine`, `.Package`, `.Service` and
`.History` (`varlinkctl introspect /run/den/io.denden`). History comes from
records the machine already keeps (pacman's log with the snapshots around
each transaction, snapper, the journal's boots) until milestone 7's event log.

## Agent sessions

`den session create <project>` gives an agent its own workspace: a Btrfs
snapshot of the project at its last commit with its dependencies installed,
ready in 0.05 s and free until it changes. `den session run` runs commands
there in a bubblewrap sandbox: the system and the project read-only, no sudo,
the home directory hidden except package caches and the agents' settings, its
own ports and Compose project, memory and CPU limits, and only the secrets
(`den secret set`) the session was granted. `den session review` shows what
changed; `den session commit` brings it back to the project as branch
`den/<session>`, and `discard` throws it away. The measurements behind the
design are in [session-storage.md](session-storage.md).

## Changing any program

`den src get <package>` puts the distro's recipe and the source of the
installed version in `/src/<pkgbase>` as a git repo; commit your changes there
and `den src build <package>` installs them from the `[denden-local]` repo,
which shadows every other repo. `den src diff` shows your changes, `den src
rebase` carries them onto a newer distro version (the daily update check says
when one is out), and `den src drop` goes back to the distro's package.

## Backups

With the Den Den USB stick plugged in, the last step of **Set up Den Den**
adds a backup partition after the image (the stick stays bootable) and shows
the key the backups are encrypted with; keep it in your password manager.
After that, `/home` and `/src` are backed up whenever the stick is plugged in
and daily while it is, and a notification asks for the stick when the last
backup is three days old. Restore with
`denden-backup restic restore latest --target <dir> --include <path>`.
