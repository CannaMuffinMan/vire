#!/usr/bin/env bash
# Fail-before / pass-after: fcgbds-go heartbeat JSON sessionId vs host listen and native ELF.
# FAIL_BEFORE at 5c3ed01 (query-only guest). PASS_AFTER is this HEAD.
# Windows PE: tools/rebuild-fcgbds-heartbeat-windows.ps1 (CouchStation; not run here).
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
STAGE="$ROOT/data/native-heartbeat"
CONTRACT="$ROOT/tests/rebuild/contracts/fcgbds-heartbeat.json"
FAIL_SRC="$ROOT/tests/rebuild/guests/fcgbds-heartbeat-fail.vire"
GOOD_SRC="$ROOT/tests/rebuild/guests/fcgbds-heartbeat.vire"
mkdir -p "$STAGE" data

dotnet build vire.csproj -c Release --nologo

hex_to_bin() {
  python3 - "$1" "$2" <<'PY'
import pathlib, sys
pathlib.Path(sys.argv[2]).write_bytes(bytes.fromhex(pathlib.Path(sys.argv[1]).read_text().strip()))
PY
}

compile_guest() {
  local src="$1"
  local stem="$2"
  cp "$src" "$STAGE/${stem}.vire"
  rm -f "$STAGE/${stem}.hex" "$STAGE/${stem}.elf"
  dotnet exec "$VIRE_DLL" --compiler compile-native.vire "data/native-heartbeat/${stem}.vire" "data/native-heartbeat/${stem}.hex"
  hex_to_bin "$STAGE/${stem}.hex" "$STAGE/${stem}.elf"
  chmod +x "$STAGE/${stem}.elf"
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
  kill "$1" 2>/dev/null || true
  wait "$1" 2>/dev/null || true
}

http_check() {
  python3 - "$@" <<'PY'
import json, socket, sys
from pathlib import Path

host_port = int(sys.argv[1])
nat_port = int(sys.argv[2]) if sys.argv[2] != "-" else None
doc = json.loads(Path(sys.argv[3]).read_text())
mismatches = []
volatile = set(doc.get("volatile_fields") or [])

def http_req(port, method, path, body=""):
    payload = body.encode("utf-8") if body else b""
    req = f"{method} {path} HTTP/1.1\r\nHost: 127.0.0.1\r\nConnection: close\r\n"
    if method in ("POST", "PUT", "PATCH"):
        req += f"Content-Length: {len(payload)}\r\n"
    req += "\r\n"
    s = socket.create_connection(("127.0.0.1", port), 8)
    s.setsockopt(socket.IPPROTO_TCP, socket.TCP_NODELAY, 1)
    s.sendall(req.encode("ascii"))
    if payload:
        s.sendall(payload)
    s.settimeout(8)
    data = b""
    while True:
        try:
            chunk = s.recv(4096)
        except socket.timeout:
            break
        if not chunk:
            break
        data += chunk
        split = data.find(b"\r\n\r\n")
        if split >= 0:
            cl = None
            for line in data[:split].split(b"\r\n")[1:]:
                if line.lower().startswith(b"content-length:"):
                    cl = int(line.split(b":", 1)[1].strip())
                    break
            if cl is not None and len(data[split + 4 :]) >= cl:
                break
    s.close()
    raw = data.decode("utf-8", "replace")
    if not raw.startswith("HTTP/"):
        raise SystemExit("empty/bad http from " + str(port) + " " + path + " " + raw[:80])
    head, _, body = raw.partition("\r\n\r\n")
    status = int(head.split(" ")[1])
    headers = {}
    for line in head.split("\r\n")[1:]:
        if ":" in line:
            k, v = line.split(":", 1)
            headers[k.strip().lower()] = v.strip()
    return status, headers, body

def drop_vol(obj):
    if isinstance(obj, dict):
        return {k: drop_vol(v) for k, v in obj.items() if k not in volatile}
    if isinstance(obj, list):
        return [drop_vol(x) for x in obj]
    return obj

def check(port, label):
    for c in doc["cases"]:
        st, hdrs, b = http_req(port, c.get("method", "POST"), c["path"], c.get("body", ""))
        if st != c["status"]:
            mismatches.append(f"{label} {c['name']} status {st} want {c['status']} body {b!r}")
            continue
        for hk, hv in c.get("headers", {}).items():
            if hdrs.get(hk.lower()) != hv:
                mismatches.append(f"{label} {c['name']} header {hk} got {hdrs.get(hk.lower())!r} want {hv!r}")
        if "body_fields" in c:
            try:
                got = drop_vol(json.loads(b))
            except json.JSONDecodeError:
                mismatches.append(f"{label} {c['name']} not json {b!r}")
                continue
            want = drop_vol(c["body_fields"])

            def subset(gotv, wantv, prefix):
                if isinstance(wantv, dict):
                    if not isinstance(gotv, dict):
                        mismatches.append(f"{label} {c['name']} {prefix} not object")
                        return
                    for kk, vv in wantv.items():
                        subset(gotv.get(kk), vv, prefix + "." + kk)
                    return
                if gotv != wantv:
                    mismatches.append(f"{label} {c['name']} {prefix} got {gotv!r} want {wantv!r}")

            subset(got, want, "")
        print(f"{label} {c['name']} status {st} body {b!r}")

check(host_port, "left")
if nat_port is not None:
    check(nat_port, "native")
    for c in doc["cases"]:
        hs, hh, hb = http_req(host_port, c.get("method", "POST"), c["path"], c.get("body", ""))
        ns, nh, nb = http_req(nat_port, c.get("method", "POST"), c["path"], c.get("body", ""))
        if hs != ns or hb != nb:
            mismatches.append(f"host-vs-native {c['name']} {hs}/{hb!r} vs {ns}/{nb!r}")
            continue
        for hk in c.get("headers", {}):
            if hh.get(hk.lower()) != nh.get(hk.lower()):
                mismatches.append(f"host-vs-native {c['name']} header {hk}")
if mismatches:
    print("\n".join(mismatches))
    sys.exit(1)
print("match", Path(sys.argv[3]).name)
PY
}

echo "fail_before_base $BEFORE_SHA"
echo "pass_after_sha $AFTER_SHA"

echo "== FAIL_BEFORE query-only guest (5c3ed01 behavior) =="
compile_guest "$FAIL_SRC" "hb-fail"
read FAIL_PID FAIL_PORT < <(run_listen hb-fail "$STAGE/hb-fail.elf")
set +e
http_check "$FAIL_PORT" "-" "$CONTRACT"
FAIL_CODE=$?
set -e
stop_guest "$FAIL_PID"
if [[ "$FAIL_CODE" -eq 0 ]]; then
  echo "FAIL_BEFORE expected mismatch"
  exit 1
fi
echo "FAIL_BEFORE at $BEFORE_SHA fcgbds-heartbeat-fail.vire vs JSON sessionId contract"

echo "== PASS_AFTER host vs native ELF =="
compile_guest "$GOOD_SRC" "hb-pass"
read HOST_PID HOST_PORT < <(run_listen hb-host dotnet exec "$VIRE_DLL" "$STAGE/hb-pass.vire")
read NAT_PID NAT_PORT < <(run_listen hb-nat "$STAGE/hb-pass.elf")
http_check "$HOST_PORT" "$NAT_PORT" "$CONTRACT"
stop_guest "$HOST_PID"
stop_guest "$NAT_PID"
echo "PASS_AFTER at $AFTER_SHA native ELF matches host and recorded fcgbds heartbeat JSON contract"
echo "rebuild fcgbds heartbeat ok"
