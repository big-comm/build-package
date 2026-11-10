#!/bin/bash
# Makes makepkg's http/https downloads retry on every error.
#
#   scripts/makepkg-download-retry.sh [makepkg.conf ...]   (default /etc/makepkg.conf)
#
# makepkg.conf ships curl with --retry 3, which only retries timeouts and
# HTTP 5xx. A connection reset (curl 35/56) failed the whole build at once:
# 2026-11-10, mesa-big twice in a row on archive.mesa3d.org, "Recv failure:
# Connection reset by peer", while the same download worked in the builds
# around them. --retry-all-errors retries those too; -C - (already there)
# resumes a partial file instead of starting over.
#
# Running it again changes nothing: curl takes the last of a repeated option,
# so the old --retry/--retry-delay are removed, not overridden.

set -euo pipefail

RETRY='--retry 5 --retry-delay 10 --retry-all-errors'

(($#)) || set -- /etc/makepkg.conf
for conf in "$@"; do
  [[ -f $conf ]] || { echo "makepkg-download-retry: $conf not found" >&2; exit 1; }
  sed -i -E "/^[[:space:]]*(DLAGENTS=\()?'https?::/{
    s/ --retry-all-errors//g
    s/ --retry-delay [0-9]+//g
    s/ --retry [0-9]+//g
    s#(/usr/bin/curl) #\1 $RETRY #
  }" "$conf"
  # Both agents must have it, or a download over the other scheme still fails at once.
  for scheme in http https; do
    grep -qE "^[[:space:]]*(DLAGENTS=\()?'$scheme::/usr/bin/curl $RETRY " "$conf" || {
      echo "makepkg-download-retry: no $scheme curl agent in $conf" >&2
      exit 1
    }
  done
done
