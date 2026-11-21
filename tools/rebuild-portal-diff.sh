#!/usr/bin/env bash
# Fail-before / pass-after for rpc-portal-go / dev-portal-go / fcgbds-dashboard-go
# JWT cookie gates, 307, 405, sandbox dist static. Linux ELF host vs native.
# Windows PE: tools/rebuild-portal-windows.ps1 (CouchStation).
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
export PATH="${HOME}/.dotnet:${PATH:-}"
export DOTNET_ROOT="${DOTNET_ROOT:-$HOME/.dotnet}"
export VIRE_HEADLESS=1
unset VIRE_BUDGET || true
unset FCG_API_TOKEN || true
unset JWT_SECRET || true

AFTER_SHA="$(git rev-parse HEAD)"
VIRE_DLL="$ROOT/bin/Release/net10.0/vire.dll"
STAGE="$ROOT/data/native-portal"
DIST="$ROOT/data/rebuild-dist"
mkdir -p "$STAGE" data

dotnet build vire.csproj -c Release --nologo
bash "$ROOT/tools/stage-compiler-src.sh"

hex_to_bin() {
  python3 - "$1" "$2" <<'PY'
import pathlib, sys
pathlib.Path(sys.argv[2]).write_bytes(bytes.fromhex(pathlib.Path(sys.argv[1]).read_text().strip()))
PY
}

echo "pass_after_sha $AFTER_SHA"

echo "== FAIL_BEFORE =="
cp "$ROOT/tests/rebuild/guests/portal-fail.vire" "$STAGE/portal-fail.vire"
rm -f "$STAGE/portal-fail.hex" "$STAGE/portal-fail.elf"
dotnet exec "$VIRE_DLL" --compiler compile-native.vire "data/native-portal/portal-fail.vire" "data/native-portal/portal-fail.hex"
hex_to_bin "$STAGE/portal-fail.hex" "$STAGE/portal-fail.elf"
chmod +x "$STAGE/portal-fail.elf"

run_listen() {
  local name="$1"
  shift
  local out="/tmp/vire-portal-${name}.out"
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
nat_port = int(sys.argv[2])
doc = json.loads(Path(sys.argv[3]).read_text())
mismatches = []

def http_req(port, method, path, body=""):
    payload = body.encode("utf-8") if body else b""
    req = f"{method} {path} HTTP/1.1\r\nHost: 127.0.0.1\r\nConnection: close\r\n"
    if method in ("POST", "PUT", "DELETE") and method != "GET":
        if method == "POST" or method == "PUT":
            req += f"Content-Length: {len(payload)}\r\n"
        elif method == "DELETE" and payload:
            req += f"Content-Length: {len(payload)}\r\n"
    if method == "POST":
        if "Content-Length" not in req:
            req += f"Content-Length: {len(payload)}\r\n"
    req += "\r\n"
    s = socket.create_connection(("127.0.0.1", port), 8)
    s.sendall(req.encode("ascii") + payload)
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

def check(port, label):
    for c in doc["cases"]:
        st, hdrs, b = http_req(port, c.get("method", "GET"), c["path"], c.get("req_body", ""))
        if st != c["status"] or b != c["body"]:
            mismatches.append(f"{label} {c['name']} got {st} {b!r} want {c['status']} {c['body']!r}")
            continue
        for hk, hv in c.get("headers", {}).items():
            if hdrs.get(hk.lower()) != hv:
                mismatches.append(f"{label} {c['name']} header {hk} got {hdrs.get(hk.lower())!r} want {hv!r}")

check(host_port, "host")
check(nat_port, "native")
for c in doc["cases"]:
    hs, hh, hb = http_req(host_port, c.get("method", "GET"), c["path"], c.get("req_body", ""))
    ns, nh, nb = http_req(nat_port, c.get("method", "GET"), c["path"], c.get("req_body", ""))
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

read FAIL_PID FAIL_PORT < <(run_listen portal-fail "$STAGE/portal-fail.elf")
set +e
http_check "$FAIL_PORT" "$FAIL_PORT" "$ROOT/tests/rebuild/contracts/fcgbds-dashboard-go.json"
FAIL_CODE=$?
set -e
stop_guest "$FAIL_PID"
if [[ "$FAIL_CODE" -eq 0 ]]; then
  echo "FAIL_BEFORE expected mismatch"
  exit 1
fi
echo "FAIL_BEFORE at $AFTER_SHA portal-fail.vire vs dashboard contract"

cp "$ROOT/src/http-client.vire" "$STAGE/http-client.vire"
cp "$ROOT/src/rt-crypto.vire" "$STAGE/rt-crypto.vire"
cp "$ROOT/src/dist-static.vire" "$STAGE/dist-static.vire"
cp "$ROOT/src/portal-jwt.vire" "$STAGE/portal-jwt.vire"
cp "$ROOT/tests/rebuild/guests/rpc-portal-go.vire" "$STAGE/rpc-portal-go.vire"
cp "$ROOT/tests/rebuild/guests/dev-portal-go.vire" "$STAGE/dev-portal-go.vire"
cp "$ROOT/tests/rebuild/guests/fcgbds-dashboard-go.vire" "$STAGE/fcgbds-dashboard-go.vire"
mkdir -p "$STAGE/data"
rm -rf "$STAGE/data/rebuild-dist"
cp -a "$DIST" "$STAGE/data/rebuild-dist"

compile_guest() {
  local stem="$1"
  rm -f "$STAGE/${stem}.hex" "$STAGE/${stem}.elf"
  dotnet exec "$VIRE_DLL" --compiler compile-native.vire "data/native-portal/${stem}.vire" "data/native-portal/${stem}.hex"
  hex_to_bin "$STAGE/${stem}.hex" "$STAGE/${stem}.elf"
  chmod +x "$STAGE/${stem}.elf"
}

echo "== compile guests =="
compile_guest rpc-portal-go
compile_guest dev-portal-go
compile_guest fcgbds-dashboard-go

SECRET="fixture-jwt-secret"
NOW=1000
DEV_PAY='{"type":"dev_session","exp":2000}'
RPC_PAY='{"role":"dev","exp":2000}'

echo "== dashboard (no dist) =="
read HOST_PID HOST_PORT < <(run_listen dash-host dotnet exec "$VIRE_DLL" "$STAGE/fcgbds-dashboard-go.vire" "-")
read NAT_PID NAT_PORT < <(run_listen dash-nat "$STAGE/fcgbds-dashboard-go.elf" "-")
http_check "$HOST_PORT" "$NAT_PORT" "$ROOT/tests/rebuild/contracts/fcgbds-dashboard-go.json"
stop_guest "$HOST_PID"
stop_guest "$NAT_PID"

echo "== dashboard static =="
read HOST_PID HOST_PORT < <(run_listen dash-static-host dotnet exec "$VIRE_DLL" "$STAGE/fcgbds-dashboard-go.vire" "data/rebuild-dist")
read NAT_PID NAT_PORT < <(run_listen dash-static-nat "$STAGE/fcgbds-dashboard-go.elf" "data/rebuild-dist")
python3 - "$HOST_PORT" "$NAT_PORT" <<'PY'
import socket, sys
def get(port, path):
    req = f"GET {path} HTTP/1.1\r\nHost: x\r\nConnection: close\r\n\r\n".encode()
    s = socket.create_connection(("127.0.0.1", int(port)), 3)
    s.sendall(req); s.settimeout(3)
    data = b""
    while True:
        try:
            c = s.recv(4096)
        except socket.timeout:
            break
        if not c:
            break
        data += c
    s.close()
    raw = data.decode()
    return int(raw.split(" ")[1]), raw.split("\r\n\r\n", 1)[1]
for path, needle in [("/", "portal-index"), ("/about", "portal-about"), ("/defense-reports", "defense-reports")]:
    hs, hb = get(sys.argv[1], path)
    ns, nb = get(sys.argv[2], path)
    if hs != 200 or ns != 200 or needle not in hb or hb != nb:
        raise SystemExit(f"static {path} {hs}/{hb!r} {ns}/{nb!r}")
print("dashboard static host-vs-native match")
PY
stop_guest "$HOST_PID"
stop_guest "$NAT_PID"

echo "== rpc-portal-go listen =="
read HOST_PID HOST_PORT < <(run_listen rpc-host dotnet exec "$VIRE_DLL" "$STAGE/rpc-portal-go.vire" "9" listen "-" "$NOW" "-" "-")
read NAT_PID NAT_PORT < <(run_listen rpc-nat "$STAGE/rpc-portal-go.elf" "9" listen "-" "$NOW" "-" "-")
http_check "$HOST_PORT" "$NAT_PORT" "$ROOT/tests/rebuild/contracts/rpc-portal-go.json"
stop_guest "$HOST_PID"
stop_guest "$NAT_PID"

echo "== dist traversal CLI =="
dotnet exec "$VIRE_DLL" "$STAGE/rpc-portal-go.vire" "9" dist-probe "-" 0 "-" "data/rebuild-dist" "/escape..path" >"$STAGE/host_trav.txt"
"$STAGE/rpc-portal-go.elf" "9" dist-probe "-" 0 "-" "data/rebuild-dist" "/escape..path" >"$STAGE/nat_trav.txt"
cmp -s "$STAGE/host_trav.txt" "$STAGE/nat_trav.txt"
grep -q "^deny" "$STAGE/nat_trav.txt"
dotnet exec "$VIRE_DLL" "$STAGE/rpc-portal-go.vire" "9" dist-probe "-" 0 "-" "data/rebuild-dist" "/about" >"$STAGE/host_okp.txt"
"$STAGE/rpc-portal-go.elf" "9" dist-probe "-" 0 "-" "data/rebuild-dist" "/about" >"$STAGE/nat_okp.txt"
cmp -s "$STAGE/host_okp.txt" "$STAGE/nat_okp.txt"
grep -q "about.html" "$STAGE/nat_okp.txt"
echo "dist path CLI host-vs-native match"

echo "== rpc JWT CLI + gated GET =="
dotnet exec "$VIRE_DLL" "$STAGE/rpc-portal-go.vire" "9" jwt-sign "$SECRET" "$NOW" "-" "-" "-" "$RPC_PAY" >"$STAGE/host_rpc_jwt.txt"
"$STAGE/rpc-portal-go.elf" "9" jwt-sign "$SECRET" "$NOW" "-" "-" "-" "$RPC_PAY" >"$STAGE/nat_rpc_jwt.txt"
cmp -s "$STAGE/host_rpc_jwt.txt" "$STAGE/nat_rpc_jwt.txt"
TOK="$(awk 'NR==2 {print}' "$STAGE/host_rpc_jwt.txt")"
test -n "$TOK"
dotnet exec "$VIRE_DLL" "$STAGE/rpc-portal-go.vire" "9" jwt-verify "$SECRET" "$NOW" "-" "-" "$TOK" >"$STAGE/host_rpc_v.txt"
"$STAGE/rpc-portal-go.elf" "9" jwt-verify "$SECRET" "$NOW" "-" "-" "$TOK" >"$STAGE/nat_rpc_v.txt"
cmp -s "$STAGE/host_rpc_v.txt" "$STAGE/nat_rpc_v.txt"
grep -q "^ok" "$STAGE/nat_rpc_v.txt"
read HOST_PID HOST_PORT < <(run_listen rpc-ok-host dotnet exec "$VIRE_DLL" "$STAGE/rpc-portal-go.vire" "9" listen "$SECRET" "$NOW" "-" "-")
read NAT_PID NAT_PORT < <(run_listen rpc-ok-nat "$STAGE/rpc-portal-go.elf" "9" listen "$SECRET" "$NOW" "-" "-")
python3 - "$HOST_PORT" "$NAT_PORT" "$TOK" <<'PY'
import socket, sys
def get(port, path, cookie):
    req = f"GET {path} HTTP/1.1\r\nHost: x\r\nCookie: dev_session={cookie}\r\nConnection: close\r\n\r\n".encode()
    s = socket.create_connection(("127.0.0.1", int(port)), 3)
    s.sendall(req); s.settimeout(3)
    data = b""
    while True:
        try:
            c = s.recv(4096)
        except socket.timeout:
            break
        if not c:
            break
        data += c
    s.close()
    raw = data.decode()
    return int(raw.split(" ")[1]), raw.split("\r\n\r\n", 1)[1]
tok = sys.argv[3]
hs, hb = get(sys.argv[1], "/api/dev/auth", tok)
ns, nb = get(sys.argv[2], "/api/dev/auth", tok)
if hs != 200 or ns != 200 or hb != '{"ok":true}' or nb != hb:
    raise SystemExit(f"rpc jwt gate {hs}/{hb!r} {ns}/{nb!r}")
print("rpc JWT cookie gate host-vs-native match")
PY
stop_guest "$HOST_PID"
stop_guest "$NAT_PID"

echo "== rpc static =="
read HOST_PID HOST_PORT < <(run_listen rpc-st-host dotnet exec "$VIRE_DLL" "$STAGE/rpc-portal-go.vire" "9" listen "-" "$NOW" "-" "data/rebuild-dist")
read NAT_PID NAT_PORT < <(run_listen rpc-st-nat "$STAGE/rpc-portal-go.elf" "9" listen "-" "$NOW" "-" "data/rebuild-dist")
python3 - "$HOST_PORT" "$NAT_PORT" <<'PY'
import socket, sys
def get(port, path):
    req = f"GET {path} HTTP/1.1\r\nHost: x\r\nConnection: close\r\n\r\n".encode()
    s = socket.create_connection(("127.0.0.1", int(port)), 3)
    s.sendall(req); s.settimeout(3)
    data = b""
    while True:
        try:
            c = s.recv(4096)
        except socket.timeout:
            break
        if not c:
            break
        data += c
    s.close()
    raw = data.decode()
    return int(raw.split(" ")[1]), raw.split("\r\n\r\n", 1)[1]
hs, hb = get(sys.argv[1], "/")
ns, nb = get(sys.argv[2], "/")
if hs != 200 or ns != 200 or "portal-index" not in hb or hb != nb:
    raise SystemExit(f"rpc index {hs}/{hb!r} {ns}/{nb!r}")
print("rpc static host-vs-native match")
PY
stop_guest "$HOST_PID"
stop_guest "$NAT_PID"

echo "== dev-portal-go 307 / 405 =="
read HOST_PID HOST_PORT < <(run_listen dev-host dotnet exec "$VIRE_DLL" "$STAGE/dev-portal-go.vire" "9" listen "-" "$NOW" "-" "-")
read NAT_PID NAT_PORT < <(run_listen dev-nat "$STAGE/dev-portal-go.elf" "9" listen "-" "$NOW" "-" "-")
http_check "$HOST_PORT" "$NAT_PORT" "$ROOT/tests/rebuild/contracts/dev-portal-go-auth.json"
python3 - "$HOST_PORT" "$NAT_PORT" <<'PY'
import socket, sys
def req(port, method, path):
    extra = "Content-Length: 0\r\n" if method == "POST" else ""
    rawreq = f"{method} {path} HTTP/1.1\r\nHost: x\r\nConnection: close\r\n{extra}\r\n".encode()
    s = socket.create_connection(("127.0.0.1", int(port)), 3)
    s.sendall(rawreq); s.settimeout(3)
    data = b""
    while True:
        try:
            c = s.recv(4096)
        except socket.timeout:
            break
        if not c:
            break
        data += c
    s.close()
    raw = data.decode()
    return int(raw.split(" ")[1]), raw.split("\r\n\r\n", 1)[1]
hs, hb = req(sys.argv[1], "POST", "/login")
ns, nb = req(sys.argv[2], "POST", "/login")
if hs != 405 or ns != 405 or hb != nb:
    raise SystemExit(f"dev 405 {hs}/{hb!r} {ns}/{nb!r}")
print("dev-portal 405 host-vs-native match")
PY
stop_guest "$HOST_PID"
stop_guest "$NAT_PID"

echo "== dev-portal JWT session =="
dotnet exec "$VIRE_DLL" "$STAGE/dev-portal-go.vire" "9" jwt-sign "$SECRET" "$NOW" "-" "-" "1" "$DEV_PAY" >"$STAGE/host_dev_jwt.txt"
"$STAGE/dev-portal-go.elf" "9" jwt-sign "$SECRET" "$NOW" "-" "-" "1" "$DEV_PAY" >"$STAGE/nat_dev_jwt.txt"
cmp -s "$STAGE/host_dev_jwt.txt" "$STAGE/nat_dev_jwt.txt"
DTOK="$(awk 'NR==2 {print}' "$STAGE/host_dev_jwt.txt")"
test -n "$DTOK"
read HOST_PID HOST_PORT < <(run_listen dev-ok-host dotnet exec "$VIRE_DLL" "$STAGE/dev-portal-go.vire" "9" listen "$SECRET" "$NOW" "-" "-" "1")
read NAT_PID NAT_PORT < <(run_listen dev-ok-nat "$STAGE/dev-portal-go.elf" "9" listen "$SECRET" "$NOW" "-" "-" "1")
python3 - "$HOST_PORT" "$NAT_PORT" "$DTOK" <<'PY'
import socket, sys
def req(port, method, path, body="", cookie=""):
    payload = body.encode()
    extra = f"Content-Length: {len(payload)}\r\n" if method == "POST" else ""
    ck = f"Cookie: fcg_dev_portal_session={cookie}\r\n" if cookie else ""
    rawreq = f"{method} {path} HTTP/1.1\r\nHost: x\r\n{ck}Connection: close\r\n{extra}\r\n".encode() + payload
    s = socket.create_connection(("127.0.0.1", int(port)), 3)
    s.sendall(rawreq); s.settimeout(3)
    data = b""
    while True:
        try:
            c = s.recv(4096)
        except socket.timeout:
            break
        if not c:
            break
        data += c
    s.close()
    raw = data.decode()
    return int(raw.split(" ")[1]), raw.split("\r\n\r\n", 1)[1]
tok = sys.argv[3]
hs, hb = req(sys.argv[1], "GET", "/api/auth/session", cookie=tok)
ns, nb = req(sys.argv[2], "GET", "/api/auth/session", cookie=tok)
if hs != 200 or ns != 200 or hb != '{"ok":true}' or nb != hb:
    raise SystemExit(f"dev session get {hs}/{hb!r} {ns}/{nb!r}")
body = '{"token":"' + tok + '"}'
hs, hb = req(sys.argv[1], "POST", "/api/auth/session", body)
ns, nb = req(sys.argv[2], "POST", "/api/auth/session", body)
if hs != 200 or ns != 200 or hb != '{"ok":true}' or nb != hb:
    raise SystemExit(f"dev session post {hs}/{hb!r} {ns}/{nb!r}")
print("dev-portal JWT session host-vs-native match")
PY
stop_guest "$HOST_PID"
stop_guest "$NAT_PID"

echo "== dev-portal static =="
read HOST_PID HOST_PORT < <(run_listen dev-st-host dotnet exec "$VIRE_DLL" "$STAGE/dev-portal-go.vire" "9" listen "-" "$NOW" "-" "data/rebuild-dist" "1")
read NAT_PID NAT_PORT < <(run_listen dev-st-nat "$STAGE/dev-portal-go.elf" "9" listen "-" "$NOW" "-" "data/rebuild-dist" "1")
python3 - "$HOST_PORT" "$NAT_PORT" <<'PY'
import socket, sys
def get(port, path):
    req = f"GET {path} HTTP/1.1\r\nHost: x\r\nConnection: close\r\n\r\n".encode()
    s = socket.create_connection(("127.0.0.1", int(port)), 3)
    s.sendall(req); s.settimeout(3)
    data = b""
    while True:
        try:
            c = s.recv(4096)
        except socket.timeout:
            break
        if not c:
            break
        data += c
    s.close()
    raw = data.decode()
    return int(raw.split(" ")[1]), raw.split("\r\n\r\n", 1)[1]
hs, hb = get(sys.argv[1], "/")
ns, nb = get(sys.argv[2], "/")
if hs != 200 or ns != 200 or "portal-index" not in hb or hb != nb:
    raise SystemExit(f"dev index {hs}/{hb!r} {ns}/{nb!r}")
print("dev-portal static host-vs-native match")
PY
stop_guest "$HOST_PID"
stop_guest "$NAT_PID"

echo "PASS_AFTER at $AFTER_SHA"
echo "JWT cookie gates, 307, 405, dist static proven host-vs-native"
echo "blocked: AES-GCM vault, FCGBC fan-out, HTTPS API, listen+proxy_reply SEGV"
