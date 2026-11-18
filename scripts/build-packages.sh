#!/usr/bin/env bash
# Build every PKGBUILD under packages/ into the local `denden` pacman repo at
# repo/x86_64/, which the ISO build installs from.
#
# Run as a normal user (makepkg refuses root). Packages whose current version
# is already in the repo are skipped.
set -euo pipefail

repo_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
# DENDEN_PKGDEST and SRCDEST let a build from another worktree (denden-update
# bump) put its packages and downloads in the main checkout's.
repo_dir="${DENDEN_PKGDEST:-${repo_root}/repo/x86_64}"
repo_db="${repo_dir}/denden.db.tar.gz"

if [[ ${EUID} -eq 0 ]]; then
  echo "error: makepkg can't run as root; run this as a normal user" >&2
  exit 1
fi

# Optional package names let installed machines rebuild just their own set.
packages=()
if (($#)); then
  for name in "$@"; do
    [[ $name =~ ^[a-zA-Z0-9@._+-]+$ && -f ${repo_root}/packages/$name/PKGBUILD ]] || {
      echo "error: unknown package: $name" >&2; exit 1;
    }
    packages+=("${repo_root}/packages/$name/PKGBUILD")
  done
else
  packages=("${repo_root}"/packages/*/PKGBUILD)
fi
mkdir -p -- "${repo_dir}"
export PKGDEST="${repo_dir}"
export SRCDEST="${SRCDEST:-${repo_root}/repo/sources}"
# Build outside this repo's working tree, so package build scripts that look
# for an enclosing git repo (e.g. to install hooks) can't find this one.
export BUILDDIR="${XDG_CACHE_HOME:-${HOME}/.cache}/denden/build"
mkdir -p -- "${SRCDEST}" "${BUILDDIR}"

shopt -s nullglob
exec 9>"${repo_dir}/.build.lock"
flock 9
for pkgbuild in "${packages[@]}"; do
  pkg_dir="$(dirname -- "${pkgbuild}")"
  mapfile -t pkg_files < <(cd -- "${pkg_dir}" && makepkg --packagelist)
  if [[ -f ${pkg_files[0]} ]]; then
    echo "==> $(basename -- "${pkg_dir}"): up to date"
    # Cached archives may not yet have an entry in the database.
    built=()
    for file in "${pkg_files[@]}"; do [[ ! -f $file ]] || built+=("$file"); done
    repo-add --prevent-downgrade "${repo_db}" "${built[@]}"
    continue
  fi
  echo "==> Building $(basename -- "${pkg_dir}")"
  # Packages that compile nothing (meta packages, repackaged binaries,
  # scripts and artwork: no build step, or arch 'any') skip dependency checks,
  # so building them doesn't install their whole runtime closure on the build
  # host, nor need [denden]/[cachyos] configured there. Their build tools
  # (makedepends) are installed directly.
  dep_flag=--syncdeps
  if ! grep -qE '^(prepare|build)\(\)' "${pkgbuild}" || grep -qE "^arch=\('any'\)" "${pkgbuild}"; then
    dep_flag=--nodeps
    mapfile -t make_deps < <(bash -c 'source "$1" && for d in "${makedepends[@]}"; do echo "${d}"; done' _ "${pkgbuild}")
    if ((${#make_deps[@]})); then
      sudo pacman -S --needed --noconfirm --asdeps "${make_deps[@]}"
    fi
  fi
  (cd -- "${pkg_dir}" && makepkg "${dep_flag}" --clean --cleanbuild --noconfirm)
  # --packagelist includes a -debug package even when makepkg ends up with
  # nothing to put in it, so add only what was actually built.
  built=()
  for file in "${pkg_files[@]}"; do if [[ -f ${file} ]]; then built+=("${file}"); fi; done
  repo-add --prevent-downgrade "${repo_db}" "${built[@]}"
done

# Create an empty database if there were no packages, so pacman can still sync.
[[ -f ${repo_db} ]] || repo-add "${repo_db}"
