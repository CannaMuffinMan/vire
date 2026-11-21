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
  say got
  tls_close with h
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

cat > data/tls-badca.vire <<'EOF'
define main
  tls_connect with "127.0.0.1", 443, "localhost", "../etc/passwd"
end
EOF
rm -f data/tls-badca.hex
dotnet exec bin/Release/net10.0/vire.dll --compiler compile-native.vire data/tls-badca.vire data/tls-badca.hex
python3 - <<'PY'
from pathlib import Path
Path("data/tls-badca.elf").write_bytes(bytes.fromhex(Path("data/tls-badca.hex").read_text().strip()))
PY
chmod +x data/tls-badca.elf
set +e
BAD="$(./data/tls-badca.elf 2>&1)"
BADCODE=$?
set -e
echo "$BAD"
echo "tls_elf_badca_exit $BADCODE"
if [[ "$BADCODE" -eq 0 ]]; then
  echo "tls CA path outside data/ must fail"
  exit 1
fi
echo "$BAD" | grep -E -q "folder|inside|path"

cat > data/tls-listen.vire <<'EOF'
define route with method, path, body
  return "{\"ok\":true}"
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
set +e
LOUT="$(./data/tls-listen.elf 2>&1)"
LCODE=$?
set -e
echo "$LOUT"
echo "tls_listen_elf_exit $LCODE"
if [[ "$LCODE" -eq 0 ]]; then
  echo "native tls_listen must stay fail-closed"
  exit 1
fi
echo "$LOUT" | grep -q "fail-closed"

echo "PASS_AFTER at $AFTER_SHA ELF tls_connect ping round-trip; tls_listen fail-closed; CA sandbox on"
echo "native elf tls ok"
