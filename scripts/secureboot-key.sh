#!/bin/bash
# The Secure Boot key, for the kernel builds only:
#
#   secureboot-key.sh prepare <source url> <build_env> <directory>
#   secureboot-key.sh remove
#
# build-package builds every package of the organization, AUR ones included,
# and anything a PKGBUILD runs can read what the build can. So the key (the
# SECUREBOOT_KEY secret, in the environment variable of the same name) is
# only written for a build from big-comm/big-kernel, whose PKGBUILDs sign the
# kernel image and its modules with it (big-kernel/secureboot/sign.sh). It
# goes to <directory>/key.pem, readable by the build user alone, and its path
# to BIGCOMMUNITY_SB_KEY through $GITHUB_ENV, which makepkg then inherits.
# Any other build, or no secret, writes nothing: the build is what it always
# was.
#
# "remove" deletes the key. action.yml runs it right after makepkg, before the
# extra command and the upload, and again at the end of the job whatever
# happened.

set -euo pipefail

KERNEL_REPOSITORY=big-comm/big-kernel

is_kernel_build() {
  local url=${1%/} build_env=$2
  url=${url%.git}
  [[ $build_env != aur && $url == "https://github.com/$KERNEL_REPOSITORY" ]]
}

case ${1:-} in
  prepare)
    url=${2:-} build_env=${3:-} dir=${4:-}
    if [[ -z ${SECUREBOOT_KEY:-} ]]; then
      echo "Secure Boot: no key in this workflow, nothing is signed"
      exit 0
    fi
    if ! is_kernel_build "$url" "$build_env"; then
      echo "Secure Boot: not a $KERNEL_REPOSITORY build, the key is not provided"
      exit 0
    fi
    [[ -n $dir ]] || { echo "secureboot-key.sh: no directory" >&2; exit 2; }
    (umask 077 && mkdir -p "$dir" && printf '%s\n' "$SECUREBOOT_KEY" > "$dir/key.pem")
    echo "BIGCOMMUNITY_SB_KEY=$dir/key.pem" >> "${GITHUB_ENV:?}"
    echo "Secure Boot: key provided to the $KERNEL_REPOSITORY build"
    ;;
  remove)
    if [[ -n ${BIGCOMMUNITY_SB_KEY:-} && -e $BIGCOMMUNITY_SB_KEY ]]; then
      shred -u "$BIGCOMMUNITY_SB_KEY" 2>/dev/null || rm -f -- "$BIGCOMMUNITY_SB_KEY"
      echo "Secure Boot: key removed"
    fi
    ;;
  *)
    echo "usage: secureboot-key.sh prepare <url> <build_env> <directory> | remove" >&2
    exit 2
    ;;
esac
