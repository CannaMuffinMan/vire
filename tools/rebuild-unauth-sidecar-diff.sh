#!/usr/bin/env bash
# Fail-before / pass-after for unauth Go sidecar routes (rpc-portal-go,
# edge-go, dev-portal-go, fcgbds-dashboard-go) vs host listen and native ELF.
# Does not dial production, Railway, Stripe, or databases. Loopback only.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
export PATH="${HOME}/.dotnet:${PATH:-}"
export DOTNET_ROOT="${DOTNET_ROOT:-$HOME/.dotnet}"
export VIRE_HEADLESS=1
unset VIRE_BUDGET || true
unset FCG_API_TOKEN || true

AFTER_SHA="$(git rev-parse HEAD)"
BASE_SHA="a58999b15dc8fc1b2b1fe196dd7a88aa89179630"
VIRE_DLL="$ROOT/bin/Release/net10.0/vire.dll"
GUEST_DIR="$ROOT/tests/rebuild/guests"
CONTRACT_ROOT="$ROOT/tests/rebuild/contracts"

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

diff_contract() {
  local port="$1"
  local contract="$2"
  python3 - "$port" "$contract" <<'PY'
import json, socket, sys
from pathlib import Path

port = int(sys.argv[1])
doc = json.loads(Path(sys.argv[2]).read_text())
mismatches = []

def http_call(method, path, request_body):
    payload = b"" if request_body is None else request_body.encode("utf-8")
    lines = [
        "%s %s HTTP/1.1" % (method, path),
        "Host: 127.0.0.1",
    ]
    if method in ("POST", "PUT"):
        lines.append("Content-Type: application/json")
        lines.append("Content-Length: %s" % len(payload))
    lines.append("Connection: close")
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

for case in doc["cases"]:
    method = case.get("method", "GET")
    req_body = case["request_body"] if "request_body" in case else None
    status, headers, body = http_call(method, case["path"], req_body)
    name = case["name"]
    if status != case["status"]:
        mismatches.append("%s status got %s want %s" % (name, status, case["status"]))
    want_h = case.get("headers") or {}
    for hk, hv in want_h.items():
        g = headers.get(hk.lower(), "")
        if hk.lower() == "content-type":
            if hv.lower() not in g.lower():
                mismatches.append("%s content-type got %s want contains %s" % (name, g, hv))
            if hv.lower() == "application/json" and "charset" in g.lower():
                mismatches.append("%s content-type has charset: %s" % (name, g))
        elif g.lower() != hv.lower():
            mismatches.append("%s header %s got %s want %s" % (name, hk, g, hv))
    if "body" in case and body != case["body"]:
        mismatches.append("%s body got %r want %r" % (name, body, case["body"]))
    print("case %s status %s ctype %s body %r" % (name, status, headers.get("content-type", ""), body))

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
  local contract="$3"
  python3 - "$host_port" "$native_port" "$contract" <<'PY'
import json, socket, sys
from pathlib import Path

def http_call(port, method, path, request_body):
    payload = b"" if request_body is None else request_body.encode("utf-8")
    lines = [
        "%s %s HTTP/1.1" % (method, path),
        "Host: 127.0.0.1",
    ]
    if method in ("POST", "PUT"):
        lines.append("Content-Type: application/json")
        lines.append("Content-Length: %s" % len(payload))
    lines.append("Connection: close")
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
keys = ["content-type", "connection", "x-content-type-options", "cache-control"]
mismatches = []
for case in doc["cases"]:
    method = case.get("method", "GET")
    req_body = case["request_body"] if "request_body" in case else None
    hs, hh, hb = http_call(host_port, method, case["path"], req_body)
    ns, nh, nb = http_call(native_port, method, case["path"], req_body)
    name = case["name"]
    if hs != ns:
        mismatches.append("%s host status %s native %s" % (name, hs, ns))
    for k in keys:
        hv = hh.get(k, "")
        nv = nh.get(k, "")
        if k == "content-type":
            def kind(v):
                v = v.lower()
                if "text/plain" in v:
                    return "plain"
                if "application/json" in v:
                    return "json"
                return v
            if kind(hv) != kind(nv):
                mismatches.append("%s content-type host %s native %s" % (name, hv, nv))
            if "application/json" in hv.lower() and "charset" in hv.lower():
                mismatches.append("%s host content-type has charset %s" % (name, hv))
            if "application/json" in nv.lower() and "charset" in nv.lower():
                mismatches.append("%s native content-type has charset %s" % (name, nv))
        elif hv.lower() != nv.lower():
            mismatches.append("%s header %s host %s native %s" % (name, k, hv, nv))
    if hb != nb:
        mismatches.append("%s body host %r native %r" % (name, hb, nb))
    print("pair %s host %s native %s" % (name, hs, ns))
if mismatches:
    print("HOST_NATIVE_MISMATCH")
    for m in mismatches:
        print(m)
    sys.exit(3)
print("HOST_NATIVE_MATCH")
PY
}

run_slice() {
  local id="$1"
  local fail_src="$2"
  local good_src="$3"
  shift 3
  local contracts=("$@")

  echo "=== slice $id FAIL_BEFORE (base $BASE_SHA) ==="
  compile_listen_guest "$fail_src" "unauth-fail-$id"
  ids="$(run_cmd "unauth-fail-$id" "./data/unauth-fail-${id}.elf")"
  local fpid="${ids%% *}"
  local fport="${ids##* }"
  echo "fail_before_listen 127.0.0.1:$fport"
  local any_mismatch=0
  local contract
  for contract in "${contracts[@]}"; do
    set +e
    diff_contract "$fport" "$contract"
    local fcode=$?
    set -e
    if [[ "$fcode" -eq 0 ]]; then
      echo "FAIL_BEFORE $id $contract expected mismatch, got match"
      stop_guest "$fpid"
      exit 1
    fi
    if [[ "$fcode" -ne 2 ]]; then
      echo "FAIL_BEFORE $id $contract harness error $fcode"
      stop_guest "$fpid"
      exit 1
    fi
    any_mismatch=1
  done
  stop_guest "$fpid"
  echo "FAIL_BEFORE at $BASE_SHA vs $AFTER_SHA $id contract mismatch as required"

  echo "=== slice $id PASS_AFTER ==="
  compile_listen_guest "$good_src" "unauth-good-$id"
  ids="$(run_cmd "unauth-good-$id" "./data/unauth-good-${id}.elf")"
  local gpid="${ids%% *}"
  local gport="${ids##* }"
  echo "native_listen 127.0.0.1:$gport"
  ids="$(run_cmd "unauth-host-$id" dotnet exec "$VIRE_DLL" "data/unauth-good-${id}.vire")"
  local hpid="${ids%% *}"
  local hport="${ids##* }"
  echo "host_listen 127.0.0.1:$hport"
  for contract in "${contracts[@]}"; do
    diff_contract "$gport" "$contract"
    echo "native contract ok $contract"
    diff_contract "$hport" "$contract"
    echo "host contract ok $contract"
    pair_host_native "$hport" "$gport" "$contract"
  done
  stop_guest "$gpid"
  stop_guest "$hpid"
  echo "PASS_AFTER at $AFTER_SHA $id host vs native match"
}

echo "pass_after_sha $AFTER_SHA fail_before_base $BASE_SHA"

rpc_contracts=(
  "$CONTRACT_ROOT/rpc-portal-go/api-health.json"
  "$CONTRACT_ROOT/rpc-portal-go/api-capabilities.json"
  "$CONTRACT_ROOT/rpc-portal-go/api-rpc.json"
  "$CONTRACT_ROOT/rpc-portal-go/api-transfer.json"
  "$CONTRACT_ROOT/rpc-portal-go/dist-missing.json"
  "$CONTRACT_ROOT/rpc-portal-go/not-found.json"
)
run_slice rpcportal "$GUEST_DIR/rpc-portal-go-fail.vire" "$GUEST_DIR/rpc-portal-go.vire" "${rpc_contracts[@]}"

edge_contracts=(
  "$CONTRACT_ROOT/edge-go/healthz.json"
  "$CONTRACT_ROOT/edge-go/not-found.json"
)
run_slice edge "$GUEST_DIR/edge-go-fail.vire" "$GUEST_DIR/edge-go.vire" "${edge_contracts[@]}"

maint_contracts=(
  "$CONTRACT_ROOT/edge-go/maintenance.json"
)
run_slice edgemaint "$GUEST_DIR/edge-go-fail.vire" "$GUEST_DIR/edge-go-maintenance.vire" "${maint_contracts[@]}"

dev_contracts=(
  "$CONTRACT_ROOT/dev-portal-go/dist-missing.json"
)
run_slice devportal "$GUEST_DIR/dev-portal-go-fail.vire" "$GUEST_DIR/dev-portal-go.vire" "${dev_contracts[@]}"

dash_contracts=(
  "$CONTRACT_ROOT/fcgbds-dashboard-go/api-health.json"
  "$CONTRACT_ROOT/fcgbds-dashboard-go/api-challenge.json"
  "$CONTRACT_ROOT/fcgbds-dashboard-go/api-challenge-verify.json"
  "$CONTRACT_ROOT/fcgbds-dashboard-go/api-events-detailed.json"
  "$CONTRACT_ROOT/fcgbds-dashboard-go/api-stats.json"
  "$CONTRACT_ROOT/fcgbds-dashboard-go/api-stats-detailed.json"
  "$CONTRACT_ROOT/fcgbds-dashboard-go/api-reviewers-heartbeat.json"
  "$CONTRACT_ROOT/fcgbds-dashboard-go/api-stream-wall-status.json"
  "$CONTRACT_ROOT/fcgbds-dashboard-go/dist-missing.json"
  "$CONTRACT_ROOT/fcgbds-dashboard-go/not-found.json"
)
run_slice dash "$GUEST_DIR/fcgbds-dashboard-go-fail.vire" "$GUEST_DIR/fcgbds-dashboard-go.vire" "${dash_contracts[@]}"

echo "rebuild unauth sidecar diff ok"
