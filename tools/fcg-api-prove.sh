#!/usr/bin/env bash
# Host FCG API prove: throwaway Postgres + Redis, FAIL_BEFORE / PASS_AFTER.
set -euo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$root"
export VIRE_BUDGET=5000000 VIRE_HEADLESS=1
dll="$root/bin/Release/net10.0/vire.dll"
if [[ ! -f "$dll" ]]; then
  echo "missing $dll" >&2
  exit 1
fi

base_sha="9ea4561d12236f7f2f44858f137d7c948836df65"
after_sha="$(git rev-parse HEAD)"
echo "fail_before_sha $base_sha"
echo "pass_after_sha $after_sha"

redis_host="${REDIS_HOST:-127.0.0.1}"
redis_port="${REDIS_PORT:-6379}"
pg_host="${PGHOST:-127.0.0.1}"
pg_port="${PGPORT:-5432}"
pg_user="${PGUSER:-postgres}"
pg_db="${PGDATABASE:-fcgci}"
listen_port="${FCG_LISTEN_PORT:-18080}"

python3 - <<PY
import socket, time, sys
def wait(port, n=50):
    for _ in range(n):
        s = socket.socket()
        s.settimeout(0.2)
        try:
            s.connect(("127.0.0.1", port))
            s.close()
            return True
        except OSError:
            time.sleep(0.1)
    return False
if not wait(int("$redis_port")):
    print("redis not listening", file=sys.stderr)
    sys.exit(1)
print("redis_up")
PY

# Seed Redis (RESP2 ASCII). Postgres COUNT copied into waitlist:count.
python3 - <<PY
import socket
def cmd(parts):
    buf = "*%d\r\n" % len(parts)
    for p in parts:
        b = p.encode()
        buf += "$%d\r\n" % len(b) + p + "\r\n"
    s = socket.create_connection(("127.0.0.1", int("$redis_port")), 2)
    s.sendall(buf.encode())
    got = s.recv(4096)
    s.close()
    return got
print(cmd(["SET", "waitlist:count", "3"]))
print("redis_seed_ok")
PY

if command -v psql >/dev/null 2>&1; then
  PGPASSWORD="${PGPASSWORD:-fcgci}" psql -h "$pg_host" -p "$pg_port" -U "$pg_user" -d "$pg_db" -v ON_ERROR_STOP=1 -f tools/fcg-api-seed.sql
  count="$(PGPASSWORD="${PGPASSWORD:-fcgci}" psql -h "$pg_host" -p "$pg_port" -U "$pg_user" -d "$pg_db" -tAc 'SELECT COUNT(*) FROM "WaitlistEntry"')"
  echo "pg_waitlist_count $count"
  if [[ "$count" != "3" ]]; then
    echo "expected 3 waitlist rows" >&2
    exit 1
  fi
else
  echo "psql missing; redis already has waitlist:count=3"
fi

git cat-file -e "$base_sha^{commit}" 2>/dev/null || git fetch --depth 1 origin "$base_sha"
tmp="$(mktemp -d)"
git show "${base_sha}:api/fcgcpa.vire" > "$tmp/fcgcpa.vire"
old_port=18081
dotnet exec "$dll" "$tmp/fcgcpa.vire" "$old_port" >/tmp/fcg-old-listen.log 2>&1 &
old_pid=$!
python3 - <<PY
import socket, time, sys, urllib.request
port=int("$old_port")
for _ in range(80):
    s=socket.socket(); s.settimeout(0.2)
    try:
        s.connect(("127.0.0.1", port)); s.close(); break
    except OSError:
        time.sleep(0.1)
else:
    print("old listener did not bind", file=sys.stderr); sys.exit(1)
try:
    urllib.request.urlopen("http://127.0.0.1:%d/api/waitlist/count" % port, timeout=2)
    print("FAIL_BEFORE unexpectedly 200")
    sys.exit(1)
except urllib.error.HTTPError as e:
    body=e.read().decode()
    print(body)
    if e.code != 404 and '"status":404' not in body:
        print("FAIL_BEFORE expected 404, got", e.code, file=sys.stderr)
        sys.exit(1)
print("FAIL_BEFORE at $base_sha GET /api/waitlist/count is 404")
PY
kill "$old_pid" 2>/dev/null || true
wait "$old_pid" 2>/dev/null || true

mkdir -p data
dotnet exec "$dll" fcg-api.vire "$listen_port" "$redis_port" >/tmp/fcg-new-listen.log 2>&1 &
new_pid=$!
cleanup() { kill "$new_pid" 2>/dev/null || true; }
trap cleanup EXIT
python3 - <<PY
import socket, time, sys, urllib.request
port=int("$listen_port")
for _ in range(80):
    s=socket.socket(); s.settimeout(0.2)
    try:
        s.connect(("127.0.0.1", port)); s.close(); break
    except OSError:
        time.sleep(0.1)
else:
    print(open("/tmp/fcg-new-listen.log").read())
    print("new listener did not bind", file=sys.stderr); sys.exit(1)

def get(path):
    req = urllib.request.Request("http://127.0.0.1:%d%s" % (port, path), method="GET")
    try:
        with urllib.request.urlopen(req, timeout=5) as r:
            return r.status, r.read().decode()
    except urllib.error.HTTPError as e:
        return e.code, e.read().decode()

def post(path, body):
    req = urllib.request.Request("http://127.0.0.1:%d%s" % (port, path), data=body.encode(), method="POST")
    req.add_header("Content-Type", "application/json")
    try:
        with urllib.request.urlopen(req, timeout=15) as r:
            return r.status, r.read().decode()
    except urllib.error.HTTPError as e:
        return e.code, e.read().decode()

checks = [
    ("GET", "/health", None, '{"ok":true,"service":"fcgcpa","payments":false}'),
    ("GET", "/api/health", None, '{"ok":true,"service":"fcgcpa","payments":false}'),
    ("GET", "/api/health/redis", None, '{"ok":true,"redis":"PONG","payments":false}'),
    ("GET", "/payments", None, '{"ok":false,"status":403,"error":"payments are off","payments":false}'),
    ("GET", "/api/payment/catalog", None, '{"ok":false,"status":403,"error":"payments are off","payments":false}'),
    ("GET", "/api/capabilities", None, None),
    ("GET", "/api/couchy/info", None, None),
    ("GET", "/api/waitlist/count", None, '{"count":3,"max":null,"spotsLeft":null,"full":false,"registrationClosed":false}'),
    ("GET", "/connect", None, '{"twitch":"https://www.twitch.tv","youtube":"https://www.youtube.com"}'),
    ("GET", "/info", None, None),
    ("POST", "/api/login", "{}", '{"ok":false,"status":404,"error":"Endpoint not found"}'),
]
for method, path, body, want in checks:
    st, got = get(path) if method == "GET" else post(path, body)
    print("ROUTE", method, path, st, got)
    if want is not None and got != want:
        print("mismatch want", want, file=sys.stderr)
        sys.exit(1)
    if '"payments":true' in got:
        print("payments leaked on", file=sys.stderr)
        sys.exit(1)
print("PASS_AFTER host FCG API routes at $after_sha")
PY
echo "fcg host prove ok"
bash tools/fcg-api-pack.sh
saved="${VIRE_BUDGET-}"
unset VIRE_BUDGET || true
set +e
dotnet exec "$dll" --compiler compile-native.vire data/fcg-api-guest.vire data/fcg-api.hex
cc=$?
set -e
if [[ -n "${saved}" ]]; then export VIRE_BUDGET="$saved"; fi
if [[ "$cc" -ne 0 ]]; then
  echo "compile-native fcg-api-guest failed" >&2
  exit 1
fi
echo "PASS_AFTER compile-native packed FCG guest at $after_sha"
