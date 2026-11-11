#!/usr/bin/env bash
# Build the live ISO from ./archiso with mkarchiso.
#
# Must run as root on an Arch Linux host (bare metal, VM, or the Arch WSL
# distro) with the `archiso` package installed. Build from a clone on a Linux
# filesystem, not from /mnt/<drive>: NTFS checkouts lose the exec bits and
# symlinks the profile depends on.
set -euo pipefail

repo_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
work_dir="${WORK_DIR:-${repo_root}/work}"
out_dir="${OUT_DIR:-${repo_root}/out}"

if [[ ${EUID} -ne 0 ]]; then
  echo "error: mkarchiso needs root; re-run with sudo" >&2
  exit 1
fi
if ! command -v mkarchiso >/dev/null; then
  echo "error: mkarchiso not found; install it with: pacman -S archiso" >&2
  exit 1
fi
case "${repo_root}" in
  /mnt/[a-z]/*)
    echo "error: ${repo_root} is a Windows drive; clone the repo onto the Linux filesystem first" >&2
    exit 1
    ;;
esac

rm -rf -- "${work_dir}"
mkarchiso -v -w "${work_dir}" -o "${out_dir}" "${repo_root}/archiso"
echo "ISO written to ${out_dir}"
