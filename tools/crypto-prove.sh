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
echo "$out" | grep -q "ADV leftover REJECT"
echo "$out" | grep -q "ADV nested alg REJECT"
echo "$out" | grep -q "ADV crit REJECT"
echo "$out" | grep -q "ADV nbf REJECT"
echo "$out" | grep -q "ADV exp equal REJECT"
echo "$out" | grep -q "UTF8 ascii_text REJECT"
echo "$out" | grep -q "UTF8 text PASS"
echo "$out" | grep -q "JWT utf8 PASS"
echo "$out" | grep -q "ADV exp ms REJECT"
echo "$out" | grep -q "JWT exp ms live PASS"
echo "$out" | grep -q "ADV exp safe equal REJECT"
echo "$out" | grep -q "ADV exp 17 digit REJECT"
echo "$out" | grep -q "CT eq residual not a CPU timing barrier"
echo "crypto host prove ok"
