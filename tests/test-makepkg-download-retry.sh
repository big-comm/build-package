#!/bin/bash
# scripts/makepkg-download-retry.sh: makepkg's downloads survive a connection
# reset, and the rest of makepkg.conf is left as it was.
#
#   tests/test-makepkg-download-retry.sh

set -uo pipefail

script=$(realpath "$(dirname "$0")/../scripts/makepkg-download-retry.sh")
work=$(mktemp -d)
trap 'kill "${server:-}" 2>/dev/null; rm -rf -- "$work"' EXIT
failures=0

check() {
  local name=$1; shift
  if "$@"; then echo "ok   $name"; else echo "FAIL $name"; failures=$((failures + 1)); fi
}

# The DLAGENTS of the image the packages are built in (talesam/community-build).
cat > "$work/makepkg.conf" <<'EOF'
#-- The download utilities that makepkg should use to acquire sources
DLAGENTS=('file::/usr/bin/curl -qgC - -o %o %u'
          'ftp::/usr/bin/curl -qgfC - --ftp-pasv --retry 3 --retry-delay 3 -o %o %u'
          'http::/usr/bin/curl -qgb "" -fLC - --retry 3 --retry-delay 3 -o %o %u'
          'https::/usr/bin/curl -qgb "" -fLC - --retry 3 --retry-delay 3 -o %o %u'
          'rsync::/usr/bin/rsync --no-motd -z %u %o'
          'scp::/usr/bin/scp -C %u %o')
PACKAGER="Big Community Package Build <talesam@gmail.com>"
EOF
cp "$work/makepkg.conf" "$work/original"

"$script" "$work/makepkg.conf"
check "it runs" [ $? = 0 ]
want='/usr/bin/curl --retry 5 --retry-delay 10 --retry-all-errors -qgb "" -fLC - -o %o %u'
check "https agent retries every error" grep -qF "'https::$want'" "$work/makepkg.conf"
check "http agent retries every error" grep -qF "'http::$want'" "$work/makepkg.conf"
check "no --retry 3 left to override it" bash -c "! grep -E \"'https?::\" '$work/makepkg.conf' | grep -q -- '--retry 3'"
check "only the http and https lines change" \
  [ "$(diff "$work/original" "$work/makepkg.conf" | grep -c '^[<>]')" = 4 ]
check "still valid bash, makepkg sources it" bash -n "$work/makepkg.conf"
check "the agents still parse as six" \
  [ "$(bash -c "source '$work/makepkg.conf'; echo \${#DLAGENTS[@]}")" = 6 ]

cp "$work/makepkg.conf" "$work/once"
"$script" "$work/makepkg.conf"
check "running it twice changes nothing" diff -q "$work/once" "$work/makepkg.conf"

printf 'DLAGENTS=()\n' > "$work/empty.conf"
"$script" "$work/empty.conf" 2>/dev/null
check "a makepkg.conf without curl agents is an error, not ignored" [ $? != 0 ]
"$script" "$work/missing.conf" 2>/dev/null
check "a missing makepkg.conf is an error" [ $? != 0 ]

# The real thing: a server that resets the first two connections, then serves
# the file. The agent before the change gives up; the one after gets it.
cat > "$work/server.py" <<'EOF'
import http.server, socket, struct, sys
count = 0
class Handler(http.server.BaseHTTPRequestHandler):
    def do_GET(self):
        global count
        count += 1
        if count <= 2:  # RST instead of a reply, as archive.mesa3d.org did
            self.connection.setsockopt(socket.SOL_SOCKET, socket.SO_LINGER, struct.pack("ii", 1, 0))
            self.connection.close()
            return
        body = b"mesa\n"
        self.send_response(200)
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)
    def log_message(self, *args):
        pass
server = http.server.HTTPServer(("127.0.0.1", 0), Handler)
print(server.server_address[1], flush=True)
server.serve_forever()
EOF
agent() { # conf: the http agent of that makepkg.conf, as makepkg runs it
  bash -c "source '$1'; for a in \"\${DLAGENTS[@]}\"; do [[ \$a == http::* ]] && echo \"\${a#http::}\"; done"
}
fetch() { # conf -> downloads from a fresh server
  coproc SERVER { python3 -I "$work/server.py"; }
  server=$SERVER_PID
  read -r port <&"${SERVER[0]}"
  rm -f "$work/got"
  local cmd
  cmd=$(agent "$1")
  cmd=${cmd//--retry-delay 10/--retry-delay 1}  # the same retries, faster
  cmd=${cmd//%o/$work/got}
  cmd=${cmd//%u/http://127.0.0.1:$port/mesa.tar.xz}
  eval "$cmd" 2>/dev/null
  local rc=$?
  kill "$server" 2>/dev/null; wait "$server" 2>/dev/null
  return $rc
}
fetch "$work/original"
check "before: a connection reset fails the download (what broke mesa-big)" [ $? != 0 ]
fetch "$work/makepkg.conf"
check "after: the download survives two connection resets" [ $? = 0 ]
check "after: and the file is the server's" grep -qx mesa "$work/got"

if ((failures)); then echo "$failures failed"; exit 1; fi
echo "all passed"
