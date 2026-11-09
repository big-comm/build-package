#!/bin/bash
# Who gets the Secure Boot key: scripts/secureboot-key.sh must hand it to the
# big-comm/big-kernel builds and to nothing else.
#
#   tests/test-secureboot-key.sh

set -uo pipefail

script=$(realpath "$(dirname "$0")/../scripts/secureboot-key.sh")
work=$(mktemp -d)
trap 'rm -rf -- "$work"' EXIT
failures=0
key=$'-----BEGIN PRIVATE KEY-----\ntest\n-----END PRIVATE KEY-----'

check() {
  local name=$1; shift
  if "$@"; then echo "ok   $name"; else echo "FAIL $name"; failures=$((failures + 1)); fi
}

# prepare <url> <build_env> [key]: runs the script in a fresh directory, and
# leaves there what it wrote.
prepare() {
  rm -rf "$work/run" && mkdir "$work/run" && : > "$work/run/env"
  SECUREBOOT_KEY=${3-$key} GITHUB_ENV=$work/run/env \
    "$script" prepare "$1" "$2" "$work/run/sb" > "$work/run/out" 2>&1
}
given() { [[ -s $work/run/env && -f $work/run/sb/key.pem ]]; }
withheld() { [[ ! -s $work/run/env && ! -e $work/run/sb ]]; }

for url in https://github.com/big-comm/big-kernel https://github.com/big-comm/big-kernel.git \
           https://github.com/big-comm/big-kernel/; do
  prepare "$url" testing
  check "kernel build gets the key ($url)" given
done

prepare https://github.com/big-comm/big-kernel testing
check "env names the key file" grep -qx "BIGCOMMUNITY_SB_KEY=$work/run/sb/key.pem" "$work/run/env"
check "key file holds the key" diff -q <(printf '%s\n' "$key") "$work/run/sb/key.pem"
check "key file is private" [ "$(stat -c %a "$work/run/sb/key.pem")" = 600 ]
check "key directory is private" [ "$(stat -c %a "$work/run/sb")" = 700 ]
check "key never printed" bash -c "! grep -q test '$work/run/out'"

for url in https://github.com/big-comm/big-mesa https://github.com/big-comm/big-kernel-evil \
           https://github.com/someone/big-kernel https://aur.archlinux.org/linux-big.git ""; do
  prepare "$url" testing
  check "other build gets nothing (${url:-no url})" withheld
done
prepare https://github.com/big-comm/big-kernel aur
check "aur build gets nothing" withheld
prepare https://github.com/big-comm/big-kernel testing ""
check "no secret, nothing written" withheld

prepare https://github.com/big-comm/big-kernel stable
BIGCOMMUNITY_SB_KEY=$work/run/sb/key.pem "$script" remove > /dev/null
check "remove deletes the key" [ ! -e "$work/run/sb/key.pem" ]
check "remove with nothing to remove" env -u BIGCOMMUNITY_SB_KEY "$script" remove
check "remove of a missing file" env BIGCOMMUNITY_SB_KEY="$work/none" "$script" remove

if (( failures )); then echo "$failures failure(s)"; exit 1; fi
echo "all passed"
