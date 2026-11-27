#!/usr/bin/env bash
# Loopback 127.0.0.1 proof: native POST /block deny-by-default Bearer.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
export PATH="${HOME}/.dotnet:${PATH:-}"
export DOTNET_ROOT="${DOTNET_ROOT:-$HOME/.dotnet}"
export DOTNET_CLI_TELEMETRY_OPTOUT=1
export VIRE_HEADLESS=1
unset VIRE_BUDGET FCG_API_TOKEN FCG_BLOCK_TOKEN || true
AFTER="$(git rev-parse HEAD)"
echo "pass_after_sha $AFTER"
bash "$ROOT/tools/stage-compiler-src.sh" >/tmp/vire-auth-stage.log
dotnet build vire.csproj -c Release --nologo >/tmp/vire-auth-build.log
python3 - <<'PY'
from pathlib import Path
text = Path("guest-chain.vire").read_text().replace("listen with 18080", "listen with 0")
Path("data").mkdir(exist_ok=True)
Path("data/block-auth.vire").write_text(text)
PY
rm -f data/block-auth.hex data/block-auth.elf
dotnet exec bin/Release/net10.0/vire.dll --compiler compile-native.vire data/block-auth.vire data/block-auth.hex
python3 - <<'PY'
from pathlib import Path
Path("data/block-auth.elf").write_bytes(bytes.fromhex(Path("data/block-auth.hex").read_text().strip()))
PY
chmod +x data/block-auth.elf
mkdir -p data/chain
cp data/rebuild/chain/head.json data/rebuild/chain/000001.json data/rebuild/chain/blocks.json data/chain/

rm -f /tmp/vire-auth-short.out
FCG_API_TOKEN=short-token ./data/block-auth.elf >/tmp/vire-auth-short.out 2>&1 &
SPID=$!
for i in $(seq 1 120); do
  grep -q "listening on 127.0.0.1:" /tmp/vire-auth-short.out && break
  kill -0 "$SPID" 2>/dev/null || { cat /tmp/vire-auth-short.out; exit 1; }
  sleep 0.05
done
SPORT="$(sed -n 's/.*listening on 127.0.0.1:\([0-9]*\).*/\1/p' /tmp/vire-auth-short.out | head -1)"
python3 - "$SPORT" <<'PY'
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

def chain():
    r = req(b"GET /chain HTTP/1.1\r\nHost: x\r\nConnection: close\r\n\r\n")
    split = r.find(b"\r\n\r\n")
    return r.split(b"\r\n", 1)[0], r[split + 4 :]

st0, c0 = chain()
print("GET /chain before", st0)
post = b'POST /block HTTP/1.1\r\nHost: x\r\nContent-Length: 16\r\nConnection: close\r\n\r\n{"text":"pwned"}'
r = req(post)
print("POST short-secret", r.split(b"\r\n", 1)[0])
print("body", r[r.find(b"\r\n\r\n") + 4 :][:200] if b"\r\n\r\n" in r else r[:200])
assert b"401" in r and b"unauthorized" in r, r
assert b"short-token" not in r
st1, c1 = chain()
print("GET /chain after", st1)
assert c0 == c1
assert b"pwned" not in c1
print("PASS_AFTER short configured secret 401 chain unchanged")
health = req(b"GET /health HTTP/1.1\r\nHost: x\r\nConnection: close\r\n\r\n")
info = req(b"GET /info HTTP/1.1\r\nHost: x\r\nConnection: close\r\n\r\n")
print("GET /health", health.split(b"\r\n", 1)[0])
print("GET /info", info.split(b"\r\n", 1)[0])
assert b"401" not in health.split(b"\r\n", 1)[0]
assert b"401" not in info.split(b"\r\n", 1)[0]
PY
kill "$SPID" 2>/dev/null || true
wait "$SPID" 2>/dev/null || true

rm -f /tmp/vire-auth-ok.out
FCG_BLOCK_TOKEN=test-block-token1 ./data/block-auth.elf >/tmp/vire-auth-ok.out 2>&1 &
OPID=$!
for i in $(seq 1 120); do
  grep -q "listening on 127.0.0.1:" /tmp/vire-auth-ok.out && break
  kill -0 "$OPID" 2>/dev/null || { cat /tmp/vire-auth-ok.out; exit 1; }
  sleep 0.05
done
OPORT="$(sed -n 's/.*listening on 127.0.0.1:\([0-9]*\).*/\1/p' /tmp/vire-auth-ok.out | head -1)"
python3 - "$OPORT" <<'PY'
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

r = req(b'POST /block HTTP/1.1\r\nHost: x\r\nX-FCG-Token: test-block-token1\r\nContent-Length: 2\r\nConnection: close\r\n\r\n{}')
print("X-FCG-Token only", r.split(b"\r\n", 1)[0])
assert b"401" in r
r = req(b'POST /block HTTP/1.1\r\nHost: x\r\nAuthorization: Bearer test-block-token1\r\nAuthorization: Bearer test-block-token1\r\nContent-Length: 2\r\nConnection: close\r\n\r\n{}')
print("dup Bearer", r.split(b"\r\n", 1)[0])
assert b"401" in r
r = req(b'POST /block HTTP/1.1\r\nHost: x\r\nAuthorization: Bearer test-block-token\r\nContent-Length: 2\r\nConnection: close\r\n\r\n{}')
print("prefix Bearer", r.split(b"\r\n", 1)[0])
assert b"401" in r
r = req(b'POST /block HTTP/1.1\r\nHost: x\r\nAuthorization: Bearer test-block-token1\r\nContent-Length: 2\r\nConnection: close\r\n\r\n{}')
print("good Bearer", r.split(b"\r\n", 1)[0] if r else b"<empty>", r[r.find(b"\r\n\r\n")+4:][:180] if b"\r\n\r\n" in r else b"")
assert b"test-block-token1" not in r
print("PASS_AFTER Bearer refuse cases (packed POST body residual may still crash/empty on authorized route)")
PY
kill "$OPID" 2>/dev/null || true
wait "$OPID" 2>/dev/null || true
echo "post-block-auth native ok"
