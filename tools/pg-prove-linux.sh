#!/usr/bin/env bash
# Host interpreter and native ELF against loopback PostgreSQL (SCRAM-SHA-256).
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
export VIRE_BUDGET=5000000
export VIRE_HEADLESS=1
PIN=5b10ea5fa5eea46859f17a52b36037d9d088c01d
echo "pg_pin $PIN"
echo "pass_after_sha $(git rev-parse HEAD)"
echo "pg_residual no TLS (TLS lane); native recv timeout is host 5s / SO_RCVTIMEO follow-up"

if ! git cat-file -e "${PIN}^{commit}" 2>/dev/null; then
  git fetch --depth 1 origin "$PIN"
fi
PINDIR="$(mktemp -d "${TMPDIR:-/tmp}/vire-pg-fail-before.XXXXXX")"
rmdir "$PINDIR"
git worktree add --detach "$PINDIR" "$PIN"
cleanup_pin() { git worktree remove --force "$PINDIR" >/dev/null 2>&1 || rm -rf "$PINDIR"; }
trap cleanup_pin EXIT
dotnet build "$PINDIR/vire.csproj" -c Release
PIN_DLL="$PINDIR/bin/Release/net10.0/vire.dll"
if [[ ! -f "$PIN_DLL" ]]; then
  echo "pin build missing $PIN_DLL" >&2
  exit 1
fi
if [[ -f "$PINDIR/src/rt-pg.vire" ]]; then
  echo "pin $PIN unexpectedly has src/rt-pg.vire" >&2
  exit 1
fi
mkdir -p "$PINDIR/data"
python3 - <<PY
from pathlib import Path
root = Path("$ROOT")
guest = (root / "tests/native/pg-client.vire").read_text()
guest = guest.replace("PORT_PLACEHOLDER", "55432")
guest = guest.replace("PGUSER_PLACEHOLDER", "vire")
guest = guest.replace("PGDB_PLACEHOLDER", "vire")
guest = guest.replace("PGSECRET_PLACEHOLDER", "")
Path("$PINDIR/data/pg-fail-before.vire").write_text(guest)
PY
echo "pg_fail_before_pin_dll $PIN_DLL"
set +e
before_out="$(cd "$PINDIR" && dotnet exec "$PIN_DLL" data/pg-fail-before.vire 2>&1)"
before_code=$?
set -e
printf '%s\n' "$before_out"
echo "fail_before_host_exit $before_code"
if [[ "$before_code" == "0" ]]; then
  echo "FAIL_BEFORE unexpectedly passed at $PIN" >&2
  exit 1
fi
if ! grep -Fq "there is no definition named pg_open" <<<"$before_out"; then
  echo "FAIL_BEFORE expected missing pg_open at pin" >&2
  exit 1
fi
captured="$(printf '%s' "$before_out" | tr '\n' '|' )"
echo "FAIL_BEFORE at $PIN pin worktree build+run of tests/native/pg-client.vire: $captured"
cleanup_pin
trap - EXIT

VIRE_DLL="$ROOT/bin/Release/net10.0/vire.dll"
if [[ ! -f "$VIRE_DLL" ]]; then
  dotnet build "$ROOT/vire.csproj" -c Release
fi
echo "pg_decode_start"
set +e
decode_out="$(dotnet exec "$VIRE_DLL" pg-decode-prove.vire)"
decode_code=$?
set -e
printf '%s\n' "$decode_out"
echo "pg_decode_exit $decode_code"
if [[ "$decode_code" != "0" ]]; then
  echo "pg-decode-prove exit $decode_code"
  exit 1
fi
if ! grep -Fq "PG DECODE PROVE pass" <<<"$decode_out"; then
  echo "decode prove missing pass line"
  exit 1
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
PGDATA="$ROOT/data/pgdata"
PGPORT="${PGPORT:-55432}"
PGUSER=vire
PGDB=vire
PGSECRET="$(python3 -c 'import secrets,string; a=string.ascii_letters+string.digits; print("".join(secrets.choice(a) for _ in range(20)))')"
echo "pg_secret_len ${#PGSECRET}"
rm -rf "$PGDATA"
mkdir -p "$ROOT/data"
"$INITDB" -D "$PGDATA" -U "$PGUSER" --auth=trust --auth-local=trust --no-sync --locale=C --encoding=UTF8
cat >> "$PGDATA/postgresql.conf" <<EOF
listen_addresses = '127.0.0.1'
port = $PGPORT
unix_socket_directories = '$ROOT/data'
password_encryption = scram-sha-256
scram_iterations = 32
EOF
cat > "$PGDATA/pg_hba.conf" <<EOF
local   all             all                                     trust
host    all             all             127.0.0.1/32            trust
host    all             all             ::1/128                 reject
host    all             all             0.0.0.0/0               reject
EOF
echo "pg_listen 127.0.0.1:$PGPORT"
"$PGCTL" -D "$PGDATA" -l "$ROOT/data/pg.log" -o "-h 127.0.0.1 -p $PGPORT" -w start
cleanup() { "$PGCTL" -D "$PGDATA" -m fast -w stop >/dev/null 2>&1 || true; }
trap cleanup EXIT
"$CREATEDB" -h 127.0.0.1 -p "$PGPORT" -U "$PGUSER" "$PGDB"
"$PSQL" -h 127.0.0.1 -p "$PGPORT" -U "$PGUSER" -d "$PGDB" -v ON_ERROR_STOP=1 -c "ALTER USER ${PGUSER} PASSWORD '${PGSECRET}';"
cat > "$PGDATA/pg_hba.conf" <<EOF
local   all             all                                     trust
host    all             all             127.0.0.1/32            scram-sha-256
host    all             all             ::1/128                 reject
host    all             all             0.0.0.0/0               reject
EOF
"$PGCTL" -D "$PGDATA" reload
echo "pg_ready loopback scram-sha-256"

python3 - <<PY
from pathlib import Path
root = Path("$ROOT")
lib = (root / "src/rt-pg.vire").read_text()
guest = (root / "tests/native/pg-client.vire").read_text()
guest = guest.replace("PORT_PLACEHOLDER", "$PGPORT")
guest = guest.replace("PGUSER_PLACEHOLDER", "$PGUSER")
guest = guest.replace("PGDB_PLACEHOLDER", "$PGDB")
guest = guest.replace("PGSECRET_PLACEHOLDER", """$PGSECRET""")
(root / "data/pg-client.vire").write_text(lib + "\n" + guest)
PY

echo "pg_timeout_start"
set +e
timeout_out="$(ROOT="$ROOT" python3 - <<PY
import socket, subprocess, os, threading, time, sys
root = os.environ["ROOT"]
dll = os.path.join(root, "bin/Release/net10.0/vire.dll")
s = socket.socket()
s.bind(("127.0.0.1", 0))
s.listen(1)
port = s.getsockname()[1]
def hold():
    try:
        c, _ = s.accept()
        time.sleep(8)
        c.close()
    except Exception:
        pass
threading.Thread(target=hold, daemon=True).start()
lib = open(os.path.join(root, "src/rt-pg.vire")).read()
src = lib + """
define main
  let opened be pg_open with \"127.0.0.1\", %d, \"vire\", \"vire\", \"x\"
  if (opened at \"ok\") == true
    say \"TIMEOUT missed\"
    halt with 1
  end
  say \"timeout \" + (opened at \"why\")
end
""" % port
path = os.path.join(root, "data/pg-timeout.vire")
open(path, "w").write(src)
p = subprocess.run(["dotnet", "exec", dll, "data/pg-timeout.vire"], cwd=root, capture_output=True, text=True)
sys.stdout.write(p.stdout or "")
sys.stderr.write(p.stderr or "")
sys.exit(p.returncode)
PY
)"
timeout_code=$?
set -e
printf '%s\n' "$timeout_out"
echo "pg_timeout_exit $timeout_code"
if [[ "$timeout_code" != "0" ]]; then
  echo "timeout prove exit $timeout_code"
  exit 1
fi
if ! grep -Eq "timeout |could not connect|closed" <<<"$timeout_out"; then
  echo "timeout prove missing reject"
  exit 1
fi

echo "pg_host_start"
set +e
host_out="$(dotnet exec "$VIRE_DLL" data/pg-client.vire)"
host_code=$?
set -e
printf '%s\n' "$host_out"
echo "pg_host_exit $host_code"
echo "pg_host_budget_cap 5000000"
if [[ "$host_code" != "0" ]]; then
  echo "host pg-client exit $host_code"
  exit 1
fi
for n in "non-loopback refused" "private refused" "auth scram-sha-256" "select1 1" "roundtrip 7" "bad-sql " "injection-blocked table-live" "rollback 1" "commit 2" "typed int-bool-null" "PG PROVE pass"; do
  if ! grep -Fq "$n" <<<"$host_out"; then
    echo "host missing $n"
    exit 1
  fi
done
echo "pg linux host prove ok"

echo "pg_elf_compile_start"
set +e
saved_budget="${VIRE_BUDGET:-}"
unset VIRE_BUDGET || true
compile_out="$(dotnet exec "$VIRE_DLL" --compiler compile-native.vire data/pg-client.vire data/pg-client.hex elf)"
compile_code=$?
if [[ -n "$saved_budget" ]]; then export VIRE_BUDGET="$saved_budget"; fi
set -e
printf '%s\n' "$compile_out"
echo "pg_elf_compile_exit $compile_code"
if [[ "$compile_code" != "0" ]]; then
  echo "compile-native elf pg-client exit $compile_code"
  exit 1
fi
python3 - <<PY
from pathlib import Path
hx = Path("$ROOT/data/pg-client.hex").read_text().strip()
Path("$ROOT/data/pg-client.elf").write_bytes(bytes.fromhex(hx))
PY
chmod +x "$ROOT/data/pg-client.elf"
set +e
elf_out="$("$ROOT/data/pg-client.elf")"
elf_code=$?
set -e
printf '%s\n' "$elf_out"
echo "pg_elf_exit $elf_code"
if [[ "$elf_code" != "0" ]]; then
  echo "pg ELF exit $elf_code"
  exit 1
fi
host_norm="$(printf '%s' "$host_out" | tr -d '\r')"
elf_norm="$(printf '%s' "$elf_out" | tr -d '\r')"
if [[ "$host_norm" != "$elf_norm" ]]; then
  echo "HOST_ELF_MISMATCH"
  exit 1
fi
echo "pg host elf match"
echo "pg linux prove ok"
