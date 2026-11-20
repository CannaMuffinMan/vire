#!/usr/bin/env bash
# Differential harness: recorded FCG health contract vs native ELF listen guest.
# FAIL_BEFORE compiles tests/rebuild/fail-before-health.vire and requires mismatch.
# PASS_AFTER compiles guest-health.vire and requires contract match.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
export PATH="${HOME}/.dotnet:${PATH:-}"
export DOTNET_ROOT="${DOTNET_ROOT:-$HOME/.dotnet}"
export VIRE_HEADLESS=1
unset VIRE_BUDGET || true

AFTER_SHA="$(git rev-parse HEAD)"
CONTRACT="$ROOT/tests/rebuild/contracts/fcg-health.json"
FAIL_SRC="$ROOT/tests/rebuild/fail-before-health.vire"
GOOD_SRC="$ROOT/guest-health.vire"

if [[ ! -f "$CONTRACT" ]]; then
  echo "missing contract $CONTRACT"
  exit 1
fi

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
  dotnet exec bin/Release/net10.0/vire.dll --compiler compile-native.vire "data/${stem}.vire" "data/${stem}.hex"
  hex_to_bin "data/${stem}.hex" "data/${stem}.elf"
  chmod +x "data/${stem}.elf"
}

run_guest() {
  local stem="$1"
  local out="/tmp/vire-rebuild-${stem}.out"
  rm -f "$out"
  "./data/${stem}.elf" >"$out" 2>&1 &
  local pid=$!
  local i
  for i in $(seq 1 100); do
    if grep -q "listening on 127.0.0.1:" "$out" 2>/dev/null; then
      break
    fi
    if ! kill -0 "$pid" 2>/dev/null; then
      cat "$out"
      echo "guest $stem exited before listen"
      exit 1
    fi
    sleep 0.05
  done
  local port
  port="$(sed -n 's/.*listening on 127.0.0.1:\([0-9]*\).*/\1/p' "$out" | head -1)"
  if [[ -z "$port" ]]; then
    cat "$out"
    echo "no listen port for $stem"
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
  python3 - "$CONTRACT" "$port" <<'PY'
import json, socket, sys
from pathlib import Path

contract = json.loads(Path(sys.argv[1]).read_text())
port = int(sys.argv[2])
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

for case in contract["cases"]:
    status, headers, body = http_get(case["path"])
    name = case["name"]
    if status != case["status"]:
        mismatches.append("%s status got %s want %s" % (name, status, case["status"]))
    want_h = case.get("headers") or {}
    for hk, hv in want_h.items():
        got = headers.get(hk.lower(), "")
        if hk.lower() == "content-type":
            if hv.lower() not in got.lower():
                mismatches.append("%s content-type got %s want contains %s" % (name, got, hv))
        elif got.lower() != hv.lower():
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

echo "pass_after_sha $AFTER_SHA"

echo "FAIL_BEFORE compile mismatch guest"
compile_listen_guest "$FAIL_SRC" "rebuild-fail"
ids="$(run_guest rebuild-fail)"
FPID="${ids%% *}"
FPORT="${ids##* }"
echo "fail_before_listen 127.0.0.1:$FPORT"
set +e
diff_contract "$FPORT"
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
ids="$(run_guest rebuild-health)"
GPID="${ids%% *}"
GPORT="${ids##* }"
echo "health_listen 127.0.0.1:$GPORT"
diff_contract "$GPORT"
stop_guest "$GPID"
echo "PASS_AFTER at $AFTER_SHA native ELF matches recorded FCG health contract"
echo "rebuild health diff ok"
