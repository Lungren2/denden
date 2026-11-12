#!/usr/bin/env bash
# Build every PKGBUILD under packages/ into the local `denden` pacman repo at
# repo/x86_64/, which the ISO build installs from.
#
# Run as a normal user (makepkg refuses root). Packages whose current version
# is already in the repo are skipped.
set -euo pipefail

repo_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
repo_dir="${repo_root}/repo/x86_64"
repo_db="${repo_dir}/denden.db.tar.gz"

if [[ ${EUID} -eq 0 ]]; then
  echo "error: makepkg can't run as root; run this as a normal user" >&2
  exit 1
fi

mkdir -p -- "${repo_dir}"
export PKGDEST="${repo_dir}"
export SRCDEST="${repo_root}/repo/sources"
# Build outside this repo's working tree, so package build scripts that look
# for an enclosing git repo (e.g. to install hooks) can't find this one.
export BUILDDIR="${XDG_CACHE_HOME:-${HOME}/.cache}/denden/build"
mkdir -p -- "${SRCDEST}" "${BUILDDIR}"

shopt -s nullglob
for pkgbuild in "${repo_root}"/packages/*/PKGBUILD; do
  pkg_dir="$(dirname -- "${pkgbuild}")"
  mapfile -t pkg_files < <(cd -- "${pkg_dir}" && makepkg --packagelist)
  if [[ -f ${pkg_files[0]} ]]; then
    echo "==> $(basename -- "${pkg_dir}"): up to date"
    continue
  fi
  echo "==> Building $(basename -- "${pkg_dir}")"
  (cd -- "${pkg_dir}" && makepkg --syncdeps --clean --cleanbuild --noconfirm)
  repo-add --remove "${repo_db}" "${pkg_files[@]}"
done

# Create an empty database if there were no packages, so pacman can still sync.
[[ -f ${repo_db} ]] || repo-add "${repo_db}"
