#!/usr/bin/env bash
# Isolated tamper detection reproducer (security property).
# FAIL_BEFORE: snapshot guest that does not re-hash stored segments.
# PASS_AFTER: guest-chain.vire returns 503 chain invalid after a data/chain
# segment text is altered. ELF only on this host; PE is CouchStation.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
export PATH="${HOME}/.dotnet:${PATH:-}"
export DOTNET_ROOT="${DOTNET_ROOT:-$HOME/.dotnet}"
export VIRE_HEADLESS=1
unset VIRE_BUDGET || true

AFTER_SHA="$(git rev-parse HEAD)"
BEFORE_SHA="$(git rev-parse df58afd1d401c67bf8b086f447399162b3cc8b78 2>/dev/null || git rev-parse HEAD^)"
VIRE_DLL="$ROOT/bin/Release/net10.0/vire.dll"
FIX_SRC="$ROOT/data/rebuild/chain"
FIX_DST="$ROOT/data/chain"

dotnet build vire.csproj -c Release --nologo >/dev/null

hex_to_bin() {
  python3 - "$1" "$2" <<'PY'
import pathlib, sys
pathlib.Path(sys.argv[2]).write_bytes(bytes.fromhex(pathlib.Path(sys.argv[1]).read_text().strip()))
PY
}

compile_guest() {
  local src="$1"
  local stem="$2"
  python3 - "$src" "$ROOT/${stem}-run.vire" "data/${stem}.vire" <<'PY'
from pathlib import Path
import sys
text = Path(sys.argv[1]).read_text()
text = text.replace("listen with 18080", "listen with 0")
Path(sys.argv[2]).write_text(text)
Path(sys.argv[3]).write_text(text)
PY
  rm -f "data/${stem}.hex" "data/${stem}.elf"
  dotnet exec "$VIRE_DLL" --compiler compile-native.vire "data/${stem}.vire" "data/${stem}.hex"
  hex_to_bin "data/${stem}.hex" "data/${stem}.elf"
  chmod +x "data/${stem}.elf"
}

run_cmd() {
  local name="$1"
  shift
  local out="/tmp/vire-tamper-${name}.out"
  rm -f "$out"
  "$@" >"$out" 2>&1 &
  local pid=$!
  local i
  for i in $(seq 1 200); do
    if grep -q "listening on 127.0.0.1:" "$out" 2>/dev/null; then
      break
    fi
    if ! kill -0 "$pid" 2>/dev/null; then
      cat "$out"
      echo "guest $name exited before listen"
      exit 1
    fi
    sleep 0.05
  done
  local port
  port="$(sed -n 's/.*listening on 127.0.0.1:\([0-9]*\).*/\1/p' "$out" | head -1)"
  echo "$pid $port"
}

stop_guest() {
  kill "$1" 2>/dev/null || true
  wait "$1" 2>/dev/null || true
}

install_fix() {
  rm -rf "$FIX_DST"
  mkdir -p "$FIX_DST"
  cp "$FIX_SRC/head.json" "$FIX_DST/head.json"
  cp "$FIX_SRC/000001.json" "$FIX_DST/000001.json"
  cp "$FIX_SRC/blocks.json" "$FIX_DST/blocks.json"
}

echo "tamper_fail_before_sha $BEFORE_SHA"
echo "tamper_pass_after_sha $AFTER_SHA"
echo "property: POST/GET after mutating data/chain/000001.json text must be HTTP 503 chain invalid"
echo "platform: Linux ELF (this script). Windows PE unproven here; CouchStation tools/rebuild-fcgcpa-windows.ps1"
echo "residual: verify re-hashes stored compact JSON fields; a rewrite that keeps proofs consistent is accepted. Files stay under data/ with openat O_NOFOLLOW. Native has no erase; migrate overwrites data/chain.json with empty text. Arena 32MB / list 100000 / steps 5M unchanged. Native listen does not GC between huge-chain requests; harness restarts guests before pair."

compile_guest "$ROOT/tests/rebuild/fail-before-chain-remainder.vire" "tamper-fail"
install_fix
ids="$(run_cmd fail "./data/tamper-fail.elf")"
FPID="${ids%% *}"
FPORT="${ids##* }"
set +e
python3 - "$FPORT" "$FIX_DST" <<'PY'
import socket, sys
from pathlib import Path

def http(port, method, path, body):
    payload = body.encode() if body else b""
    lines = ["%s %s HTTP/1.1" % (method, path), "Host: 127.0.0.1", "Connection: close"]
    if method == "POST":
        lines += ["Content-Type: application/json", "Content-Length: %d" % len(payload)]
    req = ("\r\n".join(lines) + "\r\n\r\n").encode() + payload
    s = socket.create_connection(("127.0.0.1", int(port)), 5)
    s.sendall(req)
    s.settimeout(5)
    data = b""
    try:
        while True:
            n = s.recv(4096)
            if not n:
                break
            data += n
    except socket.timeout:
        pass
    s.close()
    head, body = data.split(b"\r\n\r\n", 1)
    status = int(head.split()[1])
    return status, body.decode()

port = sys.argv[1]
dst = Path(sys.argv[2])
st, body = http(port, "POST", "/block", '{"text":"keep"}')
if st != 200:
    print("setup failed", st, body)
    sys.exit(4)
raw = (dst / "000001.json").read_text()
(dst / "000001.json").write_text(raw.replace("keep", "tamper"))
st, body = http(port, "POST", "/block", '{"text":"more"}')
print("fail_before tamper POST status", st, "body", body)
if st == 503:
    print("FAIL_BEFORE unexpectedly 503")
    sys.exit(1)
print("FAIL_BEFORE tamper not 503 as required")
PY
FCODE=$?
set -e
stop_guest "$FPID"
if [[ "$FCODE" -ne 0 ]]; then
  echo "tamper FAIL_BEFORE harness error $FCODE"
  exit 1
fi

compile_guest "$ROOT/guest-chain.vire" "tamper-pass"
install_fix
ids="$(run_cmd pass "./data/tamper-pass.elf")"
GPID="${ids%% *}"
GPORT="${ids##* }"
python3 - "$GPORT" "$FIX_DST" <<'PY'
import socket, sys
from pathlib import Path

def http(port, method, path, body):
    payload = body.encode() if body else b""
    lines = ["%s %s HTTP/1.1" % (method, path), "Host: 127.0.0.1", "Connection: close"]
    if method == "POST":
        lines += ["Content-Type: application/json", "Content-Length: %d" % len(payload)]
    req = ("\r\n".join(lines) + "\r\n\r\n").encode() + payload
    s = socket.create_connection(("127.0.0.1", int(port)), 5)
    s.sendall(req)
    s.settimeout(5)
    data = b""
    try:
        while True:
            n = s.recv(4096)
            if not n:
                break
            data += n
    except socket.timeout:
        pass
    s.close()
    head, body = data.split(b"\r\n\r\n", 1)
    status = int(head.split()[1])
    return status, body.decode()

port = sys.argv[1]
dst = Path(sys.argv[2])
st, body = http(port, "POST", "/block", '{"text":"keep"}')
if st != 200:
    print("setup failed", st, body)
    raise SystemExit(4)
raw = (dst / "000001.json").read_text()
(dst / "000001.json").write_text(raw.replace("keep", "tamper"))
st, body = http(port, "POST", "/block", '{"text":"more"}')
print("pass_after tamper POST status", st, "body", body)
want = '{"ok":false,"status":503,"error":"chain invalid"}'
if st != 503 or body != want:
    print("PASS_AFTER tamper mismatch")
    raise SystemExit(2)
st2, body2 = http(port, "GET", "/chain", None)
print("pass_after tamper GET status", st2, "body", body2)
if st2 != 503 or body2 != want:
    print("PASS_AFTER GET tamper mismatch")
    raise SystemExit(2)
print("PASS_AFTER tamper 503")
PY
stop_guest "$GPID"
echo "PASS_AFTER at $AFTER_SHA tamper -> 503 on native ELF"
echo "rebuild chain tamper ok"
