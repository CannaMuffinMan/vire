#!/usr/bin/env bash
# Differential harness: fcgbds-go unauth HTTP + worker-go env cases.
# FAIL_BEFORE uses tests/rebuild/fail-before-*.vire and requires mismatch.
# PASS_AFTER compiles guest-fcgbds.vire and guest-worker.vire (host + native ELF).
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
export PATH="${HOME}/.dotnet:${PATH:-}"
export DOTNET_ROOT="${DOTNET_ROOT:-$HOME/.dotnet}"
export VIRE_HEADLESS=1
unset VIRE_BUDGET || true

AFTER_SHA="$(git rev-parse HEAD)"
BEFORE_SHA="$(git rev-parse HEAD^ 2>/dev/null || git rev-parse HEAD)"
if git merge-base --is-ancestor 4da22c2cce8bb09fe057c219c57764eec94706dc HEAD 2>/dev/null; then
  BEFORE_SHA="4da22c2cce8bb09fe057c219c57764eec94706dc"
fi
CONTRACT_HTTP="$ROOT/tests/rebuild/contracts/fcgbds-go.json"
CONTRACT_WORKER="$ROOT/tests/rebuild/contracts/worker-go.json"
FAIL_HTTP="$ROOT/tests/rebuild/fail-before-fcgbds.vire"
FAIL_WORKER="$ROOT/tests/rebuild/fail-before-worker.vire"
GOOD_HTTP="$ROOT/guest-fcgbds.vire"
GOOD_WORKER="$ROOT/guest-worker.vire"
VIRE_DLL="$ROOT/bin/Release/net10.0/vire.dll"

[[ -f "$CONTRACT_HTTP" && -f "$CONTRACT_WORKER" ]] || { echo "missing contracts"; exit 1; }

dotnet build vire.csproj -c Release --nologo
mkdir -p data

hex_to_bin() {
  python3 - "$1" "$2" <<'PY'
import pathlib, sys
pathlib.Path(sys.argv[2]).write_bytes(bytes.fromhex(pathlib.Path(sys.argv[1]).read_text().strip()))
PY
}

compile_guest() {
  local src="$1"
  local stem="$2"
  local listen0="${3:-0}"
  python3 - "$src" "data/${stem}.vire" "$listen0" <<'PY'
from pathlib import Path
import sys
text = Path(sys.argv[1]).read_text()
if sys.argv[3] == "1":
    text = text.replace("listen with 18080", "listen with 0")
    # guest-fcgbds already listen with port from args; force 0 when no argv
    if "listen with port" in text:
        text = text.replace("listen with port", "listen with 0")
        # keep reserved-port checks: they run before listen, using args
Path(sys.argv[2]).write_text(text)
PY
  rm -f "data/${stem}.hex" "data/${stem}.elf"
  dotnet exec "$VIRE_DLL" --compiler compile-native.vire "data/${stem}.vire" "data/${stem}.hex"
  hex_to_bin "data/${stem}.hex" "data/${stem}.elf"
  chmod +x "data/${stem}.elf"
}

# For HTTP guests we need listen 0 but keep 7099/8778 checks. Patch only the listen call.
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

run_listen() {
  local name="$1"
  shift
  local out="/tmp/vire-fcgbds-${name}.out"
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

diff_http() {
  local port="$1"
  local side="${2:-native}"
  python3 - "$port" "$CONTRACT_HTTP" "$side" <<'PY'
import json, socket, sys
from pathlib import Path

port = int(sys.argv[1])
doc = json.loads(Path(sys.argv[2]).read_text())
side = sys.argv[3] if len(sys.argv) > 3 else "native"
volatile = set(doc.get("volatile_fields") or [])
mismatches = []

def drop_volatile(obj):
    if isinstance(obj, dict):
        return {k: drop_volatile(v) for k, v in obj.items() if k not in volatile}
    if isinstance(obj, list):
        return [drop_volatile(v) for v in obj]
    return obj

def subset(got, want, path):
    if isinstance(want, dict):
        if not isinstance(got, dict):
            mismatches.append("%s: want object got %r" % (path, got))
            return
        for k, v in want.items():
            if k not in got:
                mismatches.append("%s missing key %s" % (path, k))
            else:
                subset(got[k], v, path + "." + k)
        return
    if isinstance(want, list):
        if got != want:
            mismatches.append("%s list got %r want %r" % (path, got, want))
        return
    if got != want:
        mismatches.append("%s got %r want %r" % (path, got, want))

def http(method, path, body):
    payload = body.encode("utf-8") if body else b""
    req = ("%s %s HTTP/1.1\r\nHost: 127.0.0.1\r\nConnection: close\r\n" % (method, path)).encode("ascii")
    if method in ("POST", "PUT", "PATCH"):
        req += ("Content-Type: application/json\r\nContent-Length: %d\r\n" % len(payload)).encode("ascii")
    req += b"\r\n" + payload
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
    name = case["name"]
    if side == "host" and case.get("native_only"):
        print("case %s skipped on host (native_only)" % name)
        continue
    status, headers, body = http(case.get("method") or "GET", case["path"], case.get("body") or "")
    print("case %s status %s" % (name, status))
    if status != case["status"]:
        mismatches.append("%s status got %s want %s" % (name, status, case["status"]))
    want_h = case.get("headers") or {}
    for hk, hv in want_h.items():
        g = headers.get(hk.lower(), "")
        if g.lower() != hv.lower():
            mismatches.append("%s header %s got %s want %s" % (name, hk, g, hv))
    stripped = body.strip()
    if "body" in case and "body_fields" not in case:
        if stripped != case["body"].strip():
            mismatches.append("%s body got %s want %s" % (name, stripped, case["body"]))
    if "body_fields" in case:
        try:
            parsed = json.loads(stripped)
        except Exception as e:
            mismatches.append("%s body not json %s %r" % (name, e, stripped))
            continue
        parsed = drop_volatile(parsed)
        subset(parsed, case["body_fields"], name)
        for absf in case.get("absent_fields") or []:
            if isinstance(parsed, dict) and absf in parsed:
                mismatches.append("%s unexpected field %s" % (name, absf))
    print("  body %s" % stripped[:180])

if mismatches:
    print("CONTRACT_MISMATCH")
    for m in mismatches:
        print(m)
    sys.exit(2)
print("CONTRACT_MATCH")
PY
}

pair_host_native() {
  python3 - "$1" "$2" "$CONTRACT_HTTP" <<'PY'
import json, socket, sys
from pathlib import Path

def http(port, method, path, body):
    payload = body.encode("utf-8") if body else b""
    req = ("%s %s HTTP/1.1\r\nHost: 127.0.0.1\r\nConnection: close\r\n" % (method, path)).encode("ascii")
    if method in ("POST", "PUT", "PATCH"):
        req += ("Content-Type: application/json\r\nContent-Length: %d\r\n" % len(payload)).encode("ascii")
    req += b"\r\n" + payload
    s = socket.create_connection(("127.0.0.1", int(port)), 3)
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
    head = raw[:split].decode("ascii", "replace")
    body = raw[split + 4 :].decode("utf-8")
    status = int(head.split("\r\n")[0].split(" ")[1])
    headers = {}
    for line in head.split("\r\n")[1:]:
        if ":" not in line:
            continue
        k, v = line.split(":", 1)
        headers[k.strip().lower()] = v.strip()
    return status, headers, body.strip()

host, native = sys.argv[1], sys.argv[2]
doc = json.loads(Path(sys.argv[3]).read_text())
volatile = set(doc.get("volatile_fields") or [])
mismatches = []

def drop(obj):
    if isinstance(obj, dict):
        return {k: drop(v) for k, v in obj.items() if k not in volatile}
    if isinstance(obj, list):
        return [drop(v) for v in obj]
    return obj

for case in doc["cases"]:
    if case.get("native_only"):
        print("pair %s skipped (native_only)" % case["name"])
        continue
    method = case.get("method") or "GET"
    path = case["path"]
    body = case.get("body") or ""
    hs, hh, hb = http(host, method, path, body)
    ns, nh, nb = http(native, method, path, body)
    name = case["name"]
    if hs != ns:
        mismatches.append("%s status host %s native %s" % (name, hs, ns))
    for k in ["content-type", "cache-control"]:
        if hh.get(k, "").lower() != nh.get(k, "").lower():
            mismatches.append("%s header %s host %s native %s" % (name, k, hh.get(k), nh.get(k)))
    try:
        hj, nj = json.loads(hb), json.loads(nb)
        if drop(hj) != drop(nj):
            mismatches.append("%s body host %s native %s" % (name, hb, nb))
    except Exception:
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

run_worker() {
  local label="$1"
  shift
  python3 - "$CONTRACT_WORKER" "$label" "$@" <<'PY'
import json, subprocess, sys
from pathlib import Path
doc = json.loads(Path(sys.argv[1]).read_text())
label = sys.argv[2]
cmd = sys.argv[3:]
mismatches = []
for case in doc["cases"]:
    args = cmd + list(case.get("args") or [])
    p = subprocess.run(args, capture_output=True, text=True)
    stream = (p.stdout or "") + (p.stderr or "")
    lines = [ln.rstrip("\r") for ln in stream.splitlines() if ln.strip()]
    want = case["stderr_lines"]
    print("%s %s exit %s" % (label, case["name"], p.returncode))
    for w in want:
        print("  line %s" % w)
    if p.returncode != case["exit"]:
        mismatches.append("%s %s exit got %s want %s" % (label, case["name"], p.returncode, case["exit"]))
    # required lines in order, extras (vire: ...) allowed around them
    idx = 0
    for w in want:
        found = False
        while idx < len(lines):
            if lines[idx] == w:
                found = True
                idx += 1
                break
            idx += 1
        if not found:
            mismatches.append("%s %s missing line %r in %r" % (label, case["name"], w, lines))
if mismatches:
    print("WORKER_MISMATCH %s" % label)
    for m in mismatches:
        print(m)
    sys.exit(2)
print("WORKER_MATCH %s" % label)
PY
}

echo "pass_after_sha $AFTER_SHA"
echo "fail_before_base $BEFORE_SHA"

echo "FAIL_BEFORE compile fcgbds mismatch guest"
compile_listen_guest "$FAIL_HTTP" "rebuild-fcgbds-fail"
ids="$(run_listen fcgbds-fail "./data/rebuild-fcgbds-fail.elf")"
FPID="${ids%% *}"
FPORT="${ids##* }"
echo "fail_before_listen 127.0.0.1:$FPORT"
set +e
diff_http "$FPORT"
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
echo "FAIL_BEFORE at $BEFORE_SHA fcgbds contract mismatch as required"

echo "FAIL_BEFORE worker mismatch guest"
compile_listen_guest "$FAIL_WORKER" "rebuild-worker-fail"
set +e
run_worker fail-before "./data/rebuild-worker-fail.elf"
WCODE=$?
set -e
if [[ "$WCODE" -eq 0 ]]; then
  echo "FAIL_BEFORE worker expected mismatch, got match"
  exit 1
fi
echo "FAIL_BEFORE at $BEFORE_SHA worker contract mismatch as required"

echo "PASS_AFTER compile guest-fcgbds.vire"
compile_listen_guest "$GOOD_HTTP" "rebuild-fcgbds"
ids="$(run_listen fcgbds-native "./data/rebuild-fcgbds.elf")"
GPID="${ids%% *}"
GPORT="${ids##* }"
echo "native_listen 127.0.0.1:$GPORT"

# host listen: copy guest, force listen 0 by passing no port via wrapping... guest uses args then listen with port.
# Run host with no extra args so port is 0.
ids="$(run_listen fcgbds-host dotnet exec "$VIRE_DLL" "guest-fcgbds.vire")"
HPID="${ids%% *}"
HPORT="${ids##* }"
echo "host_listen 127.0.0.1:$HPORT"

diff_http "$GPORT" native
echo "native contract ok"
diff_http "$HPORT" host
echo "host contract ok"
pair_host_native "$HPORT" "$GPORT"
stop_guest "$GPID"
stop_guest "$HPID"

echo "PASS_AFTER reserved ports 7099/8778"
for p in 7099 8778; do
  set +e
  native_out="$(./data/rebuild-fcgbds.elf "$p" 2>&1)"
  native_code=$?
  host_out="$(dotnet exec "$VIRE_DLL" guest-fcgbds.vire "$p" 2>&1)"
  host_code=$?
  set -e
  echo "native port $p exit $native_code"
  echo "$native_out"
  echo "host port $p exit $host_code"
  echo "$host_out"
  echo "$native_out" | grep -q "refusing reserved port" || { echo "native missing refuse line"; exit 1; }
  echo "$host_out" | grep -q "refusing reserved port" || { echo "host missing refuse line"; exit 1; }
  [[ "$native_code" -eq 1 && "$host_code" -eq 1 ]] || { echo "reserved port exit not 1"; exit 1; }
done

echo "PASS_AFTER compile guest-worker.vire"
compile_listen_guest "$GOOD_WORKER" "rebuild-worker"
run_worker native "./data/rebuild-worker.elf"
run_worker host dotnet exec "$VIRE_DLL" guest-worker.vire

echo "PASS_AFTER at $AFTER_SHA native ELF matches host and recorded fcgbds-go/worker-go contracts"
echo "rebuild fcgbds worker diff ok"
file data/rebuild-fcgbds.elf data/rebuild-worker.elf || true
