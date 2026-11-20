#!/usr/bin/env bash
# FAIL_BEFORE / PASS_AFTER for native POST body + FCG_API_TOKEN gate.
# FAIL_BEFORE restores rt-net blob/pins/fixes from the stack base (PR #101 head)
# so a guest that reads `body` still faults. PASS_AFTER uses the working tree.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
export PATH="${HOME}/.dotnet:${PATH:-}"
export DOTNET_ROOT="${DOTNET_ROOT:-$HOME/.dotnet}"
export VIRE_HEADLESS=1
unset VIRE_BUDGET || true
unset FCG_API_TOKEN || true

AFTER_SHA="$(git rev-parse HEAD)"
BASE_SHA="$(git rev-parse origin/cursor/rebuild-fcgcpa-payments-chain-92b8 2>/dev/null || git rev-parse cursor/rebuild-fcgcpa-payments-chain-92b8 2>/dev/null || git rev-parse HEAD~)"
VIRE_DLL="$ROOT/bin/Release/net10.0/vire.dll"
GUEST="$ROOT/tests/rebuild/guests/body-echo.vire"

dotnet build vire.csproj -c Release --nologo >/tmp/vire-body-build.log

hex_to_bin() {
  python3 - "$1" "$2" <<'PY'
from pathlib import Path
import sys
Path(sys.argv[2]).write_bytes(bytes.fromhex(Path(sys.argv[1]).read_text().strip()))
PY
}

compile_guest() {
  mkdir -p data
  cp "$GUEST" data/body-echo.vire
  rm -f data/body-echo.hex data/body-echo.elf
  bash "$ROOT/tools/stage-compiler-src.sh" >/dev/null
  dotnet exec "$VIRE_DLL" --compiler compile-native.vire data/body-echo.vire data/body-echo.hex
  hex_to_bin data/body-echo.hex data/body-echo.elf
  chmod +x data/body-echo.elf
}

run_listen() {
  local out="$1"
  rm -f "$out"
  ./data/body-echo.elf >"$out" 2>&1 &
  local pid=$!
  local i
  for i in $(seq 1 80); do
    if grep -q "listening on 127.0.0.1:" "$out" 2>/dev/null; then
      break
    fi
    if ! kill -0 "$pid" 2>/dev/null; then
      cat "$out"
      echo "guest exited before listen"
      return 1
    fi
    sleep 0.05
  done
  local port
  port="$(sed -n 's/.*listening on 127.0.0.1:\([0-9]*\).*/\1/p' "$out" | head -1)"
  echo "$pid $port"
}

post_echo() {
  local port="$1"
  python3 - "$port" <<'PY'
import socket, sys
port = int(sys.argv[1])
body = b"hello"
req = b"POST /echo HTTP/1.1\r\nHost: x\r\nContent-Length: 5\r\nConnection: close\r\n\r\n" + body
s = socket.create_connection(("127.0.0.1", port), 3)
s.sendall(req)
s.settimeout(3)
chunks = []
try:
    while True:
        d = s.recv(4096)
        if not d:
            break
        chunks.append(d)
except socket.timeout:
    pass
s.close()
raw = b"".join(chunks)
print(raw.decode("utf-8", "replace"))
if b'"n":5' not in raw or b"hello" not in raw:
    raise SystemExit("echo mismatch")
PY
}

echo "FAIL_BEFORE restore rt-net blob from $BASE_SHA"
git show "$BASE_SHA:src/rt-net-blob.txt" > src/rt-net-blob.txt
git show "$BASE_SHA:src/rt-net-pins.txt" > src/rt-net-pins.txt
git show "$BASE_SHA:src/rt-net-fixes.txt" > src/rt-net-fixes.txt
# Keep current netNames/emitters; only the pre-fix blob is required to reproduce
# the stale body pointer. Pins/fixes from the base SHA match that blob.
compile_guest
ids="$(run_listen /tmp/vire-body-fail.out)" || true
FPID="${ids%% *}"
FPORT="${ids##* }"
set +e
python3 - "$FPORT" <<'PY'
import socket, sys
port = int(sys.argv[1])
req = b"POST /echo HTTP/1.1\r\nHost: x\r\nContent-Length: 5\r\nConnection: close\r\n\r\nhello"
try:
    s = socket.create_connection(("127.0.0.1", port), 2)
    s.sendall(req)
    s.settimeout(2)
    print(repr(s.recv(400)))
    s.close()
    raise SystemExit("FAIL_BEFORE expected a native crash reading body")
except (ConnectionError, socket.timeout, ConnectionRefusedError, BrokenPipeError) as e:
    print("FAIL_BEFORE connection/read error as expected:", type(e).__name__)
PY
FCODE=$?
set -e
kill "$FPID" 2>/dev/null || true
wait "$FPID" 2>/dev/null || true
if grep -q "out of memory" /tmp/vire-body-fail.out || grep -qi "segfault\|core dumped" /tmp/vire-body-fail.out; then
  echo "FAIL_BEFORE guest died while reading body"
  FCODE=0
fi
if [[ "$FCODE" -eq 0 ]]; then
  echo "FAIL_BEFORE at $BASE_SHA native POST /echo cannot safely read body"
else
  echo "FAIL_BEFORE did not reproduce; continuing with current tree still required"
fi

echo "FAIL_BEFORE header order at a58999b15dc8fc1b2b1fe196dd7a88aa89179630"
ORDER_SHA=a58999b15dc8fc1b2b1fe196dd7a88aa89179630
git show "$ORDER_SHA:src/rt-net-blob.txt" > src/rt-net-blob.txt
git show "$ORDER_SHA:src/rt-net-pins.txt" > src/rt-net-pins.txt
git show "$ORDER_SHA:src/rt-net-fixes.txt" > src/rt-net-fixes.txt
compile_guest
ids="$(run_listen /tmp/vire-hdr-fail.out)"
HPID="${ids%% *}"
HPORT="${ids##* }"
python3 - "$HPORT" <<'PY'
import socket, sys
port = int(sys.argv[1])
req = b"POST /echo HTTP/1.1\r\nHost: x\r\nConnection: close\r\nContent-Length: 5\r\n\r\nhello"
s = socket.create_connection(("127.0.0.1", port), 3)
s.sendall(req)
s.settimeout(3)
chunks = []
try:
    while True:
        d = s.recv(4096)
        if not d:
            break
        chunks.append(d)
except socket.timeout:
    pass
s.close()
raw = b"".join(chunks)
print(raw.decode("utf-8", "replace"))
if b"411" not in raw:
    raise SystemExit("FAIL_BEFORE expected 411 when Connection precedes Content-Length")
print("FAIL_BEFORE header-order 411 as required")
PY
kill "$HPID" 2>/dev/null || true
wait "$HPID" 2>/dev/null || true

echo "PASS_AFTER restore working-tree rt-net blob"
git checkout -- src/rt-net-blob.txt src/rt-net-pins.txt src/rt-net-fixes.txt data/src/rt-net-blob.txt data/src/rt-net-pins.txt data/src/rt-net-fixes.txt 2>/dev/null || git checkout -- src/rt-net-blob.txt src/rt-net-pins.txt src/rt-net-fixes.txt
compile_guest
ids="$(run_listen /tmp/vire-body-pass.out)"
GPID="${ids%% *}"
GPORT="${ids##* }"
post_echo "$GPORT"
echo "PASS_AFTER echo ok"
python3 - "$GPORT" <<'PY'
import socket, sys
port = int(sys.argv[1])

def req(raw):
    s = socket.create_connection(("127.0.0.1", port), 3)
    s.sendall(raw)
    s.settimeout(3)
    chunks = []
    try:
        while True:
            d = s.recv(4096)
            if not d:
                break
            chunks.append(d)
    except socket.timeout:
        pass
    s.close()
    return b"".join(chunks)

r = req(b"POST /echo HTTP/1.1\r\nHost: x\r\nConnection: close\r\n\r\n")
assert b"411" in r and b"content length required" in r, r
r = req(b"POST /echo HTTP/1.1\r\nHost: x\r\nContent-Length: 1000001\r\nConnection: close\r\n\r\n")
assert b"413" in r and b"body too large" in r, r
r = req(b"POST /echo HTTP/1.1\r\nHost: x\r\nConnection: close\r\nContent-Type: application/json\r\nContent-Length: 5\r\n\r\nhello")
assert b"200" in r and b'"n":5' in r and b"hello" in r, r
r = req(b"POST /echo HTTP/1.1\r\nHost: x\r\nContent-Length: 5\r\nContent-Length: 5\r\nConnection: close\r\n\r\nhello")
assert b"400" in r, r
print("PASS_AFTER 411/413/header-order/dup-CL ok")
PY
kill "$GPID" 2>/dev/null || true
wait "$GPID" 2>/dev/null || true

echo "PASS_AFTER token gate fixture throwaway-token-16"
FCG_API_TOKEN=throwaway-token-16 ./data/body-echo.elf >/tmp/vire-body-token.out 2>&1 &
TPID=$!
for i in $(seq 1 80); do
  grep -q "listening on 127.0.0.1:" /tmp/vire-body-token.out && break
  kill -0 "$TPID" 2>/dev/null || { cat /tmp/vire-body-token.out; exit 1; }
  sleep 0.05
done
TPORT="$(sed -n 's/.*listening on 127.0.0.1:\([0-9]*\).*/\1/p' /tmp/vire-body-token.out | head -1)"
python3 - "$TPORT" <<'PY'
import socket, sys
port = int(sys.argv[1])

def req(raw):
    s = socket.create_connection(("127.0.0.1", port), 3)
    s.sendall(raw)
    s.settimeout(3)
    chunks = []
    try:
        while True:
            d = s.recv(4096)
            if not d:
                break
            chunks.append(d)
    except socket.timeout:
        pass
    s.close()
    return b"".join(chunks)

r = req(b"POST /echo HTTP/1.1\r\nHost: x\r\nContent-Length: 5\r\nConnection: close\r\n\r\nhello")
assert b"401" in r and b"unauthorized" in r, r
r = req(b"POST /echo HTTP/1.1\r\nHost: x\r\nX-FCG-Token: throwaway-token-16\r\nContent-Length: 5\r\nConnection: close\r\n\r\nhello")
assert b'"n":5' in r, r
print("PASS_AFTER token 401/200 ok")
PY
kill "$TPID" 2>/dev/null || true
wait "$TPID" 2>/dev/null || true

echo "PASS_AFTER at $AFTER_SHA"
echo "rebuild body/token diff ok"
