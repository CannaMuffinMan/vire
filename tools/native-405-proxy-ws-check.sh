#!/usr/bin/env bash
# Packed native residuals: dashboard 405 wire status, listen POST /proxy body,
# apigo-ws RFC 6455 upgrade (not JSON {"status":101}). Caps unchanged.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
export PATH="${HOME}/.dotnet:${PATH:-}"
export DOTNET_ROOT="${DOTNET_ROOT:-$HOME/.dotnet}"
export VIRE_HEADLESS=1
unset VIRE_BUDGET || true
unset FCG_API_TOKEN || true

python3 - <<'PY'
from pathlib import Path
rt = Path("src/rt.vire").read_text()
assert "33554432" in rt
cs = Path("Vire.cs").read_text()
assert "100000" in cs
assert "5000000" in cs
print("caps_src_ok arena=33554432 list=100000 steps=5000000 itemCap=1e6")
PY

dotnet build vire.csproj -c Release --nologo
bash "$ROOT/tools/stage-compiler-src.sh"

hex_to_bin() {
  python3 - "$1" "$2" <<'PY'
import pathlib, sys
pathlib.Path(sys.argv[2]).write_bytes(bytes.fromhex(pathlib.Path(sys.argv[1]).read_text().strip()))
PY
}

wait_listen() {
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

VIRE_DLL="$ROOT/bin/Release/net10.0/vire.dll"
STAGE="$ROOT/data/native-405-proxy-ws"
mkdir -p "$STAGE"

echo "=== 405 wire status ==="
cat > "$STAGE/st405.vire" <<'VIRE'
define route with method, path, body
  return "{\"error\":\"method_not_allowed\",\"status\":405}"
end
define main
  listen with 0
end
VIRE
rm -f "$STAGE/st405.hex" "$STAGE/st405.elf"
dotnet exec "$VIRE_DLL" --compiler compile-native.vire data/native-405-proxy-ws/st405.vire data/native-405-proxy-ws/st405.hex
hex_to_bin "$STAGE/st405.hex" "$STAGE/st405.elf"
chmod +x "$STAGE/st405.elf"
rm -f /tmp/vire-st405-host.out /tmp/vire-st405-nat.out
dotnet exec "$VIRE_DLL" "$STAGE/st405.vire" >/tmp/vire-st405-host.out 2>&1 &
H405=$!
./data/native-405-proxy-ws/st405.elf >/tmp/vire-st405-nat.out 2>&1 &
N405=$!
HP405="$(wait_listen /tmp/vire-st405-host.out)"
NP405="$(wait_listen /tmp/vire-st405-nat.out)"
python3 - "$HP405" "$NP405" <<'PY'
import socket, sys
def hit(port):
    s = socket.create_connection(("127.0.0.1", int(port)), 4)
    s.sendall(b"GET /x HTTP/1.1\r\nHost: x\r\nConnection: close\r\n\r\n")
    s.settimeout(4)
    data = b""
    while True:
        try:
            c = s.recv(4096)
        except socket.timeout:
            break
        if not c:
            break
        data += c
    s.close()
    line = data.split(b"\r\n", 1)[0]
    status = int(line.split()[1])
    body = data.split(b"\r\n\r\n", 1)[1] if b"\r\n\r\n" in data else b""
    print("wire", port, status, body[:80])
    return status, body
hs, hb = hit(sys.argv[1])
ns, nb = hit(sys.argv[2])
if hs != 405:
    raise SystemExit("host 405 expected, got %s %r" % (hs, hb))
if ns != 405:
    raise SystemExit("FAIL native wire %s body %r (want HTTP 405)" % (ns, nb[:80]))
print("PASS 405 host_native_match")
PY
kill "$H405" "$N405" 2>/dev/null || true
wait "$H405" 2>/dev/null || true
wait "$N405" 2>/dev/null || true

echo "=== POST /proxy body ==="
bash "$ROOT/tools/proxy-reply-proof.sh"

echo "=== apigo-ws upgrade ==="
bash "$ROOT/tools/apigo-ws-linux.sh"

echo "PASS_AFTER packed 405 / POST proxy / apigo-ws"
echo "Linux ELF is not Windows PE proof"
