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

if [[ ! -f /etc/pacman.d/cachyos-mirrorlist ]]; then
  echo "error: CachyOS mirrorlist missing; run: sudo ./scripts/setup-build-host.sh" >&2
  exit 1
fi

# Build packages/ into the local repo first. makepkg refuses root, so drop back
# to the user who invoked sudo.
if [[ -n ${SUDO_USER:-} && ${SUDO_USER} != root ]]; then
  sudo -u "${SUDO_USER}" -- "${repo_root}/scripts/build-packages.sh"
elif [[ ! -f ${repo_root}/repo/x86_64/denden.db.tar.gz ]]; then
  echo "error: local repo not built; run scripts/build-packages.sh as a normal user first" >&2
  exit 1
fi

rm -rf -- "${work_dir}"
mkdir -p -- "${work_dir}"
build_start="$(mktemp)"
trap 'rm -f -- "${build_start}"' EXIT

# mkarchiso needs absolute repo paths, which depend on where this clone lives.
pacman_conf="${work_dir}/pacman.conf.in"
sed "s|@DENDEN_REPO@|${repo_root}/repo/\$arch|" "${repo_root}/archiso/pacman.conf" > "${pacman_conf}"

# The installer installs Den Den's own packages from a copy of the local repo
# inside the image, so build from a copy of the profile with the repo added.
profile="${work_dir}/profile"
cp -a -- "${repo_root}/archiso" "${profile}"
mkdir -p -- "${profile}/airootfs/opt/denden/repo"
cp -a -- "${repo_root}"/repo/x86_64/{denden.db,denden.db.tar.gz,denden.files,denden.files.tar.gz,*.pkg.tar.zst} \
  "${profile}/airootfs/opt/denden/repo/"

mkarchiso -v -C "${pacman_conf}" -w "${work_dir}" -o "${out_dir}" "${profile}"

# mkarchiso can report failure (e.g. a mirror timeout during pacstrap) and
# still exit 0, so only trust a freshly written ISO.
iso="$(find "${out_dir}" -maxdepth 1 -name '*.iso' -newer "${build_start}" -print -quit 2>/dev/null)"
if [[ -z ${iso} ]]; then
  echo "error: mkarchiso finished but produced no ISO; see the log above" >&2
  exit 1
fi
echo "ISO written to ${iso}"
