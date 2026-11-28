#!/usr/bin/env bash
# Host and Linux ELF vs vire-proof pg-tls-stub (tls_wrap) and redis-tls-stub (tls_connect).
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
export VIRE_HEADLESS=1
export PATH="${HOME}/.dotnet:${PATH:-}"
export DOTNET_ROOT="${DOTNET_ROOT:-$HOME/.dotnet}"
echo "pass_after_sha $(git rev-parse HEAD)"
dotnet build "$ROOT/vire.csproj" -c Release --nologo
dotnet build "$ROOT/tools/VireProof/VireProof.csproj" -c Release --nologo
VIRE_DLL="$ROOT/bin/Release/net10.0/vire.dll"
PROOF="$ROOT/tools/VireProof/bin/Release/net10.0/vire-proof.dll"
mkdir -p "$ROOT/data"
dotnet exec "$PROOF" write-pfx "$ROOT/data/pg-tls.pfx" "$ROOT/data/pg-ca.pem" x

stub_pid=""
cleanup() {
  if [[ -n "$stub_pid" ]]; then kill "$stub_pid" >/dev/null 2>&1 || true; fi
}
trap cleanup EXIT
set +e
stub_out="$(mktemp)"
dotnet exec "$PROOF" pg-tls-stub "$ROOT/data/pg-tls.pfx" x >"$stub_out" 2>&1 &
stub_pid=$!
set -e
port=""
for _ in $(seq 1 80); do
  if grep -q "listening on 127.0.0.1:" "$stub_out"; then
    port="$(grep "listening on 127.0.0.1:" "$stub_out" | head -1 | sed 's/.*://')"
    break
  fi
  sleep 0.05
done
if [[ -z "$port" ]]; then
  echo "stub did not bind" >&2
  cat "$stub_out" >&2
  exit 1
fi
echo "pg_loopback_stub 127.0.0.1:$port"

python3 - <<PY
from pathlib import Path
root = Path("$ROOT")
lib = (root / "src/rt-pg.vire").read_text()
guest = (root / "tests/native/pg-tls.vire").read_text()
guest = guest.replace("PORT_PLACEHOLDER", "$port")
guest = guest.replace("PGUSER_PLACEHOLDER", "vire")
guest = guest.replace("PGDB_PLACEHOLDER", "vire")
guest = guest.replace("PGSECRET_PLACEHOLDER", "x")
(root / "pg-tls-run.vire").write_text(lib + "\n" + guest)
(root / "data/pg-tls-run.vire").write_text(lib + "\n" + guest)
PY

export VIRE_BUDGET=5000000
set +e
host_out="$(dotnet exec "$VIRE_DLL" pg-tls-run.vire)"
host_code=$?
set -e
printf '%s\n' "$host_out"
echo "pg_tls_host_exit $host_code"
if [[ "$host_code" != "0" ]]; then
  echo "host pg-tls stub exit $host_code" >&2
  exit 1
fi
for n in "non-loopback refused" "auth trust" "cbind tls-server-end-point" "select1 1" "paramless 42" "PG TLS PROVE pass"; do
  if ! grep -Fq "$n" <<<"$host_out"; then
    echo "host missing $n" >&2
    exit 1
  fi
done

saved_budget="${VIRE_BUDGET:-}"
unset VIRE_BUDGET || true
set +e
compile_out="$(dotnet exec "$VIRE_DLL" --compiler compile-native.vire data/pg-tls-run.vire data/pg-tls-client.hex elf)"
compile_code=$?
if [[ -n "$saved_budget" ]]; then export VIRE_BUDGET="$saved_budget"; fi
set -e
printf '%s\n' "$compile_out"
echo "pg_tls_elf_compile_exit $compile_code"
if [[ "$compile_code" != "0" ]]; then
  echo "compile-native elf pg-tls exit $compile_code" >&2
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
  echo "pg tls ELF vs stub exit $elf_code" >&2
  exit 1
fi
for n in "non-loopback refused" "auth trust" "cbind tls-server-end-point" "PG TLS PROVE pass"; do
  if ! grep -Fq "$n" <<<"$elf_out"; then
    echo "elf missing $n" >&2
    exit 1
  fi
done
echo "pg tls stub host elf ok"

python3 - <<PY
from pathlib import Path
root = Path("$ROOT")
lib = (root / "src/rt-pg.vire").read_text()
guest = (root / "tests/native/pg-tls-verify.vire").read_text()
guest = guest.replace("PORT_PLACEHOLDER", "$port")
guest = guest.replace("PGUSER_PLACEHOLDER", "vire")
guest = guest.replace("PGDB_PLACEHOLDER", "vire")
guest = guest.replace("PGSECRET_PLACEHOLDER", "x")
(root / "pg-tls-verify-run.vire").write_text(lib + "\n" + guest)
PY
if [[ ! -f "$ROOT/data/pg-untrusted.pem" ]]; then
  openssl req -x509 -newkey rsa:2048 -keyout "$ROOT/data/pg-untrusted.key" -out "$ROOT/data/pg-untrusted.pem" -days 1 -nodes -subj "/CN=untrusted-ca" >/dev/null 2>&1
fi
set +e
verify_out="$(dotnet exec "$VIRE_DLL" pg-tls-verify-run.vire)"
verify_code=$?
set -e
printf '%s\n' "$verify_out"
if [[ "$verify_code" != "0" ]]; then
  echo "host verify negatives exit $verify_code" >&2
  exit 1
fi
for n in "wrong-host " "untrusted-ca " "PG TLS VERIFY pass"; do
  if ! grep -Fq "$n" <<<"$verify_out"; then
    echo "host missing $n" >&2
    exit 1
  fi
done
echo "pg tls stub fail-closed hostname/ca ok"

python3 - <<PY
from pathlib import Path
root = Path("$ROOT")
lib = (root / "src/rt-pg.vire").read_text()
guest = (root / "tests/native/pg-tls-mitm.vire").read_text()
guest = guest.replace("PORT_PLACEHOLDER", "$port")
guest = guest.replace("PGUSER_PLACEHOLDER", "vire")
guest = guest.replace("PGDB_PLACEHOLDER", "vire")
guest = guest.replace("PGSECRET_PLACEHOLDER", "x")
(root / "pg-tls-mitm-run.vire").write_text(lib + "\n" + guest)
(root / "data/pg-tls-mitm-run.vire").write_text(lib + "\n" + guest)
PY
saved_budget="${VIRE_BUDGET:-}"
unset VIRE_BUDGET || true
set +e
mitm_compile="$(dotnet exec "$VIRE_DLL" --compiler compile-native.vire data/pg-tls-mitm-run.vire data/pg-tls-mitm.hex elf)"
mitm_compile_code=$?
if [[ -n "$saved_budget" ]]; then export VIRE_BUDGET="$saved_budget"; fi
set -e
echo "pg_tls_elf_mitm_compile_exit $mitm_compile_code"
if [[ "$mitm_compile_code" != "0" ]]; then
  printf '%s\n' "$mitm_compile"
  echo "compile-native elf pg-tls-mitm exit $mitm_compile_code" >&2
  exit 1
fi
python3 - <<PY
from pathlib import Path
hx = Path("$ROOT/data/pg-tls-mitm.hex").read_text().strip()
Path("$ROOT/data/pg-tls-mitm.elf").write_bytes(bytes.fromhex(hx))
PY
chmod +x "$ROOT/data/pg-tls-mitm.elf"
set +e
mitm_out="$("$ROOT/data/pg-tls-mitm.elf")"
mitm_code=$?
set -e
printf '%s\n' "$mitm_out"
echo "pg_tls_elf_mitm_exit $mitm_code"
if [[ "$mitm_code" != "0" ]]; then
  echo "elf MITM cert exit $mitm_code" >&2
  exit 1
fi
if ! grep -Fq "PG TLS MITM pass" <<<"$mitm_out"; then
  echo "elf missing PG TLS MITM pass" >&2
  exit 1
fi
if ! grep -Fq "mitm-cert " <<<"$mitm_out"; then
  echo "elf missing mitm-cert reject" >&2
  exit 1
fi
echo "pg tls stub elf MITM cert reject ok"

dotnet exec "$PROOF" write-pfx "$ROOT/data/redis-tls.pfx" "$ROOT/data/redis-ca.pem" x
dotnet exec "$PROOF" write-pfx-expired "$ROOT/data/redis-expired.pfx" "$ROOT/data/redis-expired.pem" x
cp "$ROOT/data/redis-expired.pem" "$ROOT/data/redis-untrusted.pem"
rstub_out="$(mktemp)"
dotnet exec "$PROOF" redis-tls-stub "$ROOT/data/redis-tls.pfx" x "$ROOT/data/redis-expired.pfx" x >"$rstub_out" 2>&1 &
rstub_pid=$!
cleanup() {
  if [[ -n "$stub_pid" ]]; then kill "$stub_pid" >/dev/null 2>&1 || true; fi
  if [[ -n "${rstub_pid:-}" ]]; then kill "$rstub_pid" >/dev/null 2>&1 || true; fi
}
trap cleanup EXIT
rport=""
for _ in $(seq 1 80); do
  if grep -q "listening on 127.0.0.1:" "$rstub_out"; then
    rport="$(grep "listening on 127.0.0.1:" "$rstub_out" | head -1 | sed 's/.*://')"
    break
  fi
  sleep 0.05
done
if [[ -z "$rport" ]]; then
  echo "redis stub did not bind" >&2
  cat "$rstub_out" >&2
  exit 1
fi
echo "redis_loopback_stub 127.0.0.1:$rport"
python3 - <<PY
from pathlib import Path
root = Path("$ROOT")
lib = (root / "src/rt-redis.vire").read_text()
guest = (root / "tests/native/redis-tls.vire").read_text()
guest = guest.replace("TLS_PORT_PLACEHOLDER", "$rport")
guest = guest.replace("SECRET_PLACEHOLDER", "x")
(root / "redis-tls-run.vire").write_text(lib + "\n" + guest)
(root / "data/redis-tls-run.vire").write_text(lib + "\n" + guest)
PY
set +e
rhost_out="$(dotnet exec "$VIRE_DLL" redis-tls-run.vire)"
rhost_code=$?
set -e
printf '%s\n' "$rhost_out"
echo "redis_tls_host_exit $rhost_code"
if [[ "$rhost_code" != "0" ]]; then
  echo "host redis-tls stub exit $rhost_code" >&2
  exit 1
fi
saved_budget="${VIRE_BUDGET:-}"
unset VIRE_BUDGET || true
set +e
rcompile_out="$(dotnet exec "$VIRE_DLL" --compiler compile-native.vire data/redis-tls-run.vire data/redis-tls-client.hex elf)"
rcompile_code=$?
if [[ -n "$saved_budget" ]]; then export VIRE_BUDGET="$saved_budget"; fi
set -e
echo "redis_tls_elf_compile_exit $rcompile_code"
if [[ "$rcompile_code" != "0" ]]; then
  printf '%s\n' "$rcompile_out"
  echo "compile-native elf redis-tls exit $rcompile_code" >&2
  exit 1
fi
python3 - <<PY
from pathlib import Path
hx = Path("$ROOT/data/redis-tls-client.hex").read_text().strip()
Path("$ROOT/data/redis-tls-client.elf").write_bytes(bytes.fromhex(hx))
PY
chmod +x "$ROOT/data/redis-tls-client.elf"
set +e
relf_out="$("$ROOT/data/redis-tls-client.elf")"
relf_code=$?
set -e
printf '%s\n' "$relf_out"
echo "redis_tls_elf_exit $relf_code"
if [[ "$relf_code" != "0" ]]; then
  echo "redis tls ELF vs stub exit $relf_code" >&2
  exit 1
fi
if ! grep -Fq "REDIS TLS PROVE pass" <<<"$relf_out"; then
  echo "elf missing REDIS TLS PROVE pass" >&2
  exit 1
fi
echo "redis tls stub host elf ok"
