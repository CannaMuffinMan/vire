#!/usr/bin/env bash
# wss:// over native tls_listen: same Upgrade hijack, local 127.0.0.1 test CA.
# Plaintext-to-TLS, bad cert, truncated handshake fail closed (TLS lane + this splice).
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
bash "$ROOT/tools/stage-compiler-src.sh"
mkdir -p data
python3 - "$ROOT/data/tls-health-cert.pem" "$ROOT/data/tls-health-key.pem" <<'PY'
import pathlib, subprocess, sys, textwrap, os
cert, key = sys.argv[1], sys.argv[2]
d = pathlib.Path("/tmp/vire-mkcert")
d.mkdir(exist_ok=True)
(d / "vire-mkcert.csproj").write_text("""<Project Sdk="Microsoft.NET.Sdk">
  <PropertyGroup><OutputType>Exe</OutputType><TargetFramework>net10.0</TargetFramework><ImplicitUsings>enable</ImplicitUsings></PropertyGroup>
</Project>
""")
(d / "Program.cs").write_text(textwrap.dedent("""
using System.Net;
using System.Security.Cryptography;
using System.Security.Cryptography.X509Certificates;
string certPath = args[0];
string keyPath = args[1];
using RSA rsa = RSA.Create(2048);
CertificateRequest req = new CertificateRequest("CN=localhost", rsa, HashAlgorithmName.SHA256, RSASignaturePadding.Pkcs1);
SubjectAlternativeNameBuilder san = new SubjectAlternativeNameBuilder();
san.AddDnsName("localhost");
san.AddIpAddress(IPAddress.Loopback);
req.CertificateExtensions.Add(san.Build());
using X509Certificate2 cert = req.CreateSelfSigned(DateTimeOffset.UtcNow.AddHours(-1), DateTimeOffset.UtcNow.AddDays(1));
File.WriteAllText(certPath, cert.ExportCertificatePem());
File.WriteAllText(keyPath, rsa.ExportRSAPrivateKeyPem());
X509Certificate2 pem = X509Certificate2.CreateFromPemFile(certPath, keyPath);
X509CertificateLoader.LoadPkcs12(pem.Export(X509ContentType.Pfx), (string)null);
Console.WriteLine("ok");
"""))
env = os.environ.copy()
subprocess.check_call(["dotnet", "run", "--project", str(d), "-c", "Release", "--", cert, key], env=env)
PY
chmod 600 data/tls-health-key.pem
mkdir -p tests/rebuild/guests/data
cp -f data/tls-health-cert.pem tests/rebuild/guests/data/tls-health-cert.pem
cp -f data/tls-health-key.pem tests/rebuild/guests/data/tls-health-key.pem
chmod 600 tests/rebuild/guests/data/tls-health-key.pem

hex_to_bin() {
  python3 - "$1" "$2" <<'PY'
import pathlib, sys
pathlib.Path(sys.argv[2]).write_bytes(bytes.fromhex(pathlib.Path(sys.argv[1]).read_text().strip()))
PY
}

PORTFILE="/tmp/vire-listen-wss-up-$$.port"
rm -f "$PORTFILE"
python3 - "$PORTFILE" <<'PY' &
import base64, hashlib, socket, sys, threading
GUID = "258EAFA5-E914-47DA-95CA-C5AB0DC85B11"

def hdr(lines, name):
    want = name.lower() + ":"
    for line in lines[1:]:
        if line.lower().startswith(want):
            return line.split(":", 1)[1].strip()
    return ""

def has_token(value, token):
    return token.lower() in [p.strip().lower() for p in value.split(",")]

def read_exact(c, n, buf):
    while len(buf) < n:
        chunk = c.recv(4096)
        if not chunk:
            return None
        buf += chunk
    return buf

def handle(c):
    try:
        c.settimeout(5)
        data = b""
        while b"\r\n\r\n" not in data and len(data) < 16384:
            chunk = c.recv(4096)
            if not chunk:
                break
            data += chunk
        if b"\r\n\r\n" not in data:
            c.close(); return
        head, rest = data.split(b"\r\n\r\n", 1)
        lines = head.decode("ascii", "replace").split("\r\n")
        parts = lines[0].split(" ") if lines else []
        method = parts[0] if parts else "GET"
        key = hdr(lines, "sec-websocket-key")
        if method != "GET" or not has_token(hdr(lines, "upgrade"), "websocket"):
            c.close(); return
        accept = base64.b64encode(hashlib.sha1((key + GUID).encode("ascii")).digest())
        c.sendall(b"HTTP/1.1 101 Switching Protocols\r\nUpgrade: websocket\r\nConnection: Upgrade\r\nSec-WebSocket-Accept: " + accept + b"\r\n\r\n")
        buf = rest
        while True:
            buf = read_exact(c, 2, buf)
            if buf is None:
                break
            b0, b1 = buf[0], buf[1]
            op = b0 & 0x0F
            masked = (b1 & 0x80) != 0
            ln = b1 & 0x7F
            off = 2
            need = off + (4 if masked else 0) + ln
            buf = read_exact(c, need, buf)
            if buf is None:
                break
            payload = buf[off:]
            if masked:
                mask = payload[:4]
                payload = bytes(payload[i] ^ mask[i & 3] for i in range(len(payload)))
            buf = buf[need:]
            if op == 8:
                c.sendall(bytes([0x88, 0x00])); break
            if op == 9:
                c.sendall(bytes([0x8A, ln]) + payload); continue
            if op in (1, 2):
                c.sendall(bytes([0x80 | op, ln]) + payload)
        c.close()
    except Exception:
        try: c.close()
        except Exception: pass

s = socket.socket()
s.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
s.bind(("127.0.0.1", 0))
s.listen(16)
open(sys.argv[1], "w").write(str(s.getsockname()[1]))
while True:
    c, _ = s.accept()
    threading.Thread(target=handle, args=(c,), daemon=True).start()
PY
UP_PID=$!
for i in $(seq 1 50); do
  [[ -f "$PORTFILE" ]] && break
  sleep 0.05
done
UP="$(cat "$PORTFILE")"
echo "upstream_port $UP"

cp tests/rebuild/guests/listen-ws-tls.vire data/native-listen-wss.vire
# rewrite args port into a copy? guest reads args at 0
rm -f data/native-listen-wss.hex data/native-listen-wss.elf
dotnet exec bin/Release/net10.0/vire.dll --compiler compile-native.vire data/native-listen-wss.vire data/native-listen-wss.hex
hex_to_bin data/native-listen-wss.hex data/native-listen-wss.elf
chmod +x data/native-listen-wss.elf

run_one() {
  local cmd="$1"
  local out="$2"
  rm -f "$out"
  eval "$cmd" >"$out" 2>&1 &
  echo $!
}

waitp() {
  local out="$1"
  for i in $(seq 1 200); do
    if grep -q "listening on 127.0.0.1:" "$out" 2>/dev/null; then
      sed -n 's/.*listening on 127.0.0.1:\([0-9]*\).*/\1/p' "$out" | head -1
      return
    fi
    sleep 0.05
  done
  cat "$out"; echo "no tls listen"; return 1
}

HOST_PID="$(run_one "dotnet exec bin/Release/net10.0/vire.dll tests/rebuild/guests/listen-ws-tls.vire $UP" /tmp/vire-wss-host.out)"
HPORT="$(waitp /tmp/vire-wss-host.out)"
NAT_PID="$(run_one "./data/native-listen-wss.elf $UP" /tmp/vire-wss-nat.out)"
NPORT="$(waitp /tmp/vire-wss-nat.out)"
echo "host_wss $HPORT native_wss $NPORT"

wss_echo() {
  python3 - "$1" data/tls-health-cert.pem <<'PY'
import socket, ssl, sys
port = int(sys.argv[1])
ca = sys.argv[2]
ctx = ssl.SSLContext(ssl.PROTOCOL_TLS_CLIENT)
ctx.minimum_version = ssl.TLSVersion.TLSv1_2
ctx.check_hostname = False
ctx.verify_mode = ssl.CERT_REQUIRED
ctx.load_verify_locations(ca)
raw = socket.create_connection(("127.0.0.1", port), 5)
s = ctx.wrap_socket(raw, server_hostname="localhost")
s.settimeout(5)
s.sendall(
    b"GET /ws/echo HTTP/1.1\r\nHost: localhost\r\nUpgrade: websocket\r\nConnection: Upgrade\r\n"
    b"Sec-WebSocket-Key: dGhlIHNhbXBsZSBub25jZQ==\r\nSec-WebSocket-Version: 13\r\n\r\n"
)
buf = b""
while b"\r\n\r\n" not in buf:
    buf += s.recv(4096)
head, rest = buf.split(b"\r\n\r\n", 1)
s.sendall(bytes([0x81, 0x82, 0, 0, 0, 0]) + b"hi" + bytes([0x88, 0x80, 0, 0, 0, 0]))
got = rest
s.settimeout(0.25)
import time
deadline = time.time() + 2.0
while time.time() < deadline:
    if bytes([0x88, 0x00]) in got:
        break
    try:
        chunk = s.recv(4096)
        if not chunk:
            break
        got += chunk
    except TimeoutError:
        continue
s.close()
sys.stdout.buffer.write(head + b"\r\n\r\n" + got)
PY
}

HOST_E="$(wss_echo "$HPORT" | python3 -c 'import sys; print(sys.stdin.buffer.read().hex())')"
NAT_E="$(wss_echo "$NPORT" | python3 -c 'import sys; print(sys.stdin.buffer.read().hex())')"
echo "host_wss_hex $HOST_E"
echo "native_wss_hex $NAT_E"
python3 - "$HOST_E" "$NAT_E" <<'PY'
import sys
def canon(h):
    t = bytes.fromhex(h)
    i = t.find(b"\r\n\r\n")
    if i < 0:
        print("no headers", h[:80]); raise SystemExit(3)
    body = t[i+4:]
    j = body.find(bytes([0x88, 0x00]))
    if j < 0:
        print("no close", t.hex()); raise SystemExit(3)
    return t[: i+4+j+2]
h, n = canon(sys.argv[1]), canon(sys.argv[2])
if h != n:
    print("HOST_NATIVE_MISMATCH wss canon")
    print("h", h.hex()); print("n", n.hex())
    raise SystemExit(3)
print("HOST_NATIVE_MATCH wss canon")
PY
echo "$HOST_E" | grep -q "6869" || { echo "wss missing echo"; exit 2; }
echo "$HOST_E" | grep -q "8800" || { echo "wss missing close"; exit 2; }

echo "=== plaintext on tls port fail closed ==="
python3 - "$HPORT" <<'PY'
import socket, sys
s = socket.create_connection(("127.0.0.1", int(sys.argv[1])), 3)
s.settimeout(3)
s.sendall(b"GET /health HTTP/1.1\r\nHost: localhost\r\n\r\n")
try:
    data = s.recv(256)
except Exception:
    data = b""
s.close()
text = data.decode("latin1", "replace")
assert "HTTP/" not in text, text
assert "101" not in text
print("plaintext_fail_closed")
PY

echo "=== truncated handshake fail closed ==="
python3 - "$HPORT" <<'PY'
import socket, sys
s = socket.create_connection(("127.0.0.1", int(sys.argv[1])), 3)
s.settimeout(3)
s.sendall(bytes([0x16, 0x03, 0x03, 0x00, 0x10, 0x01, 0x00]))
try:
    data = s.recv(256)
except Exception:
    data = b""
s.close()
text = data.decode("latin1", "replace")
assert "HTTP/" not in text
print("truncated_fail_closed")
PY

echo "=== bad cert fail closed ==="
python3 - "$HPORT" <<'PY'
import socket, ssl, sys
ctx = ssl.SSLContext(ssl.PROTOCOL_TLS_CLIENT)
ctx.check_hostname = True
ctx.verify_mode = ssl.CERT_REQUIRED
# system store / empty CA: self-signed must fail
raw = socket.create_connection(("127.0.0.1", int(sys.argv[1])), 3)
try:
    s = ctx.wrap_socket(raw, server_hostname="localhost")
    s.sendall(b"GET / HTTP/1.1\r\n\r\n")
    raise SystemExit("bad cert accepted")
except ssl.SSLError:
    print("bad_cert_fail_closed")
except ssl.CertificateError:
    print("bad_cert_fail_closed")
PY

echo "PASS_AFTER at $AFTER_SHA wss listen hijack; plaintext/truncated/bad-cert fail closed"
kill "$HOST_PID" "$NAT_PID" "$UP_PID" 2>/dev/null || true
echo "rebuild listen wss diff ok"
