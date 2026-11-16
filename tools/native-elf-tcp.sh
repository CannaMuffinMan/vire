#!/usr/bin/env bash
# Loopback TCP connect/send/recv/close and listen/accept on Linux ELF.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
export PATH="${HOME}/.dotnet:${PATH:-}"
export DOTNET_ROOT="${DOTNET_ROOT:-$HOME/.dotnet}"
export VIRE_HEADLESS=1
unset VIRE_BUDGET || true
AFTER_SHA="$(git rev-parse HEAD)"
echo "pass_after_sha $AFTER_SHA"
dotnet build vire.csproj -c Release --nologo
mkdir -p data

python3 - <<'PY' &
import socket, threading, os
s = socket.socket()
s.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
s.bind(("127.0.0.1", 0))
s.listen(8)
port = s.getsockname()[1]
open("/tmp/vire-elf-echo.port", "w").write(str(port))
print("echo_listen 127.0.0.1:%s" % port, flush=True)
while True:
    c, _ = s.accept()
    data = c.recv(4096)
    if data:
        c.sendall(data)
    c.close()
PY
for i in $(seq 1 50); do
  if [[ -f /tmp/vire-elf-echo.port ]]; then break; fi
  sleep 0.05
done
PORT="$(cat /tmp/vire-elf-echo.port)"
echo "echo_port $PORT"
sed "s/PORT_PLACEHOLDER/${PORT}/" tests/native/tcp-client.vire > data/tcp-client.vire
rm -f data/tcp-client.hex
dotnet exec bin/Release/net10.0/vire.dll --compiler compile-native.vire data/tcp-client.vire data/tcp-client.hex
python3 - <<'PY'
from pathlib import Path
Path("data/tcp-client.elf").write_bytes(bytes.fromhex(Path("data/tcp-client.hex").read_text().strip()))
PY
chmod +x data/tcp-client.elf
OUT="$(./data/tcp-client.elf)"
CODE=$?
echo "$OUT"
echo "tcp_elf_exit $CODE"
if [[ "$CODE" -ne 0 ]]; then
  echo "tcp ELF exit $CODE"
  exit 1
fi
echo "$OUT" | grep -qx "hi"
echo "$OUT" | grep -qx "up"
echo "$OUT" | grep -qx "ping"
echo "$OUT" | grep -q "refused-port"
echo "$OUT" | grep -q "connect stays off this machine and private networks"
echo "$OUT" | grep -qx "2"

cat > data/elf-listen.vire <<'EOF'
define route with method, path, body
  return "{\"ok\":true}"
end
define main
  listen with 0
end
EOF
rm -f data/elf-listen.hex
dotnet exec bin/Release/net10.0/vire.dll --compiler compile-native.vire data/elf-listen.vire data/elf-listen.hex
python3 - <<'PY'
from pathlib import Path
Path("data/elf-listen.elf").write_bytes(bytes.fromhex(Path("data/elf-listen.hex").read_text().strip()))
PY
chmod +x data/elf-listen.elf
rm -f /tmp/vire-elf-listen.out
./data/elf-listen.elf >/tmp/vire-elf-listen.out 2>&1 &
LPID=$!
for i in $(seq 1 100); do
  if grep -q "listening on 127.0.0.1:" /tmp/vire-elf-listen.out 2>/dev/null; then break; fi
  sleep 0.05
done
cat /tmp/vire-elf-listen.out
LPORT="$(sed -n 's/.*listening on 127.0.0.1:\([0-9]*\).*/\1/p' /tmp/vire-elf-listen.out | head -1)"
echo "listen_port $LPORT"
python3 - <<PY
import socket
p = int("${LPORT}")
s = socket.create_connection(("127.0.0.1", p), 2)
s.sendall(b"GET /health HTTP/1.1\r\nHost: 127.0.0.1\r\nConnection: close\r\n\r\n")
s.settimeout(3)
chunks = []
try:
    while True:
        data = s.recv(4096)
        if not data:
            break
        chunks.append(data)
except socket.timeout:
    pass
s.close()
body = b"".join(chunks)
print(body[:400])
if b"HTTP/1.1" not in body and b"{" not in body:
    raise SystemExit("listen accept did not serve HTTP")
PY
kill "$LPID" 2>/dev/null || true
wait "$LPID" 2>/dev/null || true
echo "PASS_AFTER at $AFTER_SHA ELF loopback connect/send/recv/close and listen/accept"
echo "native elf tcp ok"
