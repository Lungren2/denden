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
build_start="$(mktemp)"
trap 'rm -f -- "${build_start}"' EXIT
mkarchiso -v -w "${work_dir}" -o "${out_dir}" "${repo_root}/archiso"

# mkarchiso can report failure (e.g. a mirror timeout during pacstrap) and
# still exit 0, so only trust a freshly written ISO.
iso="$(find "${out_dir}" -maxdepth 1 -name '*.iso' -newer "${build_start}" -print -quit 2>/dev/null)"
if [[ -z ${iso} ]]; then
  echo "error: mkarchiso finished but produced no ISO; see the log above" >&2
  exit 1
fi
echo "ISO written to ${iso}"
