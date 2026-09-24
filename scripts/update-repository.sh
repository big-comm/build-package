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

# name-pkgver-pkgrel-arch.pkg.tar.zst. pkgver, pkgrel and arch never contain
# a hyphen, so the name is everything before the last three fields.
# Cutting at the first "-<digit>" instead put linux-big-nvidia-580xx in the
# same group as linux-big-nvidia, and one deleted the other.
package_name() {
  local stem=${1%.pkg.tar.*}
  echo "${stem%-*-*-*}"
}

package_version() {
  local stem=${1%.pkg.tar.*}
  stem=${stem%-*}
  echo "${stem#"$(package_name "$1")"-}"
}

# One listing, used throughout. Other builds keep uploading while this one
# runs; a package that lands later is handled by its own build, which is
# waiting for the lock. (rsync writes to a temporary name and renames, so a
# half-uploaded package never matches.)
shopt -s nullglob
listing=(*.pkg.tar.zst)
declare -A newest=()
for file in "${listing[@]}"; do
  name=$(package_name "$file")
  if [[ -z ${newest[$name]:-} ]] ||
    (($(vercmp "$(package_version "$file")" "$(package_version "${newest[$name]}")") > 0)); then
    newest[$name]=$file
  fi
done

packages=()
for file in "${listing[@]}"; do
  name=$(package_name "$file")
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
  entry="$(package_name "$file")-$(package_version "$file")/"
  if grep -qxF -- "$entry" <<< "$listed"; then
    echo "Published: $file"
  elif [[ ! -f $file ]]; then
    echo "error: $file is not in the repository: a newer version is, ${newest[$(package_name "$file")]:-none}" >&2
    failed=1
  else
    echo "error: $file is in the repository but not in $db_name" >&2
    failed=1
  fi
done
exit "$failed"
