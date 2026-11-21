#!/usr/bin/env bash
# Differential harness: recorded FCG GET /chain + POST /block vs host listen and native ELF.
# FAIL_BEFORE compiles tests/rebuild/fail-before-chain.vire and requires mismatch.
# PASS_AFTER compiles guest-chain.vire. Fixtures from data/rebuild/chain (not prod).
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
export PATH="${HOME}/.dotnet:${PATH:-}"
export DOTNET_ROOT="${DOTNET_ROOT:-$HOME/.dotnet}"
export VIRE_HEADLESS=1
unset VIRE_BUDGET || true

AFTER_SHA="$(git rev-parse HEAD)"
BASE_SHA="$(git rev-parse df58afd1d401c67bf8b086f447399162b3cc8b78 2>/dev/null || git rev-parse HEAD^ 2>/dev/null || git rev-parse HEAD)"
CONTRACT="$ROOT/tests/rebuild/contracts/fcg-chain.json"
FAIL_SRC="$ROOT/tests/rebuild/fail-before-chain.vire"
FAIL_REMAINDER_SRC="$ROOT/tests/rebuild/fail-before-chain-remainder.vire"
GOOD_SRC="$ROOT/guest-chain.vire"
REMAINDER_PY="$ROOT/tools/rebuild-chain-remainder.py"
VIRE_DLL="$ROOT/bin/Release/net10.0/vire.dll"
FIX_SRC="$ROOT/data/rebuild/chain"
FIX_DST="$ROOT/data/chain"

if [[ ! -f "$CONTRACT" || ! -f "$FIX_SRC/head.json" || ! -f "$FIX_SRC/000001.json" ]]; then
  echo "missing chain contract or fixtures"
  exit 1
fi

dotnet build vire.csproj -c Release --nologo
mkdir -p data

install_fixtures() {
  rm -rf "$FIX_DST"
  mkdir -p "$FIX_DST"
  cp "$FIX_SRC/head.json" "$FIX_DST/head.json"
  cp "$FIX_SRC/000001.json" "$FIX_DST/000001.json"
  cp "$FIX_SRC/blocks.json" "$FIX_DST/blocks.json"
  rm -f "$ROOT/data/chain.json"
}

hex_to_bin() {
  python3 - "$1" "$2" <<'PY'
import pathlib, sys
pathlib.Path(sys.argv[2]).write_bytes(bytes.fromhex(pathlib.Path(sys.argv[1]).read_text().strip()))
PY
}

compile_listen_guest() {
  local src="$1"
  local stem="$2"
  # Host file root is the program folder. Keep the patched source at repo root
  # so data/chain/... resolves the same as native ELF (cwd = repo root).
  python3 - "$src" "$ROOT/rebuild-chain-run.vire" "data/${stem}.vire" <<'PY'
from pathlib import Path
import sys
text = Path(sys.argv[1]).read_text()
text = text.replace("listen with 18080", "listen with 0")
Path(sys.argv[2]).write_text(text)
Path(sys.argv[3]).write_text(text)
PY
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

diff_contracts() {
  local port="$1"
  local only="${2:-}"
  python3 - "$port" "$CONTRACT" "$FIX_SRC" "$FIX_DST" "$only" <<'PY'
import json, shutil, socket, sys
from pathlib import Path

port = int(sys.argv[1])
doc = json.loads(Path(sys.argv[2]).read_text())
fix_src = Path(sys.argv[3])
fix_dst = Path(sys.argv[4])
only = sys.argv[5] if len(sys.argv) > 5 else ""
mismatches = []

def restore():
    fix_dst.mkdir(parents=True, exist_ok=True)
    shutil.copyfile(fix_src / "head.json", fix_dst / "head.json")
    shutil.copyfile(fix_src / "000001.json", fix_dst / "000001.json")
    shutil.copyfile(fix_src / "blocks.json", fix_dst / "blocks.json")

def http_req(method, path, body_send):
    payload = body_send.encode("utf-8") if body_send is not None else b""
    lines = [
        "%s %s HTTP/1.1" % (method, path),
        "Host: 127.0.0.1",
    ]
    lines.append("Connection: close")
    if method == "POST":
        lines.append("Content-Type: application/json")
        lines.append("Content-Length: %d" % len(payload))
    req = ("\r\n".join(lines) + "\r\n\r\n").encode("ascii") + payload
    s = socket.create_connection(("127.0.0.1", port), 3)
    s.sendall(req)
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
    raw = b"".join(chunks)
    split = raw.find(b"\r\n\r\n")
    if split < 0:
        raise SystemExit("missing header terminator")
    head = raw[:split].decode("ascii", "replace")
    body = raw[split + 4 :].decode("utf-8")
    lines = head.split("\r\n")
    status = int(lines[0].split(" ")[1])
    headers = {}
    for line in lines[1:]:
        if ":" not in line:
            continue
        k, v = line.split(":", 1)
        headers[k.strip().lower()] = v.strip()
    return status, headers, body

restore()
for case in doc["cases"]:
    if only == "GET" and (case.get("method") or "GET") != "GET":
        continue
    if case.get("restore_chain"):
        restore()
    method = case.get("method") or "GET"
    send = case.get("body_send")
    status, headers, body = http_req(method, case["path"], send)
    name = case["name"]
    if status != case["status"]:
        mismatches.append("%s status got %s want %s" % (name, status, case["status"]))
    want_h = case.get("headers") or {}
    for hk, hv in want_h.items():
        g = headers.get(hk.lower(), "")
        if g.lower() != hv.lower():
            mismatches.append("%s header %s got %s want %s" % (name, hk, g, hv))
    if body != case["body"]:
        mismatches.append("%s body got %s want %s" % (name, body, case["body"]))
    print("case %s status %s body %s" % (name, status, body))
    print("--- golden %s ---" % name)
    print("want status %s" % case["status"])
    print("got  status %s" % status)
    print("want body %s" % case["body"])
    print("got  body %s" % body)

if mismatches:
    print("CONTRACT_MISMATCH")
    for m in mismatches:
        print(m)
    sys.exit(2)
print("CONTRACT_MATCH")
PY
}

pair_host_native() {
  local host_port="$1"
  local native_port="$2"
  python3 - "$host_port" "$native_port" "$CONTRACT" "$FIX_SRC" "$FIX_DST" <<'PY'
import json, shutil, socket, sys
from pathlib import Path

def restore(fix_src, fix_dst):
    fix_dst.mkdir(parents=True, exist_ok=True)
    shutil.copyfile(fix_src / "head.json", fix_dst / "head.json")
    shutil.copyfile(fix_src / "000001.json", fix_dst / "000001.json")
    shutil.copyfile(fix_src / "blocks.json", fix_dst / "blocks.json")

def http_req(port, method, path, body_send):
    payload = body_send.encode("utf-8") if body_send is not None else b""
    lines = [
        "%s %s HTTP/1.1" % (method, path),
        "Host: 127.0.0.1",
    ]
    lines.append("Connection: close")
    if method == "POST":
        lines.append("Content-Type: application/json")
        lines.append("Content-Length: %d" % len(payload))
    req = ("\r\n".join(lines) + "\r\n\r\n").encode("ascii") + payload
    s = socket.create_connection(("127.0.0.1", port), 3)
    s.sendall(req)
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
    raw = b"".join(chunks)
    split = raw.find(b"\r\n\r\n")
    if split < 0:
        raise SystemExit("missing header terminator")
    head = raw[:split].decode("ascii", "replace")
    body = raw[split + 4 :].decode("utf-8")
    lines = head.split("\r\n")
    status = int(lines[0].split(" ")[1])
    headers = {}
    for line in lines[1:]:
        if ":" not in line:
            continue
        k, v = line.split(":", 1)
        headers[k.strip().lower()] = v.strip()
    return status, headers, body

host_port = int(sys.argv[1])
native_port = int(sys.argv[2])
doc = json.loads(Path(sys.argv[3]).read_text())
fix_src = Path(sys.argv[4])
fix_dst = Path(sys.argv[5])
keys = ["content-type", "connection", "x-content-type-options", "cache-control"]
mismatches = []

read_cases = [c for c in doc["cases"] if not c.get("restore_chain") and (c.get("method") or "GET") == "GET"]
write_cases = [c for c in doc["cases"] if (c.get("method") or "GET") == "POST"]

restore(fix_src, fix_dst)
for case in read_cases:
    method = case.get("method") or "GET"
    send = case.get("body_send")
    hs, hh, hb = http_req(host_port, method, case["path"], send)
    ns, nh, nb = http_req(native_port, method, case["path"], send)
    name = case["name"]
    if hs != ns:
        mismatches.append("%s host status %s native %s" % (name, hs, ns))
    for k in keys:
        hv = hh.get(k, "")
        nv = nh.get(k, "")
        if hv.lower() != nv.lower():
            mismatches.append("%s header %s host %s native %s" % (name, k, hv, nv))
    if hb != nb:
        mismatches.append("%s body host %s native %s" % (name, hb, nb))
    print("pair %s host %s native %s" % (name, hs, ns))

for case in write_cases:
    name = case["name"]
    method = case.get("method") or "GET"
    send = case.get("body_send")
    restore(fix_src, fix_dst)
    hs, hh, hb = http_req(host_port, method, case["path"], send)
    restore(fix_src, fix_dst)
    ns, nh, nb = http_req(native_port, method, case["path"], send)
    if hs != ns:
        mismatches.append("%s host status %s native %s" % (name, hs, ns))
    if hb != nb:
        mismatches.append("%s body host %s native %s" % (name, hb, nb))
    print("pair %s host %s native %s" % (name, hs, ns))
    print("pair proof host %s" % hb)
    print("pair proof native %s" % nb)

if mismatches:
    print("HOST_NATIVE_MISMATCH")
    for m in mismatches:
        print(m)
    sys.exit(3)
print("HOST_NATIVE_MATCH")
PY
}

echo "stack_base_sha $BASE_SHA"
echo "pass_after_sha $AFTER_SHA"
install_fixtures

echo "FAIL_BEFORE compile mismatch guest"
compile_listen_guest "$FAIL_SRC" "rebuild-chain-fail"
ids="$(run_cmd rebuild-chain-fail "./data/rebuild-chain-fail.elf")"
FPID="${ids%% *}"
FPORT="${ids##* }"
echo "fail_before_listen 127.0.0.1:$FPORT"
set +e
diff_contracts "$FPORT"
FCODE=$?
set -e
stop_guest "$FPID"
install_fixtures
if [[ "$FCODE" -eq 0 ]]; then
  echo "FAIL_BEFORE expected contract mismatch, got match"
  exit 1
fi
if [[ "$FCODE" -ne 2 ]]; then
  echo "FAIL_BEFORE harness error $FCODE"
  exit 1
fi
echo "FAIL_BEFORE at $BASE_SHA contract mismatch as required"

echo "FAIL_BEFORE remainder vs snapshot guest (no rotate/507/tamper/migrate)"
compile_listen_guest "$FAIL_REMAINDER_SRC" "rebuild-chain-fail-rem"
ids="$(run_cmd rebuild-chain-fail-rem "./data/rebuild-chain-fail-rem.elf")"
RPID="${ids%% *}"
RPORT="${ids##* }"
echo "fail_before_remainder_listen 127.0.0.1:$RPORT"
set +e
python3 "$REMAINDER_PY" run "$RPORT" "$FIX_SRC" "$FIX_DST" fail-before
RCODE=$?
set -e
stop_guest "$RPID"
install_fixtures
if [[ "$RCODE" -eq 0 ]]; then
  echo "FAIL_BEFORE remainder expected mismatch, got match"
  exit 1
fi
if [[ "$RCODE" -ne 2 ]]; then
  echo "FAIL_BEFORE remainder harness error $RCODE"
  exit 1
fi
echo "FAIL_BEFORE remainder at $BASE_SHA mismatch as required"

echo "PASS_AFTER compile guest-chain.vire"
compile_listen_guest "$GOOD_SRC" "rebuild-chain"
ids="$(run_cmd rebuild-chain "./data/rebuild-chain.elf")"
GPID="${ids%% *}"
GPORT="${ids##* }"
echo "native_listen 127.0.0.1:$GPORT"

echo "PASS_AFTER host listen guest-chain.vire"
ids="$(run_cmd rebuild-chain-host dotnet exec "$VIRE_DLL" "$ROOT/rebuild-chain-run.vire")"
HPID="${ids%% *}"
HPORT="${ids##* }"
echo "host_listen 127.0.0.1:$HPORT"

install_fixtures
diff_contracts "$GPORT"
echo "native GET /chain and POST /block contract ok"
install_fixtures
diff_contracts "$HPORT"
echo "host contract ok"
pair_host_native "$HPORT" "$GPORT"
install_fixtures
python3 "$REMAINDER_PY" run "$GPORT" "$FIX_SRC" "$FIX_DST" pass-after
echo "native remainder contract ok"
install_fixtures
python3 "$REMAINDER_PY" run "$HPORT" "$FIX_SRC" "$FIX_DST" pass-after
echo "host remainder contract ok"
stop_guest "$GPID"
stop_guest "$HPID"
install_fixtures
ids="$(run_cmd rebuild-chain "./data/rebuild-chain.elf")"
GPID="${ids%% *}"
GPORT="${ids##* }"
ids="$(run_cmd rebuild-chain-host dotnet exec "$VIRE_DLL" "$ROOT/rebuild-chain-run.vire")"
HPID="${ids%% *}"
HPORT="${ids##* }"
echo "pair_remainder native 127.0.0.1:$GPORT host 127.0.0.1:$HPORT"
python3 "$REMAINDER_PY" pair "$HPORT" "$GPORT" "$FIX_SRC" "$FIX_DST"
stop_guest "$GPID"
stop_guest "$HPID"
install_fixtures
echo "PASS_AFTER at $AFTER_SHA native ELF matches host GET /chain and POST /block vs recorded contract including rotate/507/tamper/migrate/previousHash/concurrent"
echo "rebuild chain diff ok"
