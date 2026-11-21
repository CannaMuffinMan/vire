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

hex_to_bin() {
  python3 - "$1" "$2" <<'PY'
import pathlib, sys
pathlib.Path(sys.argv[2]).write_bytes(bytes.fromhex(pathlib.Path(sys.argv[1]).read_text().strip()))
PY
}

BASE_SHA=d095972ed61474e8e852e391b984e4221dfe6c8f
AFTER_SHA="$(git rev-parse HEAD)"
if git show "$BASE_SHA:src/rt-crypto.vire" | grep -q pbkdf2_sha256; then
  echo "base already has pbkdf2" >&2
  exit 1
fi
echo "FAIL_BEFORE at $BASE_SHA: RFC 7914 section 11 PBKDF2-HMAC-SHA256 is absent"

out=$(dotnet exec "$dll" pbkdf2-prove.vire)
echo "$out"
echo "$out" | grep -q "PBKDF2 PROVE pass"
echo "$out" | grep -q "RFC7914 11 c=1 PASS"
echo "$out" | grep -q "RFC6070-SHA256 c=4096 PASS"
echo "$out" | grep -q "RFC7914 11 c=80000 PASS"
echo "$out" | grep -q "FCG login verify PASS"

mkdir -p data/src
cp src/rt-crypto.vire data/src/rt-crypto.vire
cp pbkdf2-prove.vire data/pbkdf2-prove.vire
rm -f data/pbkdf2-prove.hex
dotnet exec "$dll" --compiler compile-native.vire data/pbkdf2-prove.vire data/pbkdf2-prove.hex
hex_to_bin data/pbkdf2-prove.hex data/pbkdf2-prove.elf
python3 - <<'PY'
from pathlib import Path
b = Path("data/pbkdf2-prove.elf").read_bytes()
assert b[:4] == b"\x7fELF", b[:4]
print("elf_magic", b[:4])
PY
chmod +x data/pbkdf2-prove.elf
native=$(./data/pbkdf2-prove.elf)
echo "$native"
host_n=$(printf '%s' "$out" | tr -d '\r')
nat_n=$(printf '%s' "$native" | tr -d '\r')
if [[ "$host_n" != "$nat_n" ]]; then
  echo "HOST_ELF_MISMATCH" >&2
  exit 1
fi
echo "PASS_AFTER at $AFTER_SHA host interpreter stdout equals native ELF for RFC7914 c=1 and c=80000"
echo "caps unchanged: arena 32MB / list 100000 / steps 5M / while 1M"
echo "pbkdf2 linux prove ok"
