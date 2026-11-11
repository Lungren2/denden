#!/usr/bin/env bash
# Prepare an Arch Linux host (e.g. the Arch WSL distro) to build this ISO.
#
# Installs archiso and the package build tools, and trusts the CachyOS signing
# key and mirrorlist the profile's pacman.conf uses. The host's own repos are
# left alone. Safe to re-run; re-running also refreshes the CachyOS keyring
# and mirrorlist.
set -euo pipefail

cachyos_key=F3B607488DB35A47
cachyos_repo=https://mirror.cachyos.org/repo/x86_64/cachyos

if [[ ${EUID} -ne 0 ]]; then
  echo "error: needs root; re-run with sudo" >&2
  exit 1
fi

pacman -Syu --noconfirm --needed archiso base-devel git

if ! pacman-key --list-keys "${cachyos_key}" >/dev/null 2>&1; then
  pacman-key --recv-keys "${cachyos_key}" --keyserver hkps://keyserver.ubuntu.com
fi
pacman-key --lsign-key "${cachyos_key}"

# The keyring and mirrorlist package versions change, so look up the current
# filenames in the repo database rather than hard-coding them.
db_dir="$(mktemp -d)"
trap 'rm -rf -- "${db_dir}"' EXIT
curl -fsSL "${cachyos_repo}/cachyos.db" | bsdtar -xf - -C "${db_dir}"
urls=()
for pkg in cachyos-keyring cachyos-mirrorlist; do
  desc=("${db_dir}/${pkg}"-[0-9]*/desc)
  filename="$(sed -n '/^%FILENAME%$/{n;p;q}' "${desc[0]}")"
  urls+=("${cachyos_repo}/${filename}")
done
# pacman downloads each package's detached signature and checks it against
# the key trusted above.
pacman -U --noconfirm --needed "${urls[@]}"

echo "Build host ready."
