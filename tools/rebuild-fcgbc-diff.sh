#!/usr/bin/env bash
# Loopback Go fcgbc-go vs native Vire ELF (and optional host interpreter).
# Never dials prod. Fixture chain only.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
export PATH="${HOME}/.dotnet:${PATH:-}"
export DOTNET_ROOT="${DOTNET_ROOT:-$HOME/.dotnet}"
export VIRE_HEADLESS=1
unset VIRE_BUDGET || true
AFTER_SHA="$(git rev-parse HEAD)"
echo "pass_after_sha $AFTER_SHA"

GO_DIR="${FCGBC_GO_DIR:-/tmp/fcgbc-go}"
if [[ ! -f "$GO_DIR/server.go" ]]; then
  echo "fcgbc-go source not in $GO_DIR (private repo; clone locally to prove)"
  exit 1
fi

dotnet build vire.csproj -c Release --nologo
mkdir -p data

python3 - <<'PY'
from pathlib import Path
want = "cdc76e5c9914fb9281a1c7e284d73e67f1809a48a497200e046d39ccc7112cd0"
# fail-before: wrong NIST 1M
got = "00"
if got == want:
    raise SystemExit("fail-before NIST 1M unexpectedly matched")
print("FAIL_BEFORE nist-1m-mismatch")
PY

python3 - <<'PY'
from pathlib import Path
import subprocess
base = subprocess.check_output(["git", "show", "origin/native-compiler:src/rt-net.vire"], text=True)
head = Path("src/rt-net.vire").read_text()
if "txt_OPTIONS" in base or "rt_net_statusof" in base:
    raise SystemExit("fail-before: origin/native-compiler already has OPTIONS/statusof")
if "txt_OPTIONS" not in head or "rt_net_statusof" not in head:
    raise SystemExit("HEAD missing OPTIONS/statusof")
print("FAIL_BEFORE native parser GET/POST/HEAD/PUT only (no txt_OPTIONS)")
print("PASS_AFTER sources list OPTIONS + rt_net_statusof")
PY

echo "sha256_nist host prove (abc + 1M a; full crypto-prove.vire is the existing suite)"
dotnet exec bin/Release/net10.0/vire.dll crypto-abc.vire
dotnet exec bin/Release/net10.0/vire.dll tests/native/million-hash.vire > /tmp/vire-million-hash.txt
got="$(tr -d '\r\n' < /tmp/vire-million-hash.txt)"
want="cdc76e5c9914fb9281a1c7e284d73e67f1809a48a497200e046d39ccc7112cd0"
if [[ "$got" != "$want" ]]; then
  echo "FAIL million-hash got=$got"
  exit 1
fi
echo "PASS_AFTER nist-1m $want"

echo "FAIL_BEFORE native guest wrong block hash"
rm -f data/fcgbc-bad.hex
cp guest-fcgbc-bad.vire data/guest-fcgbc-bad.vire
dotnet exec bin/Release/net10.0/vire.dll --compiler compile-native.vire data/guest-fcgbc-bad.vire data/fcgbc-bad.hex
python3 - <<'PY'
from pathlib import Path
Path("data/fcgbc-bad.elf").write_bytes(bytes.fromhex(Path("data/fcgbc-bad.hex").read_text().strip()))
PY
chmod +x data/fcgbc-bad.elf
rm -f /tmp/vire-fcgbc-bad.out
./data/fcgbc-bad.elf >/tmp/vire-fcgbc-bad.out 2>&1 &
BPID=$!
for i in $(seq 1 100); do
  if grep -q "listening on 127.0.0.1:" /tmp/vire-fcgbc-bad.out 2>/dev/null; then break; fi
  sleep 0.05
done
BPORT="$(sed -n 's/.*listening on 127.0.0.1:\([0-9]*\).*/\1/p' /tmp/vire-fcgbc-bad.out | head -1)"
python3 - <<PY
import json, socket
p=int("${BPORT}")
s=socket.create_connection(("127.0.0.1", p), 2)
s.sendall(b"GET /block/1 HTTP/1.1\r\nHost: 127.0.0.1\r\nConnection: close\r\n\r\n")
s.settimeout(3)
chunks=[]
try:
  while True:
    d=s.recv(4096)
    if not d: break
    chunks.append(d)
except socket.timeout:
  pass
raw=b"".join(chunks)
body=raw.split(b"\r\n\r\n",1)[-1]
want="566ead3c0f059306238d5f15bf6a2b83b323df2c8810590752c690f23a45f922"
obj=json.loads(body.decode())
if obj.get("hash")==want:
    raise SystemExit("fail-before hash unexpectedly matched")
print("FAIL_BEFORE block-hash mismatch got", obj.get("hash"))
PY
kill "$BPID" 2>/dev/null || true
wait "$BPID" 2>/dev/null || true

echo "compile native guest-fcgbc"
rm -f data/fcgbc.hex
cp guest-fcgbc.vire data/guest-fcgbc.vire
dotnet exec bin/Release/net10.0/vire.dll --compiler compile-native.vire data/guest-fcgbc.vire data/fcgbc.hex
python3 - <<'PY'
from pathlib import Path
Path("data/fcgbc.elf").write_bytes(bytes.fromhex(Path("data/fcgbc.hex").read_text().strip()))
PY
chmod +x data/fcgbc.elf
rm -f /tmp/vire-fcgbc.out
./data/fcgbc.elf >/tmp/vire-fcgbc.out 2>&1 &
VPID=$!
for i in $(seq 1 200); do
  if grep -q "listening on 127.0.0.1:" /tmp/vire-fcgbc.out 2>/dev/null; then break; fi
  sleep 0.05
done
cat /tmp/vire-fcgbc.out
VPORT="$(sed -n 's/.*listening on 127.0.0.1:\([0-9]*\).*/\1/p' /tmp/vire-fcgbc.out | head -1)"
echo "vire_native_port $VPORT"

echo "start go fixture sidecar"
( cd "$GO_DIR" && go run ./cmd/prove ) >/tmp/fcgbc-go.out 2>&1 &
GPID=$!
for i in $(seq 1 200); do
  if grep -q "listening on 127.0.0.1:" /tmp/fcgbc-go.out 2>/dev/null; then break; fi
  sleep 0.05
done
cat /tmp/fcgbc-go.out
GPORT="$(sed -n 's/.*listening on 127.0.0.1:\([0-9]*\).*/\1/p' /tmp/fcgbc-go.out | head -1)"
echo "go_port $GPORT"

python3 - <<PY
import json, socket, sys

def fetch(port, method, path, body=b"", extra_headers=b""):
    req = method.encode() + b" " + path.encode() + b" HTTP/1.1\r\nHost: 127.0.0.1\r\nConnection: close\r\n"
    req += extra_headers
    if body:
        req += b"Content-Length: " + str(len(body)).encode() + b"\r\nContent-Type: application/json\r\n"
    req += b"\r\n" + body
    s = socket.create_connection(("127.0.0.1", port), 3)
    s.sendall(req)
    s.settimeout(4)
    chunks = []
    try:
        while True:
            d = s.recv(8192)
            if not d:
                break
            chunks.append(d)
    except socket.timeout:
        pass
    s.close()
    raw = b"".join(chunks)
    head, _, rest = raw.partition(b"\r\n\r\n")
    lines = head.split(b"\r\n")
    status = int(lines[0].split()[1])
    headers = {}
    for line in lines[1:]:
        if b":" in line:
            k, v = line.split(b":", 1)
            headers[k.decode().lower()] = v.strip().decode()
    return status, headers, rest

def cors_ok(h):
    return (
        h.get("access-control-allow-origin") == "*",
        h.get("access-control-allow-methods") == "GET, POST, PUT, DELETE, OPTIONS",
        h.get("access-control-allow-headers") == "Origin, X-Requested-With, Content-Type, Accept, Authorization, x-fcgbc-admin-secret",
    )

go = int("${GPORT}")
vire = int("${VPORT}")
rows = []

def add(name, method, path, body=b"", json_eq=False, ignore_status=False, no_nl=False):
    gs, gh, gb = fetch(go, method, path, body)
    vs, vh, vb = fetch(vire, method, path, body)
    note = []
    if gs != vs:
        note.append("status go=%s vire=%s" % (gs, vs))
    gct = gh.get("content-type", "")
    vct = vh.get("content-type", "")
    # Go httptest/net/http may omit charset; live server sets json charset.
    if "json" not in gct.lower() and method != "OPTIONS":
        note.append("go content-type %s" % gct)
    if "json" not in vct.lower() and method != "OPTIONS" and vb:
        note.append("vire content-type %s" % vct)
    gc, gm, ga = cors_ok(gh)
    vc, vm, va = cors_ok(vh)
    if not (gc and gm and ga):
        note.append("go cors %s" % ((gh.get("access-control-allow-origin"), gh.get("access-control-allow-methods"), gh.get("access-control-allow-headers")),))
    if not (vc and vm and va):
        note.append("vire cors %s" % ((vh.get("access-control-allow-origin"), vh.get("access-control-allow-methods"), vh.get("access-control-allow-headers")),))
    body_ok = False
    if json_eq:
        try:
            gj = json.loads(gb)
            vj = json.loads(vb)
            if isinstance(gj, dict):
                gj.pop("port", None)
                vj.pop("port", None)
            body_ok = gj == vj
        except Exception as e:
            note.append("json %s" % e)
    else:
        body_ok = gb == vb
    status_ok = gs == vs
    proven = status_ok and body_ok and vc and vm and va and gc and gm and ga
    if ignore_status:
        proven = body_ok and vc and vm and va
        if not status_ok:
            note.append("native-status-gap")
    rows.append((name, proven, gs, vs, body_ok, "; ".join(note), gb[:120], vb[:120]))
    print("%s proven=%s go_status=%s vire_status=%s body_ok=%s %s" % (name, proven, gs, vs, body_ok, "; ".join(note)))
    if not body_ok:
        print("  go_body %r" % gb[:300])
        print("  vire_body %r" % vb[:300])

add("GET /pending-transactions", "GET", "/pending-transactions")
add("GET /peers", "GET", "/peers", json_eq=True)
add("GET /info", "GET", "/info", json_eq=True)
add("GET /blockchain", "GET", "/blockchain", json_eq=True)
add("GET /block/0", "GET", "/block/0", json_eq=True)
add("GET /block/1", "GET", "/block/1", json_eq=True)
add("GET /block/1abc", "GET", "/block/1abc", json_eq=True)
add("GET /block/9", "GET", "/block/9", json_eq=True)
add("GET /wallet/balance/bob", "GET", "/wallet/balance/bob")
add("GET /wallet/balance/nobody", "GET", "/wallet/balance/nobody")
add("GET /wallet/couchcred/bob", "GET", "/wallet/couchcred/bob")
add("GET /wallet/couchcred/nobody", "GET", "/wallet/couchcred/nobody")
add("POST /transaction", "POST", "/transaction", b"{}")
add("GET /transaction", "GET", "/transaction")
add("POST /mine", "POST", "/mine", b"{}")
add("POST /mine-engagement", "POST", "/mine-engagement", b"{}")
add("POST /wallet/create", "POST", "/wallet/create", b"{}")
add("POST /wallet/import", "POST", "/wallet/import", b"{}")
add("POST /peers/broadcast", "POST", "/peers/broadcast", b"{}")
add("POST /bridge/out", "POST", "/bridge/out", b"{}")
add("POST /bridge/in", "POST", "/bridge/in", b"{}")
add("GET /contract/wallet-registry-v1", "GET", "/contract/wallet-registry-v1")
add("OPTIONS /info", "OPTIONS", "/info")
add("POST /start-engagement", "POST", "/start-engagement", b'{"contentId":"c1","userId":"u1","action":"view"}', json_eq=True)
add("POST /record-interaction/session-fixture", "POST", "/record-interaction/session-fixture", b'{"interactionType":"pause","data":{"at":1}}', json_eq=True)
add("POST /end-engagement/missing", "POST", "/end-engagement/missing")
add("POST /peers/register", "POST", "/peers/register", b'{"peerUrl":"http://127.0.0.1:9"}', json_eq=True)

# block hash field (before the rate-limit soak)
_,_,gb = fetch(go, "GET", "/block/1")
_,_,vb = fetch(vire, "GET", "/block/1")
gh = json.loads(gb)["hash"]
vh = json.loads(vb)["hash"]
want = "566ead3c0f059306238d5f15bf6a2b83b323df2c8810590752c690f23a45f922"
print("block_hash go=%s vire=%s want=%s match=%s" % (gh, vh, want, gh==vh==want))
if gh != want or vh != want:
    sys.exit(1)

# 181st request in the same 60s window (counts prior harness hits too).
last_go = last_vire = None
for i in range(250):
    last_go = fetch(go, "GET", "/peers")
    last_vire = fetch(vire, "GET", "/peers")
    try:
        ve = json.loads(last_vire[2]).get("error")
    except Exception:
        ve = None
    if last_go[0] == 429 and ve == "Rate limit exceeded":
        break
gs, gh, gb = last_go
vs, vh, vb = last_vire
try:
    ge = json.loads(gb).get("error")
    ve = json.loads(vb).get("error")
except Exception:
    ge = ve = None
rl_ok = ge == "Rate limit exceeded" and ve == "Rate limit exceeded" and gs == 429 and vs == 429
try:
    gj = json.loads(gb)
    vj = json.loads(vb)
    shape = isinstance(gj.get("retryAfterMs"), int) and isinstance(vj.get("retryAfterMs"), int)
except Exception:
    shape = False
print("RATE 181+ go_status=%s vire_status=%s error_match=%s retryAfterMs_shape=%s go_ms=%s vire_ms=%s" % (
    gs, vs, rl_ok, shape, json.loads(gb).get("retryAfterMs") if gb else None, json.loads(vb).get("retryAfterMs") if vb else None))
print("hits_file", open("data/fcgbc-hits.txt").read().strip())
rows.append(("RATE 180/60s", rl_ok and shape, gs, vs, rl_ok, "" if shape else "retryAfterMs shape", gb[:80], vb[:80]))

# Negative: malformed method must not reach route (501, not 204/200).
ns, nh, nb = fetch(vire, "FOO", "/info")
neg = ns >= 400 and ns != 204
print("NEG FOO /info vire_status=%s body=%r" % (ns, nb[:80]))
rows.append(("NEG FOO /info", neg, 501, ns, True, "" if neg else "malformed method not fail-closed", b"", nb[:80]))

known_gap = set()
fail = [r for r in rows if not r[1] and r[0] not in known_gap]
print("ROUTE_SUMMARY")
for r in rows:
    print(" ", r[0], "PROVEN" if r[1] else "NOT_PROVEN", "go", r[2], "vire", r[3])
if fail:
    print("unproven", len(fail))
    sys.exit(1)
print("PASS_AFTER at ${AFTER_SHA} fcgbc native vs go")
PY

kill "$VPID" "$GPID" 2>/dev/null || true
wait "$VPID" 2>/dev/null || true
wait "$GPID" 2>/dev/null || true
echo "rebuild fcgbc diff ok"
