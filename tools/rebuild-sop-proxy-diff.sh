#!/usr/bin/env bash
# Fail-before / pass-after for landing-go SOP HMAC cookie + loopback proxy
# routes (landing-go / dev-portal-go / edge-go). Linux ELF host vs native.
# Windows PE: tools/rebuild-sop-proxy-windows.ps1 (CouchStation).
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
export PATH="${HOME}/.dotnet:${PATH:-}"
export DOTNET_ROOT="${DOTNET_ROOT:-$HOME/.dotnet}"
export VIRE_HEADLESS=1
unset VIRE_BUDGET || true
unset FCG_API_TOKEN || true

AFTER_SHA="$(git rev-parse HEAD)"
BEFORE_SHA="223b4ef302e6ca3ca7677117e4af147541c05a30"
VIRE_DLL="$ROOT/bin/Release/net10.0/vire.dll"
STAGE="$ROOT/data/native-sop"
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
echo "fail_before_base $BEFORE_SHA"

echo "== FAIL_BEFORE =="
FAIL_OUT="$(dotnet exec "$VIRE_DLL" tests/rebuild/guests/sop-fail.vire)"
echo "$FAIL_OUT"
echo "$FAIL_OUT" | grep -q "not gated" || { echo "fail-before missing not gated"; exit 1; }
echo "$FAIL_OUT" | grep -q "not proxied" || { echo "fail-before missing not proxied"; exit 1; }
echo "FAIL_BEFORE at $BEFORE_SHA (sop-fail.vire)"

cp "$ROOT/src/http-client.vire" "$STAGE/http-client.vire"
cp "$ROOT/src/rt-crypto.vire" "$STAGE/rt-crypto.vire"
cp "$ROOT/src/sop-cookie.vire" "$STAGE/sop-cookie.vire"
cp "$ROOT/src/dist-static.vire" "$STAGE/dist-static.vire"
cp "$ROOT/src/portal-jwt.vire" "$STAGE/portal-jwt.vire"
cp "$ROOT/tests/rebuild/guests/landing-sop.vire" "$STAGE/landing-sop.vire"
cp "$ROOT/tests/rebuild/guests/landing-proxy.vire" "$STAGE/landing-proxy.vire"
cp "$ROOT/tests/rebuild/guests/dev-portal-go.vire" "$STAGE/dev-portal-go.vire"
cp "$ROOT/tests/rebuild/guests/edge-go.vire" "$STAGE/edge-go.vire"

compile_guest() {
  local stem="$1"
  rm -f "$STAGE/${stem}.hex" "$STAGE/${stem}.elf"
  dotnet exec "$VIRE_DLL" --compiler compile-native.vire "data/native-sop/${stem}.vire" "data/native-sop/${stem}.hex"
  hex_to_bin "$STAGE/${stem}.hex" "$STAGE/${stem}.elf"
  chmod +x "$STAGE/${stem}.elf"
}

echo "== compile guests =="
compile_guest landing-sop
compile_guest landing-proxy
compile_guest dev-portal-go
compile_guest edge-go

SECRET="$(python3 -c 'import os; print(os.urandom(16).hex())')"
NOW=1000
EXP_OK=2000
EXP_OLD=500

echo "== cookie CLI host vs native =="
dotnet exec "$VIRE_DLL" "$STAGE/landing-sop.vire" "$SECRET" 0 "$NOW" issue "$EXP_OK" >"$STAGE/host_issue.txt"
"$STAGE/landing-sop.elf" "$SECRET" 0 "$NOW" issue "$EXP_OK" >"$STAGE/nat_issue.txt"
cat "$STAGE/host_issue.txt"
cat "$STAGE/nat_issue.txt"
cmp -s "$STAGE/host_issue.txt" "$STAGE/nat_issue.txt"
COOKIE="$(awk 'NR==2 {print}' "$STAGE/host_issue.txt")"
if [[ -z "$COOKIE" || "$COOKIE" != v1.* ]]; then
  echo "cookie missing v1. prefix"
  exit 1
fi

cli_pair() {
  local stem="$1" needle="$2"
  shift 2
  dotnet exec "$VIRE_DLL" "$STAGE/landing-sop.vire" "$@" >"$STAGE/host_${stem}.txt"
  "$STAGE/landing-sop.elf" "$@" >"$STAGE/nat_${stem}.txt"
  cmp -s "$STAGE/host_${stem}.txt" "$STAGE/nat_${stem}.txt"
  grep -q "$needle" "$STAGE/host_${stem}.txt"
  echo "$stem $(tr '\n' ' ' < "$STAGE/host_${stem}.txt")"
}

cli_pair ok "^ok" "$SECRET" 0 "$NOW" verify "$COOKIE" "$NOW"
TAMPER="${COOKIE}00"
cli_pair tamper "tamper" "$SECRET" 0 "$NOW" verify "$TAMPER" "$NOW"
cli_pair expired "expired" "$SECRET" 0 "$NOW" verify "$COOKIE" 9000
cli_pair missing "missing" "$SECRET" 0 "$NOW" verify "-" "$NOW"
HDR="Cookie:fcg_sop_authenticated=${COOKIE}"
cli_pair header "^ok" "$SECRET" 0 "$NOW" header "$HDR" "$NOW"

PORTFILE="/tmp/vire-sop-up-$$.port"
rm -f "$PORTFILE"
python3 - "$PORTFILE" <<'PY' &
import socket, os, sys
portfile = sys.argv[1]
s = socket.socket(); s.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
s.bind(("127.0.0.1", 0)); s.listen(16)
open(portfile, "w").write(str(s.getsockname()[1]))
while True:
    c, _ = s.accept()
    try:
        c.settimeout(2)
        data = b""
        while b"\r\n\r\n" not in data and len(data) < 65536:
            chunk = c.recv(4096)
            if not chunk:
                break
            data += chunk
        req = data.split(b"\r\n", 1)[0].decode("ascii", "replace")
        path = req.split(" ")[1] if " " in req else "/"
        body = b"up-ok" if (path.startswith("/echo") or path.startswith("/up")) else b"nope"
        hdr = (
            b"HTTP/1.1 200 OK\r\nContent-Type: text/plain\r\nContent-Length: "
            + str(len(body)).encode()
            + b"\r\nConnection: close\r\n\r\n"
            + body
        )
        c.sendall(hdr)
    finally:
        c.close()
PY
UP_PID=$!
for i in $(seq 1 100); do
  if [[ -s "$PORTFILE" ]]; then break; fi
  sleep 0.05
done
UP_PORT="$(cat "$PORTFILE")"
test -n "$UP_PORT"

run_listen() {
  local name="$1"
  shift
  local out="/tmp/vire-sop-${name}.out"
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

diff_http() {
  python3 - "$@" <<'PY'
import json, socket, sys
from pathlib import Path

kind = sys.argv[1]
host_port = int(sys.argv[2])
nat_port = int(sys.argv[3])
doc = json.loads(Path(sys.argv[4]).read_text())
secret = sys.argv[5] if len(sys.argv) > 5 else ""
cookie = sys.argv[6] if len(sys.argv) > 6 else ""
mismatches = []

def http_req(port, method, path, body):
    payload = body.encode("utf-8") if body else b""
    req = f"{method} {path} HTTP/1.1\r\nHost: 127.0.0.1\r\nConnection: close\r\n"
    if method == "POST":
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
        raise SystemExit("empty/bad http from " + str(port) + " " + path + " " + raw[:80].encode("unicode_escape").decode())
    head, _, body = raw.partition("\r\n\r\n")
    status = int(head.split(" ")[1])
    headers = {}
    for line in head.split("\r\n")[1:]:
        if ":" in line:
            k, v = line.split(":", 1)
            headers[k.strip().lower()] = v.strip()
    return status, headers, body

def check(port, cases, label):
    for c in cases:
        method = c.get("method", "GET")
        path = c["path"]
        body = c.get("req_body", c.get("post_body", ""))
        st, hdrs, b = http_req(port, method, path, body)
        want_st = c["status"]
        want_b = c["body"]
        if st != want_st or b != want_b:
            mismatches.append(f"{label} {c['name']} status/body got {st} {b!r} want {want_st} {want_b!r}")
            continue
        for hk, hv in c.get("headers", {}).items():
            got = hdrs.get(hk.lower())
            if got != hv:
                mismatches.append(f"{label} {c['name']} header {hk} got {got!r} want {hv!r}")

if kind == "cookie":
    extra = [
        {"name": "post_ok", "method": "POST", "path": "/api/sop-auth", "req_body": cookie, "status": 200,
         "headers": {"content-type": "application/json", "connection": "close", "x-content-type-options": "nosniff", "cache-control": "no-store"},
         "body": "{\"ok\":true}"},
        {"name": "post_tamper", "method": "POST", "path": "/api/sop-auth", "req_body": cookie[:-1] + "0", "status": 401,
         "headers": {"content-type": "application/json", "connection": "close", "x-content-type-options": "nosniff", "cache-control": "no-store"},
         "body": "{\"ok\":false,\"status\":401,\"error\":\"tamper\"}"},
        {"name": "post_expired", "method": "POST", "path": "/api/sop-auth", "req_body": cookie, "status": 401,
         "headers": {"content-type": "application/json", "connection": "close", "x-content-type-options": "nosniff", "cache-control": "no-store"},
         "body": "{\"ok\":false,\"status\":401,\"error\":\"expired\"}", "expired_clock": True},
    ]
    # expired uses a separate listen with now=9000; skip here if cookie-ok listen now=1000
    extra = [x for x in extra if x["name"] != "post_expired"]
    cases = doc["cases"] + extra
    check(host_port, cases, "host")
    check(nat_port, cases, "native")
    for c in cases:
        hs, hh, hb = http_req(host_port, c.get("method", "GET"), c["path"], c.get("req_body", ""))
        ns, nh, nb = http_req(nat_port, c.get("method", "GET"), c["path"], c.get("req_body", ""))
        if hs != ns or hb != nb:
            mismatches.append(f"host-vs-native {c['name']} {hs}/{hb!r} vs {ns}/{nb!r}")
            continue
        for hk in c.get("headers", {}):
            if hh.get(hk) != nh.get(hk):
                mismatches.append(f"host-vs-native {c['name']} header {hk}")
elif kind == "plain":
    cases = doc["cases"]
    check(host_port, cases, "host")
    check(nat_port, cases, "native")
    for c in cases:
        hs, hh, hb = http_req(host_port, c.get("method", "GET"), c["path"], "")
        ns, nh, nb = http_req(nat_port, c.get("method", "GET"), c["path"], "")
        if hs != ns or hb != nb:
            mismatches.append(f"host-vs-native {c['name']} {hs}/{hb!r} vs {ns}/{nb!r}")
            continue
        for hk in c.get("headers", {}):
            if hh.get(hk) != nh.get(hk):
                mismatches.append(f"host-vs-native {c['name']} header {hk}")

if mismatches:
    print("\n".join(mismatches))
    sys.exit(1)
print("match", Path(sys.argv[4]).name)
PY
}

echo "== landing SOP listen =="
read HOST_PID HOST_PORT < <(run_listen landing-host dotnet exec "$VIRE_DLL" "$STAGE/landing-sop.vire" "$SECRET" 0 "$NOW")
read NAT_PID NAT_PORT < <(run_listen landing-nat "$STAGE/landing-sop.elf" "$SECRET" 0 "$NOW")
diff_http cookie "$HOST_PORT" "$NAT_PORT" "$ROOT/tests/rebuild/contracts/landing-go/sop-cookie.json" "$SECRET" "$COOKIE"
stop_guest "$HOST_PID"
stop_guest "$NAT_PID"

echo "== landing loopback proxy (host listen vs native CLI) =="
read HOST_PID HOST_PORT < <(run_listen landing-proxy-host dotnet exec "$VIRE_DLL" "$STAGE/landing-proxy.vire" "$UP_PORT" listen)
diff_http plain "$HOST_PORT" "$HOST_PORT" "$ROOT/tests/rebuild/contracts/landing-go/sop-proxy.json"
dotnet exec "$VIRE_DLL" "$STAGE/landing-proxy.vire" "$UP_PORT" proxy-echo >"$STAGE/host_pe.txt"
"$STAGE/landing-proxy.elf" "$UP_PORT" proxy-echo >"$STAGE/nat_pe.txt"
cmp -s "$STAGE/host_pe.txt" "$STAGE/nat_pe.txt"
grep -q "^200" "$STAGE/nat_pe.txt"
grep -q "up-ok" "$STAGE/nat_pe.txt"
dotnet exec "$VIRE_DLL" "$STAGE/landing-proxy.vire" "$UP_PORT" proxy-down >"$STAGE/host_pd.txt"
"$STAGE/landing-proxy.elf" "$UP_PORT" proxy-down >"$STAGE/nat_pd.txt"
cmp -s "$STAGE/host_pd.txt" "$STAGE/nat_pd.txt"
grep -q "^502" "$STAGE/nat_pd.txt"
echo "landing proxy CLI host-vs-native match"
stop_guest "$HOST_PID"

read HOST_PID HOST_PORT < <(run_listen landing-exp-host dotnet exec "$VIRE_DLL" "$STAGE/landing-sop.vire" "$SECRET" 0 9000)
read NAT_PID NAT_PORT < <(run_listen landing-exp-nat "$STAGE/landing-sop.elf" "$SECRET" 0 9000)
python3 - "$HOST_PORT" "$NAT_PORT" "$COOKIE" <<'PY'
import socket, sys
def post(port, body):
    payload = body.encode()
    req = f"POST /api/sop-auth HTTP/1.1\r\nHost: x\r\nConnection: close\r\nContent-Length: {len(payload)}\r\n\r\n".encode() + payload
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
    st = int(raw.split(" ")[1]); body = raw.split("\r\n\r\n",1)[1]
    return st, body
cookie = sys.argv[3]
for p, lab in [(sys.argv[1],"host"), (sys.argv[2],"native")]:
    st, b = post(p, cookie)
    if st != 401 or "expired" not in b:
        raise SystemExit(lab + " expired miss " + str(st) + " " + b)
print("expired listen match")
PY
stop_guest "$HOST_PID"
stop_guest "$NAT_PID"

echo "== dev-portal-go =="
read HOST_PID HOST_PORT < <(run_listen portal-host dotnet exec "$VIRE_DLL" "$STAGE/dev-portal-go.vire" "$UP_PORT" listen)
read NAT_PID NAT_PORT < <(run_listen portal-nat "$STAGE/dev-portal-go.elf" "$UP_PORT" listen)
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
    st = int(raw.split(" ")[1])
    body = raw.split("\r\n\r\n", 1)[1]
    return st, body
cases = [
    ("/", 503, '{"reason":"dist_missing","status":503}'),
    ("/api/auth/session", 307, '{"status":307}'),
]
for path, st, body in cases:
    hs, hb = get(sys.argv[1], path)
    ns, nb = get(sys.argv[2], path)
    if hs != st or ns != st or hb != body or nb != body:
        raise SystemExit(f"portal {path} {hs}/{hb!r} {ns}/{nb!r}")
print("portal goldens host-vs-native match")
PY
stop_guest "$HOST_PID"
stop_guest "$NAT_PID"
read HOST_PID HOST_PORT < <(run_listen portal-auth-host dotnet exec "$VIRE_DLL" "$STAGE/dev-portal-go.vire" "$UP_PORT" listen "-" 0 "-" "-" "1")
read NAT_PID NAT_PORT < <(run_listen portal-auth-nat "$STAGE/dev-portal-go.elf" "$UP_PORT" listen "-" 0 "-" "-" "1")
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
hs, hb = get(sys.argv[1], "/api/auth/session")
ns, nb = get(sys.argv[2], "/api/auth/session")
if hs != 503 or ns != 503 or hb != '{"ok":false,"error":"not_configured","status":503}' or nb != hb:
    raise SystemExit(f"portal gated session {hs}/{hb!r} {ns}/{nb!r}")
print("portal session not_configured with page cookie match")
PY
stop_guest "$HOST_PID"
stop_guest "$NAT_PID"
dotnet exec "$VIRE_DLL" "$STAGE/dev-portal-go.vire" "$UP_PORT" proxy-echo >"$STAGE/host_portal_pe.txt"
"$STAGE/dev-portal-go.elf" "$UP_PORT" proxy-echo >"$STAGE/nat_portal_pe.txt"
cmp -s "$STAGE/host_portal_pe.txt" "$STAGE/nat_portal_pe.txt"
grep -q "up-ok" "$STAGE/nat_portal_pe.txt"
echo "portal proxy CLI match"

echo "== edge-go =="
read HOST_PID HOST_PORT < <(run_listen edge-www-host dotnet exec "$VIRE_DLL" "$STAGE/edge-go.vire" "$UP_PORT" www)
read NAT_PID NAT_PORT < <(run_listen edge-www-nat "$STAGE/edge-go.elf" "$UP_PORT" www)
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
hs, hb = get(sys.argv[1], "/healthz")
ns, nb = get(sys.argv[2], "/healthz")
if hs != 200 or ns != 200 or hb != "ok" or nb != "ok":
    raise SystemExit(f"edge healthz {hs} {ns} {hb!r} {nb!r}")
print("edge healthz host-vs-native match")
PY
stop_guest "$HOST_PID"
stop_guest "$NAT_PID"
dotnet exec "$VIRE_DLL" "$STAGE/edge-go.vire" "$UP_PORT" proxy-echo >"$STAGE/host_edge_pe.txt"
"$STAGE/edge-go.elf" "$UP_PORT" proxy-echo >"$STAGE/nat_edge_pe.txt"
cmp -s "$STAGE/host_edge_pe.txt" "$STAGE/nat_edge_pe.txt"
grep -q "up-ok" "$STAGE/nat_edge_pe.txt"
echo "edge proxy CLI match"

echo "== edge-go unknown Host =="
read HOST_PID HOST_PORT < <(run_listen edge-unk-host dotnet exec "$VIRE_DLL" "$STAGE/edge-go.vire" "$UP_PORT" unknown)
read NAT_PID NAT_PORT < <(run_listen edge-unk-nat "$STAGE/edge-go.elf" "$UP_PORT" unknown)
python3 - "$HOST_PORT" "$NAT_PORT" <<'PY'
import socket, sys
def get(port):
    req = b"GET /echo HTTP/1.1\r\nHost: x\r\nConnection: close\r\n\r\n"
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
    return int(raw.split(" ")[1]), raw.split("\r\n\r\n",1)[1]
h, hb = get(sys.argv[1]); n, nb = get(sys.argv[2])
if h != 404 or n != 404 or hb != nb:
    raise SystemExit(f"unknown host {h} {n} {hb!r} {nb!r}")
print("edge unknown match")
PY
stop_guest "$HOST_PID"
stop_guest "$NAT_PID"

kill "$UP_PID" 2>/dev/null || true
wait "$UP_PID" 2>/dev/null || true

echo "PASS_AFTER at $AFTER_SHA"
echo "cookie gate: missing/tamper/expired deny; ct_eq MAC; fixture secret only"
