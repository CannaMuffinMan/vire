#!/usr/bin/env bash
# Isolated WebSocket refusal: a refused upgrade must never be accepted.
# FAIL_BEFORE a64cfe5f: packed ELF 101s /ws/refuse; host 403s.
# PASS_AFTER: host and native both 403, no Switching Protocols.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
export PATH="${HOME}/.dotnet:${PATH:-}"
export DOTNET_ROOT="${DOTNET_ROOT:-$HOME/.dotnet}"
export VIRE_HEADLESS=1
unset VIRE_BUDGET || true
unset FCG_API_TOKEN || true

AFTER_SHA="$(git rev-parse HEAD)"
BEFORE_SHA="a64cfe5fdb398ac7c8049bd41ac431d780a0b09e"
VIRE_DLL="$ROOT/bin/Release/net10.0/vire.dll"
GUEST="$ROOT/tests/rebuild/guests/listen-ws.vire"

python3 - <<'PY'
from pathlib import Path
rt = Path("src/rt.vire").read_text()
assert "33554432" in rt
cs = Path("Vire.cs").read_text()
assert "100000" in cs
assert "5000000" in cs
ws = Path("src/rt-ws.vire").read_text()
assert 'pin with labels, "rt_listen", image' not in ws
listen = Path("VireListen.cs").read_text()
assert 'headers.Path != "/ws/refuse"' not in listen
assert "wsIntent == 1 && code == 101" in listen
print("caps_src_ok arena=33554432 list=100000 steps=5000000")
print("security_property: route status!=101 => never RFC 6455 101")
PY

dotnet build vire.csproj -c Release --nologo
bash "$ROOT/tools/stage-compiler-src.sh"
mkdir -p data/native-ws-refuse

hex_to_bin() {
  python3 - "$1" "$2" <<'PY'
import pathlib, sys
pathlib.Path(sys.argv[2]).write_bytes(bytes.fromhex(pathlib.Path(sys.argv[1]).read_text().strip()))
PY
}

cp "$GUEST" data/native-ws-refuse/listen-ws.vire
rm -f data/native-ws-refuse/listen-ws.hex data/native-ws-refuse/listen-ws.elf
dotnet exec "$VIRE_DLL" --compiler compile-native.vire data/native-ws-refuse/listen-ws.vire data/native-ws-refuse/listen-ws.hex
hex_to_bin data/native-ws-refuse/listen-ws.hex data/native-ws-refuse/listen-ws.elf
chmod +x data/native-ws-refuse/listen-ws.elf

echo "fail_before_sha $BEFORE_SHA"
echo "pass_after_sha $AFTER_SHA"

run_listen() {
  local bin="$1"
  local out="$2"
  rm -f "$out"
  eval "$bin 18080" >"$out" 2>&1 &
  echo $!
}

wait_port() {
  local out="$1"
  local i
  for i in $(seq 1 200); do
    if grep -q "listening on 127.0.0.1:" "$out" 2>/dev/null; then
      sed -n 's/.*listening on 127.0.0.1:\([0-9]*\).*/\1/p' "$out" | head -1
      return 0
    fi
    sleep 0.05
  done
  cat "$out"
  echo "no listen port"
  return 1
}

probe() {
  python3 - "$1" <<'PY'
import socket, sys
port = int(sys.argv[1])
req = (
    b"GET /ws/refuse HTTP/1.1\r\nHost: 127.0.0.1\r\nUpgrade: websocket\r\n"
    b"Connection: Upgrade\r\nSec-WebSocket-Key: dGhlIHNhbXBsZSBub25jZQ==\r\n"
    b"Sec-WebSocket-Version: 13\r\n\r\n"
)
s = socket.create_connection(("127.0.0.1", port), 5)
s.settimeout(5)
s.sendall(req)
data = b""
while b"\r\n\r\n" not in data:
    chunk = s.recv(4096)
    if not chunk:
        break
    data += chunk
s.close()
sys.stdout.buffer.write(data)
if b"101" in data.split(b"\r\n", 1)[0] or b"Switching Protocols" in data:
    raise SystemExit("OPEN: upgrade accepted on refused path")
if b"403" not in data.split(b"\r\n", 1)[0]:
    raise SystemExit("expected 403, got %r" % data[:80])
print("", flush=True)
PY
}

HOST_PID="$(run_listen "dotnet exec \"$VIRE_DLL\" data/native-ws-refuse/listen-ws.vire" /tmp/vire-ws-refuse-host.out)"
HPORT="$(wait_port /tmp/vire-ws-refuse-host.out)"
NAT_PID="$(run_listen "$ROOT/data/native-ws-refuse/listen-ws.elf" /tmp/vire-ws-refuse-nat.out)"
NPORT="$(wait_port /tmp/vire-ws-refuse-nat.out)"
echo "host_listen $HPORT native_listen $NPORT"

canon() {
  python3 -c 'import sys,re; d=sys.stdin.buffer.read(); t=d.decode("latin1","replace"); t=re.sub(r"HTTP/1.1 (\d+) [^\r]*", r"HTTP/1.1 \1", t); print(t.split("\r\n")[0])'
}
HOST_T="$(probe "$HPORT" | canon)"
NAT_T="$(probe "$NPORT" | canon)"
echo "host $HOST_T"
echo "native $NAT_T"
if [[ "$HOST_T" != "$NAT_T" ]]; then
  echo "HOST_NATIVE_MISMATCH refuse"
  kill "$HOST_PID" "$NAT_PID" 2>/dev/null || true
  exit 3
fi
echo "$HOST_T" | grep -q "403" || { echo "missing 403"; exit 2; }
echo "$HOST_T" | grep -q "101" && { echo "101 on refuse"; exit 2; } || true
echo "HOST_NATIVE_MATCH refuse 403"
echo "PASS_AFTER at $AFTER_SHA"
kill "$HOST_PID" "$NAT_PID" 2>/dev/null || true
wait "$HOST_PID" "$NAT_PID" 2>/dev/null || true
echo "ws refuse proof ok"
