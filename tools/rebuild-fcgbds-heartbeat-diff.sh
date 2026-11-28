#!/usr/bin/env bash
# FAIL_BEFORE / PASS_AFTER for fcgbds-go JSON heartbeat sessionId (sidecar guest).
# guest-fcgbds.vire is proven by tools/rebuild-fcgbds-worker-diff.sh.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
export PATH="${HOME}/.dotnet:${PATH:-}"
export DOTNET_ROOT="${DOTNET_ROOT:-$HOME/.dotnet}"
export VIRE_HEADLESS=1
unset VIRE_BUDGET || true

AFTER_SHA="$(git rev-parse HEAD)"
CONTRACT="$ROOT/tests/rebuild/contracts/fcgbds-heartbeat.json"
FAIL_GUEST="$ROOT/tests/rebuild/guests/fcgbds-heartbeat-fail.vire"
GOOD_GUEST="$ROOT/tests/rebuild/guests/fcgbds-heartbeat.vire"
VIRE_DLL="$ROOT/bin/Release/net10.0/vire.dll"

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
  cp "$src" "data/${stem}.vire"
  rm -f "data/${stem}.hex" "data/${stem}.elf"
  dotnet exec "$VIRE_DLL" --compiler compile-native.vire "data/${stem}.vire" "data/${stem}.hex"
  hex_to_bin "data/${stem}.hex" "data/${stem}.elf"
  chmod +x "data/${stem}.elf"
}

run_listen() {
  local name="$1"
  shift
  local out="/tmp/vire-hb-${name}.out"
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
  python3 - "$port" "$CONTRACT" <<'PY'
import json, socket, sys
from pathlib import Path

port = int(sys.argv[1])
doc = json.loads(Path(sys.argv[2]).read_text())
mismatches = []

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
    if got != want:
        mismatches.append("%s got %r want %r" % (path, got, want))

def http(method, path, body):
    payload = body.encode("utf-8") if body else b""
    req = ("%s %s HTTP/1.1\r\nHost: 127.0.0.1\r\nConnection: close\r\n" % (method, path)).encode("ascii")
    if method == "POST":
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
    status = int(head.split("\r\n")[0].split(" ")[1])
    return status, body.strip()

for case in doc["cases"]:
    status, body = http(case.get("method") or "POST", case["path"], case.get("body") or "")
    print("case %s status %s body %s" % (case["name"], status, body[:160]))
    if status != case["status"]:
        mismatches.append("%s status got %s want %s" % (case["name"], status, case["status"]))
    parsed = json.loads(body)
    subset(parsed, case["body_fields"], case["name"])

if mismatches:
    print("CONTRACT_MISMATCH")
    for m in mismatches:
        print(m)
    sys.exit(2)
print("CONTRACT_MATCH")
PY
}

echo "pass_after_sha $AFTER_SHA"
echo "FAIL_BEFORE compile fcgbds-heartbeat-fail.vire"
compile_guest "$FAIL_GUEST" "rebuild-fcgbds-heartbeat-fail"
ids="$(run_listen hb-fail "./data/rebuild-fcgbds-heartbeat-fail.elf")"
FPID="${ids%% *}"
FPORT="${ids##* }"
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
echo "FAIL_BEFORE heartbeat-fail vs JSON sessionId contract as required"

echo "PASS_AFTER compile fcgbds-heartbeat.vire"
compile_guest "$GOOD_GUEST" "rebuild-fcgbds-heartbeat"
ids="$(run_listen hb-native "./data/rebuild-fcgbds-heartbeat.elf")"
GPID="${ids%% *}"
GPORT="${ids##* }"
ids="$(run_listen hb-host dotnet exec "$VIRE_DLL" "$GOOD_GUEST")"
HPID="${ids%% *}"
HPORT="${ids##* }"
diff_http "$GPORT"
echo "native heartbeat contract ok"
diff_http "$HPORT"
echo "host heartbeat contract ok"
stop_guest "$GPID"
stop_guest "$HPID"
echo "PASS_AFTER at $AFTER_SHA native ELF matches host and recorded fcgbds-heartbeat.json"
file data/rebuild-fcgbds-heartbeat.elf || true
