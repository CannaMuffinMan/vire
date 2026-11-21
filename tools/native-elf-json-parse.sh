#!/usr/bin/env bash
# Isolated native ELF json/parse + listen+parse. FAIL_BEFORE uses the
# rt-net-json blob from 6e969fc2 (same bytes as 5187c25). PASS_AFTER uses HEAD.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
export PATH="${HOME}/.dotnet:${PATH:-}"
export DOTNET_ROOT="${DOTNET_ROOT:-$HOME/.dotnet}"
export VIRE_HEADLESS=1
unset VIRE_BUDGET || true

AFTER_SHA="$(git rev-parse HEAD)"
FAIL_SHA="6e969fc2e9c94f537bad69b948e56670096c2a1b"
echo "fail_before_sha $FAIL_SHA"
echo "pass_after_sha $AFTER_SHA"

dotnet build vire.csproj -c Release --nologo >/tmp/vire-json-parse-build.log
bash "$ROOT/tools/stage-compiler-src.sh" >/tmp/vire-json-parse-stage.log

hex_to_bin() {
  python3 - "$1" "$2" <<'PY'
from pathlib import Path
import sys
Path(sys.argv[2]).write_bytes(bytes.fromhex(Path(sys.argv[1]).read_text().strip()))
PY
}

compile_guest() {
  local src="$1" stem="$2"
  if [[ "$src" != "data/${stem}.vire" ]]; then
    cp "$src" "data/${stem}.vire"
  fi
  rm -f "data/${stem}.hex" "data/${stem}.elf"
  dotnet exec bin/Release/net10.0/vire.dll --compiler compile-native.vire "data/${stem}.vire" "data/${stem}.hex"
  hex_to_bin "data/${stem}.hex" "data/${stem}.elf"
  chmod +x "data/${stem}.elf"
}

mkdir -p data
cat > data/json-parse-repro.vire <<'EOF'
define main
  say (json with (parse with "{\"a\":1}"))
end
EOF

mkdir -p /tmp/vire-json-parse-save
cp src/rt-net-json-blob.txt src/rt-more.vire /tmp/vire-json-parse-save/
git show "$FAIL_SHA:src/rt-net-json-blob.txt" > src/rt-net-json-blob.txt
git show "$FAIL_SHA:src/rt-more.vire" > src/rt-more.vire
bash tools/stage-compiler-src.sh >/tmp/stage-fail.log
compile_guest data/json-parse-repro.vire json-parse-repro
set +e
./data/json-parse-repro.elf >/tmp/json-parse-fail.out 2>&1
FAIL_CODE=$?
set -e
cp /tmp/vire-json-parse-save/rt-net-json-blob.txt src/rt-net-json-blob.txt
cp /tmp/vire-json-parse-save/rt-more.vire src/rt-more.vire
bash tools/stage-compiler-src.sh >/tmp/stage-restore.log
if [[ "$FAIL_CODE" -eq 0 ]]; then
  echo "FAIL_BEFORE expected segfault, got exit 0"
  cat /tmp/json-parse-fail.out
  exit 1
fi
echo "FAIL_BEFORE at $FAIL_SHA: native parse+json ELF exit $FAIL_CODE"

compile_guest data/json-parse-repro.vire json-parse-repro
OUT="$(./data/json-parse-repro.elf)"
echo "$OUT"
echo "$OUT" | tr -d ' ' | grep -qx '{"a":1}'

compile_guest tests/rebuild/guests/listen-parse.vire listen-parse
rm -f /tmp/vire-listen-parse.out
./data/listen-parse.elf >/tmp/vire-listen-parse.out 2>&1 &
LPID=$!
for i in $(seq 1 80); do
  grep -q "listening on 127.0.0.1:" /tmp/vire-listen-parse.out 2>/dev/null && break
  sleep 0.05
done
LPORT="$(sed -n 's/.*listening on 127.0.0.1:\([0-9]*\).*/\1/p' /tmp/vire-listen-parse.out | head -1)"
python3 - "$LPORT" <<'PY'
import socket, sys
p = int(sys.argv[1])
body = b'{"a":1}'
req = b"POST /p HTTP/1.1\r\nHost: x\r\nContent-Length: 7\r\nConnection: close\r\n\r\n" + body
s = socket.create_connection(("127.0.0.1", p), 3)
s.sendall(req)
s.settimeout(3)
got = s.recv(4096)
s.close()
if b'{"a":1}' not in got.replace(b" ", b""):
    raise SystemExit("listen+parse POST mismatch: %r" % got)
s = socket.create_connection(("127.0.0.1", p), 3)
s.sendall(b"GET /p HTTP/1.1\r\nHost: x\r\nConnection: close\r\n\r\n")
s.settimeout(3)
got = s.recv(4096)
s.close()
if b"400" not in got:
    raise SystemExit("listen+parse GET empty body: %r" % got)
print("listen_parse_ok")
PY
kill "$LPID" 2>/dev/null || true
wait "$LPID" 2>/dev/null || true
echo "PASS_AFTER at $AFTER_SHA native ELF json/parse and listen+parse"
echo "native elf json parse ok"
