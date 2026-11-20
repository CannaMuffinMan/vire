#!/usr/bin/env bash
# Differential harness: recorded FCG unauth JSON contracts vs host listen and native ELF.
# FAIL_BEFORE compiles tests/rebuild/fail-before-health.vire and requires mismatch.
# PASS_AFTER compiles guest-health.vire, runs host + native, requires contract match
# and host vs native equality (status, named headers, body).
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
export PATH="${HOME}/.dotnet:${PATH:-}"
export DOTNET_ROOT="${DOTNET_ROOT:-$HOME/.dotnet}"
export VIRE_HEADLESS=1
unset VIRE_BUDGET || true

AFTER_SHA="$(git rev-parse HEAD)"
CONTRACT_DIR="$ROOT/tests/rebuild/contracts"
FAIL_SRC="$ROOT/tests/rebuild/fail-before-health.vire"
GOOD_SRC="$ROOT/guest-health.vire"
VIRE_DLL="$ROOT/bin/Release/net10.0/vire.dll"

shopt -s nullglob
CONTRACTS=( "$CONTRACT_DIR"/fcg-health.json "$CONTRACT_DIR"/fcg-info.json "$CONTRACT_DIR"/fcg-connect.json )
for c in "${CONTRACTS[@]}"; do
  if [[ ! -f "$c" ]]; then
    echo "missing contract $c"
    exit 1
  fi
done

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
  python3 - "$port" "${CONTRACTS[@]}" <<'PY'
import json, socket, sys
from pathlib import Path

port = int(sys.argv[1])
cases = []
for p in sys.argv[2:]:
    doc = json.loads(Path(p).read_text())
    for c in doc["cases"]:
        c["_file"] = Path(p).name
        cases.append(c)
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
    body = raw[split + 4 :]
    lines = head.split("\r\n")
    status_line = lines[0]
    parts = status_line.split(" ")
    status = int(parts[1]) if len(parts) > 1 else 0
    headers = {}
    for line in lines[1:]:
        if ":" not in line:
            continue
        k, v = line.split(":", 1)
        headers[k.strip().lower()] = v.strip()
    return status, headers, body.decode("utf-8")

got = {}
for case in cases:
    status, headers, body = http_get(case["path"])
    name = case["name"]
    got[name] = (status, headers, body)
    if status != case["status"]:
        mismatches.append("%s status got %s want %s" % (name, status, case["status"]))
    want_h = case.get("headers") or {}
    for hk, hv in want_h.items():
        got = headers.get(hk.lower(), "")
        if got.lower() != hv.lower():
            mismatches.append("%s header %s got %s want %s" % (name, hk, got, hv))
    if body != case["body"]:
        mismatches.append("%s body got %s want %s" % (name, body, case["body"]))
    print("case %s status %s body %s" % (name, status, body))

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
  python3 - "$host_port" "$native_port" "${CONTRACTS[@]}" <<'PY'
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
keys = ["content-type", "connection", "x-content-type-options", "cache-control"]
mismatches = []
for p in sys.argv[3:]:
    doc = json.loads(Path(p).read_text())
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
            mismatches.append("%s body host %s native %s" % (name, hb, nb))
        print("pair %s host %s native %s" % (name, hs, ns))
if mismatches:
    print("HOST_NATIVE_MISMATCH")
    for m in mismatches:
        print(m)
    sys.exit(3)
print("HOST_NATIVE_MATCH")
PY
}

echo "pass_after_sha $AFTER_SHA"

echo "FAIL_BEFORE compile mismatch guest"
compile_listen_guest "$FAIL_SRC" "rebuild-fail"
ids="$(run_cmd rebuild-fail "./data/rebuild-fail.elf")"
FPID="${ids%% *}"
FPORT="${ids##* }"
echo "fail_before_listen 127.0.0.1:$FPORT"
set +e
diff_contracts "$FPORT"
FCODE=$?
set -e
stop_guest "$FPID"
if [[ "$FCODE" -eq 0 ]]; then
  echo "FAIL_BEFORE expected contract mismatch, got match"
  exit 1
fi
if [[ "$FCODE" -ne 2 ]]; then
  echo "FAIL_BEFORE harness error $FCODE"
  exit 1
fi
echo "FAIL_BEFORE at $AFTER_SHA contract mismatch as required"

echo "PASS_AFTER compile guest-health.vire"
compile_listen_guest "$GOOD_SRC" "rebuild-health"
ids="$(run_cmd rebuild-health "./data/rebuild-health.elf")"
GPID="${ids%% *}"
GPORT="${ids##* }"
echo "native_listen 127.0.0.1:$GPORT"

echo "PASS_AFTER host listen guest-health.vire"
ids="$(run_cmd rebuild-host dotnet exec "$VIRE_DLL" "data/rebuild-health.vire")"
HPID="${ids%% *}"
HPORT="${ids##* }"
echo "host_listen 127.0.0.1:$HPORT"

diff_contracts "$GPORT"
echo "native contract ok"
diff_contracts "$HPORT"
echo "host contract ok"
pair_host_native "$HPORT" "$GPORT"
stop_guest "$GPID"
stop_guest "$HPID"
echo "PASS_AFTER at $AFTER_SHA native ELF matches host listen and recorded FCG health/info/connect contracts"
echo "rebuild health diff ok"
