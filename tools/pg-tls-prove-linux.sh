#!/usr/bin/env bash
# Host interpreter and native ELF: Postgres SSLRequest + TLS + SCRAM on loopback.
# sslmode=require and sslmode=verify-full; refuse plaintext when the server says N.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
export VIRE_BUDGET=5000000
export VIRE_HEADLESS=1
PIN=cd0bd38584e4d3faad0f46b4eefe98515b2dbf26
echo "pg_tls_fail_before_sha $PIN"
echo "pass_after_sha $(git rev-parse HEAD)"
echo "pg_tls_residual no SCRAM-SHA-256-PLUS channel binding"

if ! git cat-file -e "${PIN}^{commit}" 2>/dev/null; then
  git fetch --depth 1 origin "$PIN"
fi
PINDIR="$(mktemp -d "${TMPDIR:-/tmp}/vire-pg-tls-fail-before.XXXXXX")"
rmdir "$PINDIR"
git worktree add --detach "$PINDIR" "$PIN"
cleanup_pin() { git worktree remove --force "$PINDIR" >/dev/null 2>&1 || rm -rf "$PINDIR"; }
trap cleanup_pin EXIT
dotnet build "$PINDIR/vire.csproj" -c Release
PIN_DLL="$PINDIR/bin/Release/net10.0/vire.dll"
mkdir -p "$PINDIR/data"
python3 - <<PY
from pathlib import Path
root = Path("$ROOT")
guest = (root / "tests/native/pg-tls.vire").read_text()
guest = guest.replace("PORT_PLACEHOLDER", "55433")
guest = guest.replace("PGUSER_PLACEHOLDER", "vire")
guest = guest.replace("PGDB_PLACEHOLDER", "vire")
guest = guest.replace("PGSECRET_PLACEHOLDER", "x")
Path("$PINDIR/data/pg-tls-fail-before.vire").write_text(guest)
PY
set +e
before_out="$(cd "$PINDIR" && dotnet exec "$PIN_DLL" data/pg-tls-fail-before.vire 2>&1)"
before_code=$?
set -e
printf '%s\n' "$before_out"
echo "fail_before_host_exit $before_code"
if [[ "$before_code" == "0" ]]; then
  echo "FAIL_BEFORE unexpectedly passed at $PIN" >&2
  exit 1
fi
if ! grep -Eq "there is no definition named (pg_open_ssl|tls_wrap)" <<<"$before_out"; then
  echo "FAIL_BEFORE expected missing pg_open_ssl or tls_wrap at pin" >&2
  exit 1
fi
echo "FAIL_BEFORE at $PIN pin worktree: missing TLS wrap/open"
cleanup_pin
trap - EXIT

VIRE_DLL="$ROOT/bin/Release/net10.0/vire.dll"
if [[ ! -f "$VIRE_DLL" ]]; then
  dotnet build "$ROOT/vire.csproj" -c Release
fi

INITDB="${PGBIN:-/usr/lib/postgresql/16/bin}/initdb"
PGCTL="${PGBIN:-/usr/lib/postgresql/16/bin}/pg_ctl"
CREATEDB="${PGBIN:-/usr/lib/postgresql/16/bin}/createdb"
PSQL="${PGBIN:-/usr/lib/postgresql/16/bin}/psql"
if [[ ! -x "$INITDB" ]]; then
  INITDB="$(command -v initdb || true)"
  PGCTL="$(command -v pg_ctl || true)"
  CREATEDB="$(command -v createdb || true)"
  PSQL="$(command -v psql || true)"
fi
if [[ ! -x "$INITDB" ]]; then
  echo "pg_install apt postgresql"
  sudo apt-get update -y
  sudo DEBIAN_FRONTEND=noninteractive apt-get install -y postgresql postgresql-contrib
  INITDB="$(command -v initdb)"
  PGCTL="$(command -v pg_ctl)"
  CREATEDB="$(command -v createdb)"
  PSQL="$(command -v psql)"
fi

PGDATA="$ROOT/data/pgtlsdata"
PGPORT="${PGPORT:-55433}"
PGUSER=vire
PGDB=vire
PGSECRET="$(python3 -c 'import secrets,string; a=string.ascii_letters+string.digits; print("".join(secrets.choice(a) for _ in range(20)))')"
echo "pg_secret_len ${#PGSECRET}"
rm -rf "$PGDATA"
mkdir -p "$ROOT/data"
"$INITDB" -D "$PGDATA" -U "$PGUSER" --auth=trust --auth-local=trust --no-sync --locale=C --encoding=UTF8

openssl req -x509 -newkey rsa:2048 -keyout "$ROOT/data/pg-ca.key" -out "$ROOT/data/pg-ca.pem" -days 1 -nodes -subj "/CN=vire-test-ca"
openssl req -newkey rsa:2048 -keyout "$PGDATA/server.key" -out "$ROOT/data/pg-server.csr" -nodes -subj "/CN=localhost"
openssl x509 -req -in "$ROOT/data/pg-server.csr" -CA "$ROOT/data/pg-ca.pem" -CAkey "$ROOT/data/pg-ca.key" -CAcreateserial -out "$PGDATA/server.crt" -days 1 -extfile <(printf "subjectAltName=DNS:localhost,IP:127.0.0.1\n")
chmod 600 "$PGDATA/server.key"
cp "$ROOT/data/pg-ca.pem" "$PGDATA/root.crt"
openssl req -x509 -newkey rsa:2048 -keyout "$ROOT/data/pg-untrusted.key" -out "$ROOT/data/pg-untrusted.pem" -days 1 -nodes -subj "/CN=untrusted-ca"

cat >> "$PGDATA/postgresql.conf" <<EOF
listen_addresses = '127.0.0.1'
port = $PGPORT
unix_socket_directories = '$ROOT/data'
password_encryption = scram-sha-256
scram_iterations = 32
ssl = on
ssl_cert_file = 'server.crt'
ssl_key_file = 'server.key'
ssl_ca_file = 'root.crt'
EOF
cat > "$PGDATA/pg_hba.conf" <<EOF
local   all             all                                     trust
host    all             all             127.0.0.1/32            trust
host    all             all             ::1/128                 reject
host    all             all             0.0.0.0/0               reject
EOF
echo "pg_listen 127.0.0.1:$PGPORT ssl"
"$PGCTL" -D "$PGDATA" -l "$ROOT/data/pgtls.log" -o "-h 127.0.0.1 -p $PGPORT" -w start
cleanup() { "$PGCTL" -D "$PGDATA" -m fast -w stop >/dev/null 2>&1 || true; }
trap cleanup EXIT
export PGPASSWORD=""
"$CREATEDB" -h 127.0.0.1 -p "$PGPORT" -U "$PGUSER" "$PGDB"
"$PSQL" -h 127.0.0.1 -p "$PGPORT" -U "$PGUSER" -d "$PGDB" -v ON_ERROR_STOP=1 -c "ALTER USER ${PGUSER} PASSWORD '${PGSECRET}';"
cat > "$PGDATA/pg_hba.conf" <<EOF
local   all             all                                     trust
hostssl all             all             127.0.0.1/32            scram-sha-256
hostnossl all           all             127.0.0.1/32            reject
host    all             all             ::1/128                 reject
host    all             all             0.0.0.0/0               reject
EOF
"$PGCTL" -D "$PGDATA" reload
echo "pg_ready loopback ssl scram-sha-256"

python3 - <<PY
from pathlib import Path
root = Path("$ROOT")
lib = (root / "src/rt-pg.vire").read_text()
guest = (root / "tests/native/pg-tls.vire").read_text()
guest = guest.replace("PORT_PLACEHOLDER", "$PGPORT")
guest = guest.replace("PGUSER_PLACEHOLDER", "$PGUSER")
guest = guest.replace("PGDB_PLACEHOLDER", "$PGDB")
guest = guest.replace("PGSECRET_PLACEHOLDER", """$PGSECRET""")
(root / "pg-tls-run.vire").write_text(lib + "\n" + guest)
(root / "data/pg-tls-run.vire").write_text(lib + "\n" + guest)
PY

echo "pg_tls_host_start"
set +e
host_out="$(dotnet exec "$VIRE_DLL" pg-tls-run.vire)"
host_code=$?
set -e
printf '%s\n' "$host_out"
echo "pg_tls_host_exit $host_code"
echo "pg_host_budget_cap 5000000"
if [[ "$host_code" != "0" ]]; then
  echo "host pg-tls exit $host_code"
  exit 1
fi
for n in "non-loopback refused" "auth scram-sha-256" "select1 1" "paramless 42" "PG TLS PROVE pass"; do
  if ! grep -Fq "$n" <<<"$host_out"; then
    echo "host missing $n"
    exit 1
  fi
done
python3 - <<PY
from pathlib import Path
root = Path("$ROOT")
lib = (root / "src/rt-pg.vire").read_text()
guest = (root / "tests/native/pg-tls-verify.vire").read_text()
guest = guest.replace("PORT_PLACEHOLDER", "$PGPORT")
guest = guest.replace("PGUSER_PLACEHOLDER", "$PGUSER")
guest = guest.replace("PGDB_PLACEHOLDER", "$PGDB")
guest = guest.replace("PGSECRET_PLACEHOLDER", """$PGSECRET""")
(root / "pg-tls-verify-run.vire").write_text(lib + "\n" + guest)
PY
set +e
verify_out="$(dotnet exec "$VIRE_DLL" pg-tls-verify-run.vire)"
verify_code=$?
set -e
printf '%s\n' "$verify_out"
if [[ "$verify_code" != "0" ]]; then
  echo "host verify negatives exit $verify_code"
  exit 1
fi
for n in "wrong-host " "untrusted-ca " "PG TLS VERIFY pass"; do
  if ! grep -Fq "$n" <<<"$verify_out"; then
    echo "host missing $n"
    exit 1
  fi
done
echo "pg tls linux host prove ok"

echo "pg_tls_elf_compile_start"
set +e
saved_budget="${VIRE_BUDGET:-}"
unset VIRE_BUDGET || true
compile_out="$(dotnet exec "$VIRE_DLL" --compiler compile-native.vire data/pg-tls-run.vire data/pg-tls-client.hex elf)"
compile_code=$?
if [[ -n "$saved_budget" ]]; then export VIRE_BUDGET="$saved_budget"; fi
set -e
printf '%s\n' "$compile_out"
echo "pg_tls_elf_compile_exit $compile_code"
if [[ "$compile_code" != "0" ]]; then
  echo "compile-native elf pg-tls exit $compile_code"
  exit 1
fi
python3 - <<PY
from pathlib import Path
hx = Path("$ROOT/data/pg-tls-client.hex").read_text().strip()
Path("$ROOT/data/pg-tls-client.elf").write_bytes(bytes.fromhex(hx))
PY
chmod +x "$ROOT/data/pg-tls-client.elf"
set +e
elf_out="$("$ROOT/data/pg-tls-client.elf")"
elf_code=$?
set -e
printf '%s\n' "$elf_out"
echo "pg_tls_elf_exit $elf_code"
if [[ "$elf_code" != "0" ]]; then
  echo "pg tls ELF exit $elf_code"
  exit 1
fi
host_norm="$(printf '%s' "$host_out" | tr -d '\r')"
elf_norm="$(printf '%s' "$elf_out" | tr -d '\r')"
if [[ "$host_norm" != "$elf_norm" ]]; then
  echo "HOST_ELF_MISMATCH"
  exit 1
fi
echo "pg tls host elf match"

echo "pg_tls_neg_start"
python3 - <<'PY'
import os, socket, subprocess, threading, time
from pathlib import Path
root = os.environ.get("ROOT") or os.getcwd()
dll = os.path.join(root, "bin/Release/net10.0/vire.dll")

def serve_n(port_holder):
    s = socket.socket()
    s.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    s.bind(("127.0.0.1", 0))
    s.listen(1)
    port_holder.append(s.getsockname()[1])
    c, _ = s.accept()
    c.recv(8)
    c.send(b"N")
    time.sleep(0.2)
    c.close()
    s.close()

def serve_s(port_holder):
    s = socket.socket()
    s.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    s.bind(("127.0.0.1", 0))
    s.listen(1)
    port_holder.append(s.getsockname()[1])
    c, _ = s.accept()
    c.recv(8)
    c.send(b"S")
    time.sleep(0.2)
    try:
        c.recv(4096)
    except Exception:
        pass
    c.close()
    s.close()

nports, sports = [], []
threading.Thread(target=serve_n, args=(nports,), daemon=True).start()
threading.Thread(target=serve_s, args=(sports,), daemon=True).start()
time.sleep(0.2)
lib = Path(root, "src/rt-pg.vire").read_text()
guest = Path(root, "tests/native/pg-tls-neg.vire").read_text()
guest = guest.replace("NPORT_PLACEHOLDER", str(nports[0]))
guest = guest.replace("SPORT_PLACEHOLDER", str(sports[0]))
Path(root, "pg-tls-neg-run.vire").write_text(lib + "\n" + guest)
p = subprocess.run(["dotnet", "exec", dll, "pg-tls-neg-run.vire"], cwd=root, capture_output=True, text=True)
print(p.stdout or "")
print(p.stderr or "")
raise SystemExit(p.returncode)
PY
echo "pg tls linux prove ok"
