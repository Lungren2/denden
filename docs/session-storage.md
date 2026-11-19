# Session storage

What an agent session's workspace is made of, decided by measuring the real
workload: many parallel copies of a project with its dependencies installed.

## The measurement

Den Den machine: Ryzen 5 5600X, SanDisk SATA SSD, Btrfs (zstd:1). Workload:
T3 Code's monorepo (pnpm, 239,000 files: 338 MB of source and 2.8 GB of
`node_modules`), the kind of tree agents work in many times over. Eight
workspaces were made one after another, as sessions start, with pnpm's store
already warm. Space is what the filesystem really used (for VDO, its physical
blocks), after a sync.

| Strategy | Ready in | Space per workspace | Discard 8 |
| --- | --- | --- | --- |
| Btrfs snapshot of a ready base | 0.05 s | 0 MB | 0.3 s ¹ |
| Btrfs snapshot of a base 50 commits behind, then `git checkout` + `pnpm install` | 8.9 s | 426 MB | 4.6 s |
| `git worktree` + `pnpm install` | 7.6 s | 370 MB | 41 s |
| `git worktree` alone, no dependencies | 3.3 s | 287 MB | 8.5 s |
| `cp --reflink` of a ready workspace | 11.1 s | 401 MB | 92 s |
| Plain copy (`cp --reflink=never`) | 35.2 s | 1,596 MB | 92 s |
| XFS on VDO: `git worktree` + `pnpm install` ² | 74 s | 37 MB | 20 s each |
| XFS on VDO: plain copy ² | 106 s | ~0 MB ³ | 6.8 s each |

¹ Deleting a subvolume outright needs root, or the `user_subvol_rm_allowed`
mount option; without either, emptying it file by file took 112 s.
² VDO (dm-vdo with dedup and compression, on a loop file on the same SSD,
two workspaces each): its userspace (`vdoformat`) isn't packaged by Arch or
CachyOS, so it was built from source for the test only.
³ Physical blocks in use fell by 44 MB as VDO compacted its own metadata:
the copies were deduplicated completely.

What the numbers say:

- **Per-file metadata is the real cost**, not file contents. pnpm already
  shares contents through its store (reflinks on Btrfs), yet every worktree
  still costs ~370 MB: the inodes and extent records of 239,000 files, and the
  small files Btrfs stores inline. A reflink copy costs the same for the same
  reason, and is slower than letting pnpm link from its store.
- **A snapshot shares the metadata too**, so it costs nothing until the
  session changes files, and is ready in 50 ms. Only a *current* base is that
  cheap: one 50 commits behind cost as much as a fresh worktree to bring up
  to date. So the base is refreshed when a session starts, once per project
  change, not once per session.
- **VDO saves space and costs time.** Its inline deduplication brought a
  worktree down to 37 MB, a tenth of Btrfs, and a full copy to nothing at
  all, but made a worktree ten times slower and a copy three times slower,
  and copying pnpm's store onto it ran at ~11 MB/s. On this machine space is
  not the constraint (183 GB free) and session start-up time is. It would also
  need its own partition and an unpackaged userspace.

## The decision

Each project has a **base**: a shared clone (`git clone --shared`, so no
objects are copied) at the project's current commit with its dependencies
installed, as a Btrfs subvolume in `~/.cache/den/bases`. A session's
**workspace is a snapshot of that base**, made when the session starts, after
the base is brought up to date (fetch, checkout, and the install command
again only when a lockfile changed).

- The base and every session see the tree at `/workspace`, so absolute paths
  tools write into it (Python virtualenvs, Cargo fingerprints) stay valid in
  the snapshot, and a base that has been built gives each session a warm
  build directory.
- Sessions live in `~/.local/share/den/sessions` (backed up, minus
  dependencies and build output); bases are a cache. Both are subvolumes, so
  the hourly snapshots of `/home` leave them out.
- Btrfs is mounted with `user_subvol_rm_allowed`, so discarding a session
  deletes its snapshot at once, without root. Subvolumes owned by root
  (snapper's, Docker's) stay protected by their permissions.

Plain worktrees remain the fallback for a project on a filesystem without
snapshots: same result, ~8 s and ~400 MB each for a tree this size.
