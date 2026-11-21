#!/usr/bin/env bash
# Host vs native: rpc-portal GET /api/rpc JSON must include "status":503.
# FAIL_BEFORE SHA 5c3ed01abe2a12a34fca74b915d5e39a9f05fde3 returned {"enabled":false}.
# Caps 32MB / 100000 / 5M. Loopback 127.0.0.1 only.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
export PATH="${HOME}/.dotnet:${PATH:-}"
export DOTNET_ROOT="${DOTNET_ROOT:-$HOME/.dotnet}"
export VIRE_HEADLESS=1
unset VIRE_BUDGET || true
unset FCG_API_TOKEN || true

AFTER_SHA="$(git rev-parse HEAD)"
BEFORE_SHA="5c3ed01abe2a12a34fca74b915d5e39a9f05fde3"
VIRE_DLL="$ROOT/bin/Release/net10.0/vire.dll"
CONTRACT="$ROOT/tests/rebuild/contracts/rpc-portal-go/api-rpc.json"

python3 - <<'PY'
from pathlib import Path
rt = Path("src/rt.vire").read_text()
assert "33554432" in rt
cs = Path("Vire.cs").read_text()
assert "5000000" in cs
print("caps_src_ok arena=33554432 list=100000 steps=5000000")
PY

if ! git cat-file -e "${BEFORE_SHA}:tests/rebuild/guests/rpc-portal-go.vire"; then
  echo "missing fail-before blob at $BEFORE_SHA"
  exit 1
fi
python3 - "$BEFORE_SHA" <<'PY'
import subprocess, sys
sha = sys.argv[1]
old = subprocess.check_output(["git", "show", f"{sha}:tests/rebuild/guests/rpc-portal-go.vire"], text=True)
if '{"enabled":false,"status":503}' in old:
    raise SystemExit("FAIL_BEFORE guest already had status field")
if 'return "{\\"enabled\\":false}"' not in old:
    raise SystemExit("FAIL_BEFORE guest missing enabled:false body")
print("fail_before_guest_body_ok")
PY
echo "FAIL_BEFORE at $BEFORE_SHA rpc-portal /api/rpc body {\"enabled\":false} (no status field)"

dotnet build vire.csproj -c Release --nologo
bash "$ROOT/tools/stage-compiler-src.sh" >/dev/null
mkdir -p data

hex_to_bin() {
  python3 - "$1" "$2" <<'PY'
import pathlib, sys
pathlib.Path(sys.argv[2]).write_bytes(bytes.fromhex(pathlib.Path(sys.argv[1]).read_text().strip()))
PY
}

compile_listen_guest() {
  local src="$1"
  local stem="$2"
  python3 - "$src" "data/${stem}.vire" <<'PY'
from pathlib import Path
import sys
text = Path(sys.argv[1]).read_text()
text = text.replace("listen with 18080", "listen with 0")
Path(sys.argv[2]).write_text(text)
PY
  cp "$ROOT/src/"*.vire "$ROOT/data/"
  rm -f "data/${stem}.hex" "data/${stem}.elf"
  dotnet exec "$VIRE_DLL" --compiler compile-native.vire "data/${stem}.vire" "data/${stem}.hex"
  hex_to_bin "data/${stem}.hex" "data/${stem}.elf"
  chmod +x "data/${stem}.elf"
}

run_cmd() {
  local name="$1"
  shift
  local out="/tmp/vire-rebuild-${name}.out"
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
  if [[ -z "$port" ]]; then
    cat "$out"
    echo "no listen port for $name"
    kill "$pid" 2>/dev/null || true
    wait "$pid" 2>/dev/null || true
    exit 1
  fi
  echo "$pid $port"
}

stop_guest() {
  local pid="$1"
  kill "$pid" 2>/dev/null || true
  wait "$pid" 2>/dev/null || true
}

git show "${BEFORE_SHA}:tests/rebuild/guests/rpc-portal-go.vire" > data/rpc-portal-rpc-fail.vire
compile_listen_guest data/rpc-portal-rpc-fail.vire rpc-rpc-fail
ids="$(run_cmd rpc-rpc-fail ./data/rpc-rpc-fail.elf 0)"
fpid="${ids%% *}"
fport="${ids##* }"
set +e
python3 - "$fport" "$CONTRACT" <<'PY'
import json, socket, sys
from pathlib import Path
port=int(sys.argv[1]); doc=json.loads(Path(sys.argv[2]).read_text())
case=doc["cases"][0]
req=("GET %s HTTP/1.1\r\nHost: 127.0.0.1\r\nConnection: close\r\n\r\n"%case["path"]).encode()
s=socket.create_connection(("127.0.0.1",port),3)
s.sendall(req); s.settimeout(3)
chunks=[]
try:
  while True:
    d=s.recv(4096)
    if not d: break
    chunks.append(d)
except socket.timeout:
  pass
s.close()
raw=b"".join(chunks)
body=raw.split(b"\r\n\r\n",1)[1].decode("utf-8")
print("fail_before_body", body)
if body==case["body"]:
  raise SystemExit("FAIL_BEFORE unexpectedly matched contract")
if '"status"' in body:
  raise SystemExit("FAIL_BEFORE already had status field")
print("FAIL_BEFORE mismatch as required")
PY
fc=$?
set -e
stop_guest "$fpid"
if [[ "$fc" -ne 0 ]]; then
  echo "FAIL_BEFORE harness error $fc"
  exit 1
fi

compile_listen_guest "$ROOT/tests/rebuild/guests/rpc-portal-go.vire" rpc-rpc-good
ids="$(run_cmd rpc-rpc-good ./data/rpc-rpc-good.elf 0)"
gpid="${ids%% *}"
gport="${ids##* }"
ids="$(run_cmd rpc-rpc-host dotnet exec "$VIRE_DLL" data/rpc-rpc-good.vire 0)"
hpid="${ids%% *}"
hport="${ids##* }"

python3 - "$hport" "$gport" "$CONTRACT" <<'PY'
import json, socket, sys
from pathlib import Path

def call(port, path):
    req=("GET %s HTTP/1.1\r\nHost: 127.0.0.1\r\nConnection: close\r\n\r\n"%path).encode()
    s=socket.create_connection(("127.0.0.1",port),3)
    s.sendall(req); s.settimeout(3)
    chunks=[]
    try:
        while True:
            d=s.recv(4096)
            if not d: break
            chunks.append(d)
    except socket.timeout:
        pass
    s.close()
    raw=b"".join(chunks)
    head, body = raw.split(b"\r\n\r\n",1)
    status=int(head.split(b" ")[1])
    return status, body.decode("utf-8")

hport=int(sys.argv[1]); nport=int(sys.argv[2])
doc=json.loads(Path(sys.argv[3]).read_text())
case=doc["cases"][0]
hs,hb=call(hport, case["path"])
ns,nb=call(nport, case["path"])
print("host", hs, hb)
print("native", ns, nb)
want=case["body"]
if hs!=case["status"] or ns!=case["status"]:
    raise SystemExit("status mismatch host %s native %s want %s"%(hs,ns,case["status"]))
if hb!=want or nb!=want:
    raise SystemExit("body mismatch host %r native %r want %r"%(hb,nb,want))
if hb!=nb:
    raise SystemExit("host vs native body mismatch")
print("HOST_NATIVE_MATCH")
print("CONTRACT_MATCH")
PY
stop_guest "$gpid"
stop_guest "$hpid"
echo "PASS_AFTER at $AFTER_SHA rpc-portal /api/rpc {\"enabled\":false,\"status\":503} host vs native"
echo "rebuild rpc portal rpc diff ok"
