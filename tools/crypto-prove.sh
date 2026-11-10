#!/usr/bin/env bash
set -euo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$root"
export VIRE_BUDGET=5000000
export VIRE_HEADLESS=1
dll="$root/bin/Release/net10.0/vire.dll"
if [[ ! -f "$dll" ]]; then
  echo "missing $dll" >&2
  exit 1
fi
start=$(date +%s)
out=$(dotnet exec "$dll" crypto-prove.vire)
end=$(date +%s)
echo "$out"
echo "crypto_host_sec $((end-start))"
echo "$out" | grep -q "CRYPTO PROVE pass"
echo "$out" | grep -q "FIPS empty guest PASS"
echo "$out" | grep -q "FIPS abc guest PASS"
echo "$out" | grep -q "FIPS 448 guest PASS"
echo "$out" | grep -q "RFC4231 1 PASS"
echo "$out" | grep -q "RFC4231 7 PASS"
echo "$out" | grep -q "RFC4648 foobar PASS"
echo "$out" | grep -q "JWT hs256 jwt.io PASS"
echo "$out" | grep -q "ADV alg none REJECT"
echo "$out" | grep -q "ADV alg HS512 REJECT"
echo "$out" | grep -q "ADV alg case REJECT"
echo "$out" | grep -q "ADV extra REJECT"
echo "$out" | grep -q "ADV missing REJECT"
echo "$out" | grep -q "ADV oversized REJECT"
echo "$out" | grep -q "ADV b64 REJECT"
echo "$out" | grep -q "ADV siglen REJECT"
echo "$out" | grep -q "ADV tamper REJECT"
echo "$out" | grep -q "ADV exp REJECT"
echo "crypto host prove ok"
