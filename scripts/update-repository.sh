#!/bin/bash
# Runs on the repository server, after a build uploaded its packages:
#
#   update-repository.sh <directory> <database> <uploaded package file>...
#
# Keeps only the newest version of each package in <directory>, rebuilds
# <database> from what is left, and checks that every uploaded package made
# it into the database. It exits non-zero when one did not, so a build whose
# package is not published fails instead of reporting success.
#
# Sent over ssh by action.yml; it must not depend on anything from the build.

set -euo pipefail

target_dir=$1
db_name=$2
shift 2
uploaded=("$@")

mkdir -p "$target_dir"
cd "$target_dir"

# Builds finish at the same time; each one rewrites the database. One at a
# time, or a database written from an older listing can drop a package.
if command -v flock >/dev/null; then
  exec 9> .update-repository.lock
  echo "Waiting for the repository lock..."
  flock -w 1800 9 || { echo "error: the repository stayed locked for 30 minutes" >&2; exit 1; }
else
  echo "warning: flock is not installed; updating without a lock" >&2
fi

# Name and version come from the package's own .PKGINFO, as repo-add reads
# them, not from the file name: files get renamed (an epoch's ":" becomes
# "."), and cutting the name at the first "-<digit>" once put
# linux-big-nvidia-580xx in the same group as linux-big-nvidia, and one
# deleted the other.
declare -A pkg_name=() pkg_version=()
read_pkginfo() {
  local info
  info=$(bsdtar -xOqf "$1" .PKGINFO) || { echo "error: $1 is not a readable package" >&2; return 1; }
  pkg_name[$1]=$(sed -n 's/^pkgname = //p' <<< "$info")
  pkg_version[$1]=$(sed -n 's/^pkgver = //p' <<< "$info")
  [[ -n ${pkg_name[$1]} && -n ${pkg_version[$1]} ]] || { echo "error: $1 has no pkgname or pkgver" >&2; return 1; }
}

shopt -s nullglob
listing=(*.pkg.tar.zst)
declare -A newest=()
for file in "${listing[@]}"; do
  read_pkginfo "$file"
  name=${pkg_name[$file]}
  if [[ -z ${newest[$name]:-} ]] ||
    (($(vercmp "${pkg_version[$file]}" "${pkg_version[${newest[$name]}]}") > 0)); then
    newest[$name]=$file
  fi
done

packages=()
for file in "${listing[@]}"; do
  name=${pkg_name[$file]}
  if [[ $file == "${newest[$name]}" ]]; then
    packages+=("$file")
  else
    echo "Removing $file (keeping ${newest[$name]})"
    rm -f -- "$file" "$file.sig" "$file.md5"
  fi
done

for file in *.sig *.md5; do
  [[ -f ${file%.*} ]] || { echo "Removing orphaned $file"; rm -f -- "$file"; }
done

# Written aside and moved into place, so pacman never downloads a database
# that is missing or half written.
echo "Rebuilding $db_name..."
work=$(mktemp -d .repo-add.XXXXXX)
trap 'rm -rf -- "$work"' EXIT
if ((${#packages[@]})); then
  repo-add --quiet --prevent-downgrade "$work/$db_name.db.tar.gz" "${packages[@]}"
else
  repo-add --quiet "$work/$db_name.db.tar.gz"
fi
mv -f -- "$work/$db_name.db.tar.gz" "$db_name.db.tar.gz"
mv -f -- "$work/$db_name.files.tar.gz" "$db_name.files.tar.gz"
ln -sfn "$db_name.db.tar.gz" "$db_name.db"
ln -sfn "$db_name.files.tar.gz" "$db_name.files"

listed=$(bsdtar -tf "$db_name.db.tar.gz")
failed=0
for file in "${uploaded[@]}"; do
  file=${file##*/}
  if [[ -z ${pkg_name[$file]:-} ]]; then
    echo "error: $file was not found in the repository" >&2
    failed=1
    continue
  fi
  name=${pkg_name[$file]}
  if grep -qxF -- "$name-${pkg_version[$file]}/" <<< "$listed"; then
    echo "Published: $file"
  elif [[ ${newest[$name]} != "$file" ]]; then
    echo "error: $file is not in the repository: a newer version is, ${newest[$name]}" >&2
    failed=1
  else
    echo "error: $file is in the repository but not in $db_name" >&2
    failed=1
  fi
done
exit "$failed"
