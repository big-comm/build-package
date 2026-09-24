#!/bin/bash
# Scenarios scripts/update-repository.sh must get right, on real (tiny)
# packages and the real repo-add, vercmp and bsdtar.
#
#   tests/test-update-repository.sh

set -uo pipefail

script=$(realpath "$(dirname "$0")/../scripts/update-repository.sh")
work=$(mktemp -d)
trap 'rm -rf -- "$work"' EXIT
failures=0

# A package pacman accepts: name, version (pkgver-pkgrel) and a .PKGINFO.
package() {
  local dir=$1 name=$2 version=$3 build
  build=$(mktemp -d "$work/build.XXXXXX")
  cat > "$build/.PKGINFO" << EOF
pkgname = $name
pkgbase = $name
pkgver = $version
pkgdesc = test
builddate = 0
packager = test
size = 0
arch = x86_64
EOF
  # Written aside and renamed into place, as rsync uploads.
  (cd "$build" && bsdtar --zstd -cf package .PKGINFO)
  mv "$build/package" "$dir/$name-$version-x86_64.pkg.tar.zst"
  rm -rf -- "$build"
  echo "$name-$version-x86_64.pkg.tar.zst"
}

database() {
  bsdtar -tf "$1/community-testing.db.tar.gz" | sed -n 's|/$||p' | sort
}

check() {
  local what=$1 expected=$2 actual=$3
  if [[ $expected == "$actual" ]]; then
    echo "ok: $what"
  else
    echo "FAIL: $what"
    diff <(echo "$expected") <(echo "$actual") | sed 's/^/    /'
    failures=$((failures + 1))
  fi
}

update() {
  local dir=$1
  shift
  bash "$script" "$dir" community-testing "$@" > "$dir.log" 2>&1
}

# 1. Names that share a prefix, and names with a part that starts with a
#    digit, are different packages. The old cleanup kept one of these six.
repo=$work/nvidia
mkdir -p "$repo"
files=()
for module in nvidia:610.57.04 nvidia-open:610.57.04 nvidia-580xx:580.178.04 \
  nvidia-580xx-open:580.178.04 nvidia-470xx:470.256.02 nvidia-390xx:390.157; do
  files+=("$(package "$repo" "linux-big-${module%%:*}" "${module#*:}-7020702")")
done
update "$repo" "${files[@]}"
check "every NVIDIA module is kept and published" "$(printf '%s\n' "${files[@]%-x86_64.pkg.tar.zst}" | sort)" "$(database "$repo")"

# 2. Newest by version, not by name or by date: 7.2.10 is newer than 7.2.9,
#    though it sorts first and is uploaded first.
repo=$work/order
mkdir -p "$repo"
new=$(package "$repo" linux-big 7.2.10-1)
sleep 1
package "$repo" linux-big 7.2.9-1 > /dev/null
update "$repo" "$new"
check "7.2.10 wins over 7.2.9" "linux-big-7.2.10-1" "$(database "$repo")"
check "7.2.9 is removed" "$new" "$(find "$repo" -name "*.pkg.tar.zst" -printf "%f\n")"

# 3. Uploading an older version fails the build, and says why.
repo=$work/downgrade
mkdir -p "$repo"
current=$(package "$repo" linux-big 7.2.8-1)
update "$repo" "$current"
older=$(package "$repo" linux-big 7.2.7-2)
update "$repo" "$older"
check "an older upload fails" "1" "$?"
check "and is explained" "1" "$(grep -c "a newer version is, $current" "$repo.log")"
check "the newer one stays published" "linux-big-7.2.8-1" "$(database "$repo")"

# 4. A new pkgrel replaces the old one, with its signature.
repo=$work/pkgrel
mkdir -p "$repo"
one=$(package "$repo" linux-big 7.2.7-1)
touch "$repo/$one.sig"
two=$(package "$repo" linux-big 7.2.7-2)
touch "$repo/$two.sig" "$repo/stray.pkg.tar.zst.sig"
update "$repo" "$two"
check "a new pkgrel replaces the old" "linux-big-7.2.7-2" "$(database "$repo")"
check "old and orphaned signatures go" "$two.sig" "$(find "$repo" -name "*.sig" -printf "%f\n")"

# 5. Fifteen builds finishing at once each publish their package.
repo=$work/parallel
mkdir -p "$repo"
package "$repo" linux-big 7.2.7-2 > /dev/null
pids=()
for n in $(seq 1 15); do
  file=$(package "$repo" "linux-big-module$n" 1.0-7020702)
  bash "$script" "$repo" community-testing "$file" > "$repo.$n.log" 2>&1 &
  pids+=($!)
done
status=0
for pid in "${pids[@]}"; do wait "$pid" || status=1; done
check "fifteen parallel updates succeed" "0" "$status"
check "and the database has all sixteen packages" "16" "$(database "$repo" | wc -l)"

# 6. The database is readable by pacman.
check "pacman reads the database" "linux-big 7.2.7-2" \
  "$(tar -xOzf "$repo/community-testing.db.tar.gz" linux-big-7.2.7-2/desc | awk '/%NAME%/{getline; n=$0} /%VERSION%/{getline; print n, $0}')"
check "the .db link points at the database" "community-testing.db.tar.gz" "$(readlink "$repo/community-testing.db")"

echo
((failures)) && { echo "$failures failed"; exit 1; }
echo "all passed"
