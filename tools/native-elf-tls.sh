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
rm -f /tmp/vire-elf-tls.port /tmp/vire-tls-health.out /tmp/vire-tls-health.port
pkill -f vire-elf-tls.port >/dev/null 2>&1 || true
openssl req -x509 -newkey rsa:2048 -keyout data/tls-elf-key.pem -out data/tls-elf-cert.pem -days 1 -nodes \
  -subj /CN=localhost -addext "subjectAltName=DNS:localhost,IP:127.0.0.1" >/tmp/vire-tls-cert.log 2>&1
cp data/tls-elf-cert.pem data/tls-health-cert.pem
cp data/tls-elf-key.pem data/tls-health-key.pem
BASE_SHA="5c1f89adb5952f6c72037edbc8a856c3fd03bfdf"
echo "fail_before_sha $BASE_SHA"
if git cat-file -e "${BASE_SHA}^{commit}" 2>/dev/null; then
  if git show "${BASE_SHA}:src/rt-tls.vire" | grep -q "native tls_listen is fail-closed"; then
    echo "FAIL_BEFORE at $BASE_SHA native tls_listen fail-closed in src/rt-tls.vire"
  else
    echo "FAIL_BEFORE marker missing at $BASE_SHA"
    exit 1
  fi
fi

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
if [[ -n "$BAD" ]]; then
  echo "$BAD" | grep -E -q "folder|inside|path"
fi
echo "tls_elf_badca_fail_closed"

cp guest-health-tls.vire data/guest-health-tls.vire
rm -f data/guest-health-tls.hex
dotnet exec bin/Release/net10.0/vire.dll --compiler compile-native.vire data/guest-health-tls.vire data/guest-health-tls.hex
python3 - <<'PY'
from pathlib import Path
Path("data/guest-health-tls.elf").write_bytes(bytes.fromhex(Path("data/guest-health-tls.hex").read_text().strip()))
PY
chmod +x data/guest-health-tls.elf
H1="$(sha256sum data/guest-health-tls.hex | awk '{print $1}')"
for run in 2 3; do
  rm -f data/guest-health-tls.hex
  dotnet exec bin/Release/net10.0/vire.dll --compiler compile-native.vire data/guest-health-tls.vire data/guest-health-tls.hex
  Hn="$(sha256sum data/guest-health-tls.hex | awk '{print $1}')"
  echo "tls_health_elf_sha_run${run} $Hn"
  if [[ "$Hn" != "$H1" ]]; then
    echo "ELF gen hashes differ"
    exit 1
  fi
done
echo "tls_health_elf_sha $H1"

rm -f /tmp/vire-tls-health.port /tmp/vire-tls-health.out
./data/guest-health-tls.elf > /tmp/vire-tls-health.out 2>&1 &
HPID=$!
trap 'kill $HPID 2>/dev/null || true' EXIT
for i in $(seq 1 80); do
  if grep -q "listening on 127.0.0.1:" /tmp/vire-tls-health.out 2>/dev/null; then
    break
  fi
  if ! kill -0 $HPID 2>/dev/null; then
    cat /tmp/vire-tls-health.out
    echo "tls health ELF exited early"
    exit 1
  fi
  sleep 0.05
done
cat /tmp/vire-tls-health.out
HPORT="$(sed -n 's/listening on 127.0.0.1://p' /tmp/vire-tls-health.out | head -1)"
echo "tls_health_elf_port $HPORT"
if [[ -z "$HPORT" ]]; then
  echo "missing listen port"
  exit 1
fi
python3 - "$HPORT" <<'PY'
import ssl, socket, sys, json, pathlib
port = int(sys.argv[1])
contract = json.loads(pathlib.Path("tests/rebuild/contracts/health.json").read_text())
want = json.dumps(contract["body"], separators=(",", ":"))
ctx = ssl.SSLContext(ssl.PROTOCOL_TLS_CLIENT)
ctx.minimum_version = ssl.TLSVersion.TLSv1_2
ctx.load_verify_locations("data/tls-health-cert.pem")
s = socket.create_connection(("127.0.0.1", port), timeout=5)
t = ctx.wrap_socket(s, server_hostname="localhost")
t.sendall(b"GET /health HTTP/1.1\r\nHost: localhost\r\nConnection: close\r\n\r\n")
data = b""
while True:
    chunk = t.recv(4096)
    if not chunk:
        break
    data += chunk
t.close()
text = data.decode("ascii", "replace")
print(text)
if "HTTP/1.1 200" not in text:
    raise SystemExit("health status mismatch")
if want not in text.replace(" ", ""):
    body = text.split("\r\n\r\n", 1)[-1].strip()
    if json.dumps(json.loads(body), separators=(",", ":")) != want:
        raise SystemExit("health body mismatch " + body)
print("elf_health_contract_ok")
# plaintext fail-closed
p = socket.create_connection(("127.0.0.1", port), timeout=5)
p.sendall(b"GET /health HTTP/1.1\r\nHost: localhost\r\n\r\n")
p.settimeout(2)
got = b""
try:
    while True:
        c = p.recv(256)
        if not c:
            break
        got += c
except Exception:
    pass
p.close()
if b"HTTP" in got or b"fcgcpa" in got:
    raise SystemExit("plaintext leaked HTTP")
print("elf_plaintext_fail_closed")
# truncated handshake
p = socket.create_connection(("127.0.0.1", port), timeout=5)
p.sendall(bytes([0x16, 0x03, 0x03, 0x00, 0x10, 0x01, 0x00]))
p.settimeout(2)
got = b""
try:
    while True:
        c = p.recv(256)
        if not c:
            break
        got += c
except Exception:
    pass
p.close()
if b"HTTP" in got:
    raise SystemExit("truncated handshake leaked HTTP")
print("elf_truncated_fail_closed")
# TLS 1.0 fail-closed
try:
    ctx10 = ssl.SSLContext(ssl.PROTOCOL_TLS_CLIENT)
    ctx10.minimum_version = ssl.TLSVersion.TLSv1
    ctx10.maximum_version = ssl.TLSVersion.TLSv1
    ctx10.check_hostname = False
    ctx10.verify_mode = ssl.CERT_NONE
    p = socket.create_connection(("127.0.0.1", port), timeout=5)
    t10 = ctx10.wrap_socket(p, server_hostname="localhost")
    t10.close()
    raise SystemExit("tls1.0 handshake must fail")
except (ssl.SSLError, ValueError, OSError):
    print("elf_tls10_fail_closed")
PY

echo "PASS_AFTER at $AFTER_SHA ELF tls_connect ping; tls_listen /health contract; negatives fail-closed; CA sandbox on"
echo "native elf tls ok"
