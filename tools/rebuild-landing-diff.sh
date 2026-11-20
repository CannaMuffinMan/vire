#!/usr/bin/env bash
# Fail-before / pass-after for landing-go unauth fixtures vs host listen and native ELF.
# FAIL_BEFORE: landing-fail.vire (routes absent), matching a58999b1 where this guest
# did not exist. PASS_AFTER: tests/rebuild/guests/landing-go.vire.
# Linux ELF only. Windows PE steps are tools/rebuild-fcgcpa-windows.ps1 (CouchStation).
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
export PATH="${HOME}/.dotnet:${PATH:-}"
export DOTNET_ROOT="${DOTNET_ROOT:-$HOME/.dotnet}"
export VIRE_HEADLESS=1
unset VIRE_BUDGET || true
unset FCG_API_TOKEN || true

AFTER_SHA="$(git rev-parse HEAD)"
BEFORE_SHA="a58999b15dc8fc1b2b1fe196dd7a88aa89179630"
VIRE_DLL="$ROOT/bin/Release/net10.0/vire.dll"
GUEST_DIR="$ROOT/tests/rebuild/guests"
CONTRACT_DIR="$ROOT/tests/rebuild/contracts/landing-go"

dotnet build vire.csproj -c Release --nologo
bash "$ROOT/tools/stage-compiler-src.sh"
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

def http_get(path):
    req = f"GET {path} HTTP/1.1\r\nHost: 127.0.0.1\r\nConnection: close\r\n\r\n".encode("ascii")
    s = socket.create_connection(("127.0.0.1", port), 3)
    s.sendall(req)
    s.settimeout(3)
    chunks = []
    try:
        while True:
            data = s.recv(8192)
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
    status, headers, body = http_get(case["path"])
    name = case["name"]
    if status != case["status"]:
        mismatches.append("%s status got %s want %s" % (name, status, case["status"]))
    want_h = case.get("headers") or {}
    for hk, hv in want_h.items():
        g = headers.get(hk.lower(), "")
        if g != hv:
            mismatches.append("%s header %s got %r want %r" % (name, hk, g, hv))
    if "body" in case and body != case["body"]:
        mismatches.append("%s body got %r want %r" % (name, body, case["body"]))
    print("case %s status %s ctype %s" % (name, status, headers.get("content-type", "")))

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
            data = s.recv(8192)
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
    return status, headers, body, raw[split + 4 :]

host_port = int(sys.argv[1])
native_port = int(sys.argv[2])
doc = json.loads(Path(sys.argv[3]).read_text())
keys = ["content-type", "connection", "x-content-type-options", "cache-control",
        "location", "www-authenticate", "x-payments-enabled"]
mismatches = []
for case in doc["cases"]:
    hs, hh, hb, hraw = http_get(host_port, case["path"])
    ns, nh, nb, nraw = http_get(native_port, case["path"])
    name = case["name"]
    if hs != ns:
        mismatches.append("%s host status %s native %s" % (name, hs, ns))
    for k in keys:
        hv = hh.get(k, "")
        nv = nh.get(k, "")
        if hv != nv:
            mismatches.append("%s header %s host %r native %r" % (name, k, hv, nv))
    if hraw != nraw:
        mismatches.append("%s body bytes host %s native %s" % (name, hraw, nraw))
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
echo "fail_before_base $BEFORE_SHA"

echo "=== landing-go FAIL_BEFORE (routes absent, as at $BEFORE_SHA) ==="
compile_listen_guest "$GUEST_DIR/landing-fail.vire" "landing-fail"
ids="$(run_cmd "landing-fail" "./data/landing-fail.elf")"
fpid="${ids%% *}"
fport="${ids##* }"
echo "fail_before_listen 127.0.0.1:$fport"
set +e
diff_contract "$fport" "$CONTRACT_DIR/healthz.json"
fcode=$?
set -e
stop_guest "$fpid"
if [[ "$fcode" -eq 0 ]]; then
  echo "FAIL_BEFORE expected mismatch, got match"
  exit 1
fi
if [[ "$fcode" -ne 2 ]]; then
  echo "FAIL_BEFORE harness error $fcode"
  exit 1
fi
echo "FAIL_BEFORE at $BEFORE_SHA landing-go contract mismatch as required"

echo "=== landing-go PASS_AFTER ==="
compile_listen_guest "$GUEST_DIR/landing-go.vire" "landing-good"
ids="$(run_cmd "landing-good" "./data/landing-good.elf")"
gpid="${ids%% *}"
gport="${ids##* }"
echo "native_listen 127.0.0.1:$gport"
ids="$(run_cmd "landing-host" dotnet exec "$VIRE_DLL" "data/landing-good.vire")"
hpid="${ids%% *}"
hport="${ids##* }"
echo "host_listen 127.0.0.1:$hport"
for c in healthz api redirects held pages; do
  echo "--- contract $c native ---"
  diff_contract "$gport" "$CONTRACT_DIR/$c.json"
  echo "--- contract $c host ---"
  diff_contract "$hport" "$CONTRACT_DIR/$c.json"
  pair_host_native "$hport" "$gport" "$CONTRACT_DIR/$c.json"
done
stop_guest "$gpid"
stop_guest "$hpid"
echo "PASS_AFTER at $AFTER_SHA landing-go host vs native match"
echo "rebuild landing diff ok"
