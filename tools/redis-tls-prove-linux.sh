#!/usr/bin/env bash
# Host interpreter and native ELF: Redis RESP2 over TLS (rediss:// verify-full).
# Throwaway CA at test time. Loopback 127.0.0.1 only.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
export VIRE_BUDGET=5000000
export VIRE_HEADLESS=1
PIN=f085dff6770513cfc9660f1a712967e177cf5b50
echo "redis_tls_fail_before_sha $PIN"
echo "pass_after_sha $(git rev-parse HEAD)"
echo "redis_tls_residual no RESP3 no ACL username no Windows PE live proof on this Linux host"

if ! git cat-file -e "${PIN}^{commit}" 2>/dev/null; then
  git fetch --depth 1 origin "$PIN"
fi
PINDIR="$(mktemp -d "${TMPDIR:-/tmp}/vire-redis-tls-fail-before.XXXXXX")"
rmdir "$PINDIR"
git worktree add --detach "$PINDIR" "$PIN"
cleanup_pin() { git worktree remove --force "$PINDIR" >/dev/null 2>&1 || rm -rf "$PINDIR"; }
trap cleanup_pin EXIT
dotnet build "$PINDIR/vire.csproj" -c Release
PIN_DLL="$PINDIR/bin/Release/net10.0/vire.dll"
mkdir -p "$PINDIR/data"
printf '%s\n' 'define main' '  redis_open_tls with 16380, "localhost", "data/redis-ca.pem"' 'end' > "$PINDIR/data/redis-tls-fail-before.vire"
set +e
before_out="$(cd "$PINDIR" && dotnet exec "$PIN_DLL" data/redis-tls-fail-before.vire 2>&1)"
before_code=$?
set -e
printf '%s\n' "$before_out"
echo "fail_before_host_exit $before_code"
if [[ "$before_code" == "0" ]]; then
  echo "FAIL_BEFORE unexpectedly passed at $PIN" >&2
  exit 1
fi
if ! grep -Fq "there is no definition named redis_open_tls" <<<"$before_out"; then
  echo "FAIL_BEFORE expected missing redis_open_tls at pin" >&2
  exit 1
fi
echo "FAIL_BEFORE at $PIN pin worktree: missing redis_open_tls"
cleanup_pin
trap - EXIT

VIRE_DLL="$ROOT/bin/Release/net10.0/vire.dll"
if [[ ! -f "$VIRE_DLL" ]]; then
  dotnet build "$ROOT/vire.csproj" -c Release
fi

if ! command -v redis-server >/dev/null 2>&1; then
  echo "redis_install apt redis-server"
  sudo apt-get update -y
  sudo DEBIAN_FRONTEND=noninteractive apt-get install -y redis-server
fi
REDIS_SERVER="$(command -v redis-server)"
echo "redis_server $REDIS_SERVER $($REDIS_SERVER --version | head -1)"
if ! ldd "$REDIS_SERVER" 2>/dev/null | grep -q libssl; then
  echo "redis-server is not linked with libssl (no TLS)" >&2
  exit 1
fi

mkdir -p "$ROOT/data"
openssl req -x509 -newkey rsa:2048 -keyout "$ROOT/data/redis-ca.key" -out "$ROOT/data/redis-ca.pem" -days 1 -nodes -subj "/CN=vire-redis-test-ca" >/dev/null 2>&1
openssl req -newkey rsa:2048 -keyout "$ROOT/data/redis-server.key" -out "$ROOT/data/redis-server.csr" -nodes -subj "/CN=localhost" >/dev/null 2>&1
openssl x509 -req -in "$ROOT/data/redis-server.csr" -CA "$ROOT/data/redis-ca.pem" -CAkey "$ROOT/data/redis-ca.key" -CAcreateserial -out "$ROOT/data/redis-server.crt" -days 1 -extfile <(printf "subjectAltName=DNS:localhost,IP:127.0.0.1\n") >/dev/null 2>&1
openssl req -x509 -newkey rsa:2048 -keyout "$ROOT/data/redis-untrusted.key" -out "$ROOT/data/redis-untrusted.pem" -days 1 -nodes -subj "/CN=untrusted-ca" >/dev/null 2>&1
openssl req -newkey rsa:2048 -keyout "$ROOT/data/redis-expired.key" -out "$ROOT/data/redis-expired.csr" -nodes -subj "/CN=localhost" >/dev/null 2>&1
rm -rf "$ROOT/data/redis-ca-db"
mkdir -p "$ROOT/data/redis-ca-db"
echo 1000 > "$ROOT/data/redis-ca-db/serial"
: > "$ROOT/data/redis-ca-db/index.txt"
cat > "$ROOT/data/redis-ca.cnf" <<EOF
[ ca ]
default_ca = CA_default
[ CA_default ]
dir = $ROOT/data/redis-ca-db
database = $ROOT/data/redis-ca-db/index.txt
serial = $ROOT/data/redis-ca-db/serial
new_certs_dir = $ROOT/data/redis-ca-db
certificate = $ROOT/data/redis-ca.pem
private_key = $ROOT/data/redis-ca.key
default_md = sha256
policy = policy_any
x509_extensions = usr_cert
default_startdate = 200101010000Z
default_enddate = 200101020000Z
[ policy_any ]
commonName = supplied
[ usr_cert ]
subjectAltName=DNS:localhost,IP:127.0.0.1
basicConstraints=CA:FALSE
EOF
openssl ca -config "$ROOT/data/redis-ca.cnf" -in "$ROOT/data/redis-expired.csr" -out "$ROOT/data/redis-expired.crt" -batch -notext
chmod 600 "$ROOT/data/redis-server.key" "$ROOT/data/redis-expired.key"

TLSPORT="${REDIS_TLS_PORT:-16380}"
PLAINPORT="${REDIS_PLAIN_PORT:-16379}"
EXPPORT="${REDIS_EXPIRED_PORT:-16381}"
SECRET="$(python3 -c 'import secrets,string; a=string.ascii_letters+string.digits; print("".join(secrets.choice(a) for _ in range(20)))')"
echo "redis_secret_len ${#SECRET}"

write_conf() {
  local conf="$1" port="$2" tlsport="$3" cert="$4" key="$5" require="$6"
  cat > "$conf" <<EOF
bind 127.0.0.1
protected-mode yes
port $port
tls-port $tlsport
tls-cert-file $cert
tls-key-file $key
tls-ca-cert-file $ROOT/data/redis-ca.pem
tls-auth-clients no
tls-protocols "TLSv1.2 TLSv1.3"
requirepass $require
daemonize no
dir $ROOT/data
dbfilename redis-tls-$tlsport.rdb
logfile $ROOT/data/redis-tls-$tlsport.log
save ""
EOF
}

write_conf "$ROOT/data/redis-tls.conf" "$PLAINPORT" "$TLSPORT" "$ROOT/data/redis-server.crt" "$ROOT/data/redis-server.key" "$SECRET"
write_conf "$ROOT/data/redis-tls-expired.conf" 0 "$EXPPORT" "$ROOT/data/redis-expired.crt" "$ROOT/data/redis-expired.key" "$SECRET"

"$REDIS_SERVER" "$ROOT/data/redis-tls.conf" &
RPID=$!
"$REDIS_SERVER" "$ROOT/data/redis-tls-expired.conf" &
EPID=$!
cleanup() {
  kill "$RPID" "$EPID" >/dev/null 2>&1 || true
  wait "$RPID" "$EPID" 2>/dev/null || true
}
trap cleanup EXIT

python3 - <<PY
import socket, time, sys
for port in ($TLSPORT, $PLAINPORT, $EXPPORT):
    ok = False
    for _ in range(80):
        s = socket.socket()
        try:
            s.settimeout(0.2)
            s.connect(("127.0.0.1", port))
            ok = True
            break
        except Exception:
            time.sleep(0.05)
        finally:
            s.close()
    if not ok:
        raise SystemExit("redis never listened on 127.0.0.1:%s" % port)
print("redis_listen 127.0.0.1:$TLSPORT tls")
print("redis_listen 127.0.0.1:$PLAINPORT plaintext")
print("redis_listen 127.0.0.1:$EXPPORT expired-tls")
PY

fill() {
  python3 - <<PY
from pathlib import Path
root = Path("$ROOT")
lib = (root / "src/rt-redis.vire").read_text()
guest = (root / "$1").read_text()
guest = guest.replace("TLS_PORT_PLACEHOLDER", "$TLSPORT")
guest = guest.replace("PLAIN_PORT_PLACEHOLDER", "$PLAINPORT")
guest = guest.replace("EXP_PORT_PLACEHOLDER", "$EXPPORT")
guest = guest.replace("SECRET_PLACEHOLDER", """$SECRET""")
(root / "$2").write_text(lib + "\n" + guest)
PY
}

fill tests/native/redis-tls.vire redis-tls-run.vire
fill tests/native/redis-tls.vire data/redis-tls-run.vire

echo "redis_tls_host_start"
set +e
host_out="$(dotnet exec "$VIRE_DLL" redis-tls-run.vire)"
host_code=$?
set -e
printf '%s\n' "$host_out"
echo "redis_tls_host_exit $host_code"
echo "redis_host_budget_cap 5000000"
if [[ "$host_code" != "0" ]]; then
  echo "host redis-tls exit $host_code"
  exit 1
fi
for n in "non-loopback refused" "plaintext-url " "auth OK" "PING PONG" "SET OK" "GET hello" "REDIS TLS PROVE pass"; do
  if ! grep -Fq "$n" <<<"$host_out"; then
    echo "host missing $n"
    exit 1
  fi
done

fill tests/native/redis-tls-verify.vire redis-tls-verify-run.vire
set +e
verify_out="$(dotnet exec "$VIRE_DLL" redis-tls-verify-run.vire)"
verify_code=$?
set -e
printf '%s\n' "$verify_out"
if [[ "$verify_code" != "0" ]]; then
  echo "host verify negatives exit $verify_code"
  exit 1
fi
for n in "wrong-host " "untrusted-ca " "expired-cert " "REDIS TLS VERIFY pass"; do
  if ! grep -Fq "$n" <<<"$verify_out"; then
    echo "host missing $n"
    exit 1
  fi
done

fill tests/native/redis-tls-neg.vire redis-tls-neg-run.vire
set +e
neg_out="$(dotnet exec "$VIRE_DLL" redis-tls-neg-run.vire)"
neg_code=$?
set -e
printf '%s\n' "$neg_out"
if [[ "$neg_code" != "0" ]]; then
  echo "host neg exit $neg_code"
  exit 1
fi
for n in "downgrade " "REDIS TLS NEG pass"; do
  if ! grep -Fq "$n" <<<"$neg_out"; then
    echo "host missing $n"
    exit 1
  fi
done
echo "redis tls linux host prove ok"

echo "redis_tls_elf_compile_start"
set +e
saved_budget="${VIRE_BUDGET:-}"
unset VIRE_BUDGET || true
compile_out="$(dotnet exec "$VIRE_DLL" --compiler compile-native.vire data/redis-tls-run.vire data/redis-tls-client.hex elf)"
compile_code=$?
if [[ -n "$saved_budget" ]]; then export VIRE_BUDGET="$saved_budget"; fi
set -e
printf '%s\n' "$compile_out"
echo "redis_tls_elf_compile_exit $compile_code"
if [[ "$compile_code" != "0" ]]; then
  echo "compile-native elf redis-tls exit $compile_code"
  exit 1
fi
python3 - <<PY
from pathlib import Path
hx = Path("$ROOT/data/redis-tls-client.hex").read_text().strip()
Path("$ROOT/data/redis-tls-client.elf").write_bytes(bytes.fromhex(hx))
PY
chmod +x "$ROOT/data/redis-tls-client.elf"
set +e
elf_out="$("$ROOT/data/redis-tls-client.elf")"
elf_code=$?
set -e
printf '%s\n' "$elf_out"
echo "redis_tls_elf_exit $elf_code"
if [[ "$elf_code" != "0" ]]; then
  echo "redis tls ELF exit $elf_code"
  exit 1
fi
host_norm="$(printf '%s' "$host_out" | tr -d '\r')"
elf_norm="$(printf '%s' "$elf_out" | tr -d '\r')"
if [[ "$host_norm" != "$elf_norm" ]]; then
  echo "HOST_ELF_MISMATCH"
  exit 1
fi
echo "redis tls host elf match"
echo "PASS_AFTER at $(git rev-parse HEAD) host and gen1 ELF redis tls stdout identical"
echo "redis tls linux prove ok"
