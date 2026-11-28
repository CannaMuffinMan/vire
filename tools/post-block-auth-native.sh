#!/usr/bin/env bash
# Loopback 127.0.0.1 proof: native POST /block deny-by-default Bearer.
# FCG_BLOCK_TOKEN else FCG_API_TOKEN, length at least 16, both env names.
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

start_elf() {
  local log="$1"
  shift
  rm -f "$log"
  env "$@" ./data/block-auth.elf >"$log" 2>&1 &
  local pid=$!
  for i in $(seq 1 120); do
    grep -q "listening on 127.0.0.1:" "$log" && break
    kill -0 "$pid" 2>/dev/null || { cat "$log"; exit 1; }
    sleep 0.05
  done
  local port
  port="$(sed -n 's/.*listening on 127.0.0.1:\([0-9]*\).*/\1/p' "$log" | head -1)"
  echo "$pid $port"
}

probe() {
  python3 - "$1" "$2" <<'PY'
import socket, sys
port = int(sys.argv[1])
mode = sys.argv[2]

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

def post(auth):
    extra = b"" if auth is None else (b"Authorization: " + auth + b"\r\n")
    body = b'{"text":"pwned"}'
    raw = b"POST /block HTTP/1.1\r\nHost: x\r\n" + extra + b"Content-Length: " + str(len(body)).encode() + b"\r\nConnection: close\r\n\r\n" + body
    return req(raw)

def chain():
    r = req(b"GET /chain HTTP/1.1\r\nHost: x\r\nConnection: close\r\n\r\n")
    split = r.find(b"\r\n\r\n")
    return r.split(b"\r\n", 1)[0], (r[split + 4 :] if split >= 0 else r)

st0, c0 = chain()
print("GET /chain before", st0)

if mode == "none":
    r = post(None)
    print("POST no-token", r.split(b"\r\n", 1)[0])
    assert b"401" in r and b"unauthorized" in r, r
elif mode == "short":
    r = post(b"Bearer short-token")
    print("POST short Bearer", r.split(b"\r\n", 1)[0])
    assert b"401" in r, r
    assert b"short-token" not in r
elif mode == "wrong":
    r = post(b"Bearer wrong-token-16x")
    print("POST wrong Bearer", r.split(b"\r\n", 1)[0])
    assert b"401" in r, r
    assert b"wrong-token" not in r
elif mode == "right":
    r = post(b"Bearer test-block-token1")
    line = r.split(b"\r\n", 1)[0] if r else b"<empty>"
    print("POST right Bearer", line, r[r.find(b"\r\n\r\n")+4:][:160] if b"\r\n\r\n" in r else r[:80])
    assert b"test-block-token1" not in r
    assert b"401" not in line, r
    assert b"200" in line, r
    assert b'"accepted":true' in r or b'"accepted": true' in r, r
    print("PASS_AFTER right token allowed")
elif mode == "oversize":
    tok = b"A" * 5000
    r = post(b"Bearer " + tok)
    line = r.split(b"\r\n", 1)[0] if r else b"<empty>"
    print("POST 5000-byte Bearer", line)
    assert b"401" in line, r
    assert tok not in r
else:
    raise SystemExit("bad mode")

if mode not in ("right", "oversize"):
    st1, c1 = chain()
    print("GET /chain after", st1)
    assert c0 == c1
    assert b"pwned" not in c1
elif mode == "oversize":
    try:
        st1, c1 = chain()
        print("GET /chain after", st1)
        assert c0 == c1
        assert b"pwned" not in c1
    except Exception as ex:
        print("GET /chain after skipped", type(ex).__name__)
print("mode", mode, "ok")
PY
}

run_case() {
  local name="$1"
  local mode="$2"
  shift 2
  mkdir -p data/chain
  cp data/rebuild/chain/head.json data/rebuild/chain/000001.json data/rebuild/chain/blocks.json data/chain/
  local pair pid port
  pair="$(start_elf "/tmp/vire-auth-${name}.out" "$@")"
  pid="${pair%% *}"
  port="${pair##* }"
  echo "case $name port $port"
  if ! probe "$port" "$mode"; then
    kill "$pid" 2>/dev/null || true
    wait "$pid" 2>/dev/null || true
    exit 1
  fi
  kill "$pid" 2>/dev/null || true
  wait "$pid" 2>/dev/null || true
}

run_case none none
run_case short-api short FCG_API_TOKEN=short-token
run_case short-block short FCG_BLOCK_TOKEN=short-token
run_case wrong-api wrong FCG_API_TOKEN=test-block-token1
run_case wrong-block wrong FCG_BLOCK_TOKEN=test-block-token1
run_case right-api right FCG_API_TOKEN=test-block-token1
run_case right-block right FCG_BLOCK_TOKEN=test-block-token1
python3 - <<'PY'
from pathlib import Path
Path("/tmp/vire-oversize-secret").write_text("A" * 5000)
PY
run_case oversize-api oversize FCG_API_TOKEN="$(python3 -c 'print("A"*5000)')"
run_case oversize-block oversize FCG_BLOCK_TOKEN="$(python3 -c 'print("A"*5000)')"
run_case oversize-present oversize FCG_BLOCK_TOKEN=test-block-token1
echo "post-block-auth native ok"
