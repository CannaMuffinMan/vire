#!/usr/bin/env bash
# Fail-before / pass-after for Go-sidecar unauth GET goldens vs host listen and native ELF.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
export PATH="${HOME}/.dotnet:${PATH:-}"
export DOTNET_ROOT="${DOTNET_ROOT:-$HOME/.dotnet}"
export VIRE_HEADLESS=1
unset VIRE_BUDGET || true

AFTER_SHA="$(git rev-parse HEAD)"
VIRE_DLL="$ROOT/bin/Release/net10.0/vire.dll"
GUEST_DIR="$ROOT/tests/rebuild/guests"
CONTRACT_DIR="$ROOT/tests/rebuild/contracts"

dotnet build vire.csproj -c Release --nologo
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
  cp "$ROOT/src/http-client.vire" "$ROOT/data/http-client.vire"
  cp "$ROOT/src/dist-static.vire" "$ROOT/data/dist-static.vire"
  cp "$ROOT/src/portal-jwt.vire" "$ROOT/data/portal-jwt.vire"
  cp "$ROOT/src/sop-cookie.vire" "$ROOT/data/sop-cookie.vire" 2>/dev/null || true
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

def http_get(path):
    req = f"GET {path} HTTP/1.1\r\nHost: 127.0.0.1\r\nConnection: close\r\n\r\n".encode("ascii")
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

def check_body(case, body):
    if "body_fields" in case:
        try:
            got = json.loads(body)
        except json.JSONDecodeError:
            return "body not json %s" % body
        if not isinstance(got, dict):
            return "body not object %s" % body
        want = case["body_fields"]
        for k, v in want.items():
            if k not in got:
                return "missing field %s" % k
            if got[k] != v:
                return "field %s got %s want %s" % (k, got[k], v)
        return None
    if "body" in case:
        if body != case["body"]:
            return "body got %r want %r" % (body, case["body"])
    return None

for case in doc["cases"]:
    status, headers, body = http_get(case["path"])
    name = case["name"]
    if status != case["status"]:
        mismatches.append("%s status got %s want %s" % (name, status, case["status"]))
    want_h = case.get("headers") or {}
    for hk, hv in want_h.items():
        g = headers.get(hk.lower(), "")
        if g.lower() != hv.lower():
            mismatches.append("%s header %s got %s want %s" % (name, hk, g, hv))
    err = check_body(case, body)
    if err:
        mismatches.append("%s %s" % (name, err))
    print("case %s status %s body %r" % (name, status, body))

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

def http_get(port, path):
    req = f"GET {path} HTTP/1.1\r\nHost: 127.0.0.1\r\nConnection: close\r\n\r\n".encode("ascii")
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
    hs, hh, hb = http_get(host_port, case["path"])
    ns, nh, nb = http_get(native_port, case["path"])
    name = case["name"]
    if hs != ns:
        mismatches.append("%s host status %s native %s" % (name, hs, ns))
    for k in keys:
        hv = hh.get(k, "")
        nv = nh.get(k, "")
        if hv.lower() != nv.lower():
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
  local contract="$4"

  echo "=== slice $id FAIL_BEFORE ==="
  compile_listen_guest "$fail_src" "sidecar-fail-$id"
  ids="$(run_cmd "sidecar-fail-$id" "./data/sidecar-fail-${id}.elf")"
  local fpid="${ids%% *}"
  local fport="${ids##* }"
  echo "fail_before_listen 127.0.0.1:$fport"
  set +e
  diff_contract "$fport" "$contract"
  local fcode=$?
  set -e
  stop_guest "$fpid"
  if [[ "$fcode" -eq 0 ]]; then
    echo "FAIL_BEFORE $id expected mismatch, got match"
    exit 1
  fi
  if [[ "$fcode" -ne 2 ]]; then
    echo "FAIL_BEFORE $id harness error $fcode"
    exit 1
  fi
  echo "FAIL_BEFORE at $AFTER_SHA $id contract mismatch as required"

  echo "=== slice $id PASS_AFTER ==="
  compile_listen_guest "$good_src" "sidecar-good-$id"
  ids="$(run_cmd "sidecar-good-$id" "./data/sidecar-good-${id}.elf")"
  local gpid="${ids%% *}"
  local gport="${ids##* }"
  echo "native_listen 127.0.0.1:$gport"
  ids="$(run_cmd "sidecar-host-$id" dotnet exec "$VIRE_DLL" "data/sidecar-good-${id}.vire")"
  local hpid="${ids%% *}"
  local hport="${ids##* }"
  echo "host_listen 127.0.0.1:$hport"
  diff_contract "$gport" "$contract"
  echo "native contract ok $id"
  diff_contract "$hport" "$contract"
  echo "host contract ok $id"
  pair_host_native "$hport" "$gport" "$contract"
  stop_guest "$gpid"
  stop_guest "$hpid"
  echo "PASS_AFTER at $AFTER_SHA $id host vs native match"
}

echo "pass_after_sha $AFTER_SHA"
run_slice fcgbds "$GUEST_DIR/fcgbds-fail.vire" "$GUEST_DIR/fcgbds-health.vire" "$CONTRACT_DIR/fcgbds-health.json"
run_slice fcgbc "$GUEST_DIR/fcgbc-fail.vire" "$GUEST_DIR/fcgbc-pending.vire" "$CONTRACT_DIR/fcgbc-pending.json"
run_slice cpa "$GUEST_DIR/cpa-fail.vire" "$GUEST_DIR/cpa-health.vire" "$CONTRACT_DIR/cpa-health.json"
run_slice rpc "$GUEST_DIR/rpc-fail.vire" "$GUEST_DIR/rpc-health.vire" "$CONTRACT_DIR/rpc-health.json"
run_slice apigo "$GUEST_DIR/api-fail.vire" "$GUEST_DIR/api-healthz.vire" "$CONTRACT_DIR/api-healthz.json"
echo "rebuild sidecar diff ok"
# Unauth sidecar routes beyond rank-3 health goldens (service-scoped guests).
bash "$ROOT/tools/rebuild-unauth-sidecar-diff.sh"
