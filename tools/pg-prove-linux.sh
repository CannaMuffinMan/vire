#!/usr/bin/env bash
# Host interpreter against loopback PostgreSQL 16 (trust). PE is Windows-only.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
export VIRE_BUDGET=5000000
export VIRE_HEADLESS=1
PIN=5b10ea5fa5eea46859f17a52b36037d9d088c01d
echo "pg_pin $PIN"
echo "pass_after_sha $(git rev-parse HEAD)"
echo "pg_residual no TLS; SCRAM-SHA-256 not used (5M cap); auth trust"

INITDB="${PGBIN:-/usr/lib/postgresql/16/bin}/initdb"
PGCTL="${PGBIN:-/usr/lib/postgresql/16/bin}/pg_ctl"
CREATEDB="${PGBIN:-/usr/lib/postgresql/16/bin}/createdb"
if [[ ! -x "$INITDB" ]]; then
  INITDB="$(command -v initdb)"
  PGCTL="$(command -v pg_ctl)"
  CREATEDB="$(command -v createdb)"
fi
PGDATA="$ROOT/data/pgdata"
PGPORT="${PGPORT:-55432}"
PGUSER=vire
PGDB=vire
rm -rf "$PGDATA"
mkdir -p "$ROOT/data"
"$INITDB" -D "$PGDATA" -U "$PGUSER" --auth=trust --auth-local=trust --no-sync --locale=C --encoding=UTF8
cat >> "$PGDATA/postgresql.conf" <<EOF
listen_addresses = '127.0.0.1'
port = $PGPORT
unix_socket_directories = '$ROOT/data'
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
echo "pg_ready 16 loopback trust"

python3 - <<PY
from pathlib import Path
root = Path("$ROOT")
lib = (root / "src/rt-pg.vire").read_text()
guest = (root / "tests/native/pg-client.vire").read_text()
guest = guest.replace("PORT_PLACEHOLDER", "$PGPORT")
guest = guest.replace("PGUSER_PLACEHOLDER", "$PGUSER")
guest = guest.replace("PGDB_PLACEHOLDER", "$PGDB")
guest = guest.replace("PGSECRET_PLACEHOLDER", "")
(root / "data/pg-client.vire").write_text(lib + "\n" + guest)
PY

VIRE_DLL="$ROOT/bin/Release/net10.0/vire.dll"
if [[ ! -f "$VIRE_DLL" ]]; then
  dotnet build "$ROOT/vire.csproj" -c Release
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
for n in "non-loopback refused" "private refused" "select1 1" "roundtrip 7" "bad-sql " "injection-blocked table-live" "PG PROVE pass"; do
  if ! grep -Fq "$n" <<<"$host_out"; then
    echo "host missing $n"
    exit 1
  fi
done
echo "pg linux host prove ok"
echo "pg_pe_skipped linux cannot run Windows gen1 PE; see native-pg-windows"
