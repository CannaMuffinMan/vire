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

sha_pw=$(dotnet exec "$dll" tests/kdf-sha-password.vire)
bcrypt_vec='$2b$04$......................LAtw7/ohmmBAhnXqmkuIz83Rl5Qdjhm'
if [[ "$sha_pw" == "$bcrypt_vec" ]]; then
  echo "SHA-256 unexpectedly equals bcrypt vector" >&2
  exit 1
fi
if git show d89edb29743c580613816d19cb1e7c749bce71e6:src/rt-crypto.vire | grep -q bcrypt_; then
  echo "base rt-crypto already has bcrypt" >&2
  exit 1
fi
echo "FAIL_BEFORE at d89edb29743c580613816d19cb1e7c749bce71e6: canonical bcrypt vector does not verify (no KDF / SHA-256 $sha_pw != $bcrypt_vec)"

start=$(date +%s)
kdf=$(dotnet exec "$dll" kdf-prove.vire)
end=$(date +%s)
echo "$kdf"
echo "kdf_host_sec $((end-start))"
echo "$kdf" | grep -q "KDF PROVE pass"
echo "$kdf" | grep -q "BCRYPT password cost4 PASS"
echo "$kdf" | grep -q "BCRYPT empty cost4 PASS"
echo "$kdf" | grep -q "BCRYPT utf8 cost4 PASS"
echo "$kdf" | grep -q "BCRYPT 72-byte truncation PASS"
echo "$kdf" | grep -q "BCRYPT wrong password REJECT"
echo "$kdf" | grep -q "not a CPU timing barrier"
echo "PASS_AFTER host bcrypt outputs match published \$2b\$04 vectors"
echo "kdf host prove ok"
