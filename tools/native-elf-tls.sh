#!/usr/bin/env bash
# Native ELF TLS vs openssl s_server / s_client. Certs generated at test time.
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
openssl req -x509 -newkey rsa:2048 -keyout data/tls-elf-key.pem -out data/tls-elf-cert.pem -days 1 -nodes -subj /CN=localhost >/tmp/vire-tls-cert.log 2>&1

python3 - <<'PY' &
import socket, ssl, threading, os, time
ctx = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
ctx.minimum_version = ssl.TLSVersion.TLSv1_2
ctx.load_cert_chain("data/tls-elf-cert.pem", "data/tls-elf-key.pem")
s = socket.socket()
s.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
s.bind(("127.0.0.1", 0))
s.listen(8)
port = s.getsockname()[1]
open("/tmp/vire-elf-tls.port", "w").write(str(port))
print("tls_echo 127.0.0.1:%s" % port, flush=True)
while True:
    c, _ = s.accept()
    try:
        t = ctx.wrap_socket(c, server_side=True)
        data = t.recv(4096)
        if data:
            t.sendall(data)
        import time
        time.sleep(0.2)
        t.close()
    except Exception:
        try: c.close()
        except Exception:
            pass
PY
for i in $(seq 1 50); do
  if [[ -f /tmp/vire-elf-tls.port ]]; then break; fi
  sleep 0.05
done
PORT="$(cat /tmp/vire-elf-tls.port)"
echo "tls_echo_port $PORT"

cat > data/tls-client.vire <<EOF
define main
  let h be tls_connect with "127.0.0.1", ${PORT}, "localhost", "data/tls-elf-cert.pem"
  tls_send with h, "ping"
  let got be tls_recv with h, 16
  tls_close with h
  say got
end
EOF

rm -f data/tls-client.hex
dotnet exec bin/Release/net10.0/vire.dll --compiler compile-native.vire data/tls-client.vire data/tls-client.hex
python3 - <<'PY'
from pathlib import Path
Path("data/tls-client.elf").write_bytes(bytes.fromhex(Path("data/tls-client.hex").read_text().strip()))
PY
chmod +x data/tls-client.elf
file data/tls-client.elf || true
readelf -d data/tls-client.elf | head -20 || true
OUT="$(./data/tls-client.elf)"
CODE=$?
echo "$OUT"
echo "tls_elf_client_exit $CODE"
if [[ "$CODE" -ne 0 ]]; then
  echo "tls client ELF exit $CODE"
  exit 1
fi
echo "$OUT" | grep -qx "ping"

cat > data/tls-listen.vire <<'EOF'
define route with method, path, body
  return "{\"ok\":true,\"tls\":true}"
end
define main
  tls_listen with 0, "data/tls-elf-cert.pem", "data/tls-elf-key.pem"
end
EOF
rm -f data/tls-listen.hex
dotnet exec bin/Release/net10.0/vire.dll --compiler compile-native.vire data/tls-listen.vire data/tls-listen.hex
python3 - <<'PY'
from pathlib import Path
Path("data/tls-listen.elf").write_bytes(bytes.fromhex(Path("data/tls-listen.hex").read_text().strip()))
PY
chmod +x data/tls-listen.elf
rm -f /tmp/vire-elf-tls-listen.out
./data/tls-listen.elf >/tmp/vire-elf-tls-listen.out 2>&1 &
LPID=$!
for i in $(seq 1 100); do
  if grep -q "listening on 127.0.0.1:" /tmp/vire-elf-tls-listen.out 2>/dev/null; then break; fi
  sleep 0.05
done
cat /tmp/vire-elf-tls-listen.out
LPORT="$(sed -n 's/.*listening on 127.0.0.1:\([0-9]*\).*/\1/p' /tmp/vire-elf-tls-listen.out | head -1)"
echo "tls_listen_port $LPORT"
echo "GET /health HTTP/1.1\r\nHost: localhost\r\nConnection: close\r\n\r\n" | openssl s_client -connect 127.0.0.1:${LPORT} -servername localhost -CAfile data/tls-elf-cert.pem -quiet -ign_eof > /tmp/vire-elf-tls-sclient.out 2>/tmp/vire-elf-tls-sclient.err || true
head -c 400 /tmp/vire-elf-tls-sclient.out; echo
grep -q "HTTP/1.1" /tmp/vire-elf-tls-sclient.out || grep -q "ok" /tmp/vire-elf-tls-sclient.out
kill "$LPID" 2>/dev/null || true
wait "$LPID" 2>/dev/null || true
echo "PASS_AFTER at $AFTER_SHA ELF TLS handshake vs openssl/python ssl peer"
echo "native elf tls ok"
