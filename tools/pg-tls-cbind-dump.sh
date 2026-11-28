#!/usr/bin/env bash
# Dump host vs ELF tls_peer_cert / tls_end_point bytes vs the stub leaf.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
export VIRE_HEADLESS=1
export PATH="${HOME}/.dotnet:${PATH:-}"
export DOTNET_ROOT="${DOTNET_ROOT:-$HOME/.dotnet}"
dotnet build "$ROOT/vire.csproj" -c Release --nologo
dotnet build "$ROOT/tools/VireProof/VireProof.csproj" -c Release --nologo
VIRE_DLL="$ROOT/bin/Release/net10.0/vire.dll"
PROOF="$ROOT/tools/VireProof/bin/Release/net10.0/vire-proof.dll"
mkdir -p "$ROOT/data"
dotnet exec "$PROOF" write-pfx "$ROOT/data/pg-tls.pfx" "$ROOT/data/pg-ca.pem" x
openssl x509 -in "$ROOT/data/pg-ca.pem" -outform DER -out "$ROOT/data/pg-ca.der"
python3 - <<'PY'
from pathlib import Path
import hashlib
der = Path("data/pg-ca.der").read_bytes()
print("stub_der_len", len(der))
print("stub_der_head", ",".join(str(b) for b in der[:12]) + ",")
print("stub_der_sha256", hashlib.sha256(der).hexdigest())
print("stub_ep_bytes", ",".join(str(b) for b in hashlib.sha256(der).digest()) + ",")
PY
echo "stub_sig_alg $(openssl x509 -in "$ROOT/data/pg-ca.pem" -noout -text | grep -m1 'Signature Algorithm')"

stub_out="$(mktemp)"
dotnet exec "$PROOF" pg-tls-stub "$ROOT/data/pg-tls.pfx" x >"$stub_out" 2>&1 &
stub_pid=$!
cleanup() { kill "$stub_pid" >/dev/null 2>&1 || true; }
trap cleanup EXIT
port=""
for _ in $(seq 1 80); do
  if grep -q "listening on 127.0.0.1:" "$stub_out"; then
    port="$(grep "listening on 127.0.0.1:" "$stub_out" | head -1 | sed 's/.*://')"
    break
  fi
  sleep 0.05
done
if [[ -z "$port" ]]; then
  cat "$stub_out" >&2
  exit 1
fi
echo "pg_loopback_stub 127.0.0.1:$port"

python3 - <<PY
from pathlib import Path
root = Path("$ROOT")
lib = (root / "src/rt-pg.vire").read_text()
guest = """
define main
  let port be %s
  let h be connect with "127.0.0.1", port
  send with h, (pg_ssl_request)
  let reply be recv with h, 1
  say "ssl_reply " + reply
  tls_wrap with h, "localhost", "data/pg-ca.pem", 1
  say "wrap ok"
  try
    let der be tls_peer_cert with h
    let tab be pg_tab
    say "der_len " + (text with (length with der))
    let i be 0
    let head be ""
    while i < 12
      let head be head + (text with (find with tab, (der at i))) + ","
      let i be i + 1
    end
    say "der_head " + head
    let ep be tls_end_point with der
    say "ep_len " + (text with (length with ep))
    let i be 0
    let eps be ""
    while i < (length with ep)
      let eps be eps + (text with (find with tab, (ep at i))) + ","
      let i be i + 1
    end
    say "ep_bytes " + eps
  miss problem
    say "cbind_dump_fail " + problem
    halt with 1
  end
end
""" % ($port,)
(root / "pg-tls-cbind-dump.vire").write_text(lib + "\n" + guest)
(root / "data/pg-tls-cbind-dump.vire").write_text(lib + "\n" + guest)
PY

export VIRE_BUDGET=5000000
echo "=== HOST DUMP ==="
set +e
host_out="$(dotnet exec "$VIRE_DLL" pg-tls-cbind-dump.vire)"
host_code=$?
set -e
printf '%s\n' "$host_out"
echo "host_dump_exit $host_code"

saved_budget="${VIRE_BUDGET:-}"
unset VIRE_BUDGET || true
set +e
dotnet exec "$VIRE_DLL" --compiler compile-native.vire data/pg-tls-cbind-dump.vire data/pg-tls-cbind-dump.hex elf
compile_code=$?
if [[ -n "$saved_budget" ]]; then export VIRE_BUDGET="$saved_budget"; fi
set -e
if [[ "$compile_code" != "0" ]]; then
  echo "compile dump elf exit $compile_code" >&2
  exit 1
fi
python3 - <<PY
from pathlib import Path
hx = Path("$ROOT/data/pg-tls-cbind-dump.hex").read_text().strip()
Path("$ROOT/data/pg-tls-cbind-dump.elf").write_bytes(bytes.fromhex(hx))
PY
chmod +x "$ROOT/data/pg-tls-cbind-dump.elf"
echo "=== ELF DUMP ==="
set +e
elf_out="$("$ROOT/data/pg-tls-cbind-dump.elf")"
elf_code=$?
set -e
printf '%s\n' "$elf_out"
echo "elf_dump_exit $elf_code"
