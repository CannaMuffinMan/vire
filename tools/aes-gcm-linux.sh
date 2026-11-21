#!/usr/bin/env bash
# Host interpreter vs gen1 native ELF for AES-256-GCM KATs.
# Does not raise 32MB arena, 100000 list cap, or 5M steps.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
export PATH="${HOME}/.dotnet:${PATH:-}"
export DOTNET_ROOT="${DOTNET_ROOT:-$HOME/.dotnet}"
export VIRE_HEADLESS=1
export VIRE_BUDGET=5000000
TABLE_SHA="${AES_GCM_FAIL_BEFORE_SHA:-04ea5186c6ed3ce35451df318e29a1db9b9eabe8}"
AFTER_SHA="$(git rev-parse HEAD)"
echo "fail_before_sha $TABLE_SHA"
echo "pass_after_sha $AFTER_SHA"
BEFORE_SRC="$(git show "${TABLE_SHA}:src/rt-aes.vire")"
if [[ "$BEFORE_SRC" != *"sbox at"* ]]; then
  echo "FAIL_BEFORE expected table lookup at $TABLE_SHA"
  exit 1
fi
if [[ "$BEFORE_SRC" != *"if d >= 256"* ]]; then
  echo "FAIL_BEFORE expected xtime branch at $TABLE_SHA"
  exit 1
fi
if [[ "$BEFORE_SRC" != *"if flag == 1"* ]]; then
  echo "FAIL_BEFORE expected GHASH bit skip at $TABLE_SHA"
  exit 1
fi
echo "FAIL_BEFORE at $TABLE_SHA: S-box table lookup, xtime branch, GHASH bit skip present"

hex_to_bin() {
  python3 - "$1" "$2" <<'PY'
import pathlib, sys
pathlib.Path(sys.argv[2]).write_bytes(bytes.fromhex(pathlib.Path(sys.argv[1]).read_text().strip()))
PY
}

dotnet build vire.csproj -c Release --nologo
HOST_OUT="$(dotnet exec bin/Release/net10.0/vire.dll aes-gcm-prove.vire)"
HOST_CODE=$?
echo "$HOST_OUT"
echo "aes_gcm_host_exit $HOST_CODE"
if [[ "$HOST_CODE" -ne 0 ]]; then
  echo "host aes-gcm-prove failed"
  exit 1
fi
if [[ "$HOST_OUT" != *"AES-GCM PROVE pass"* ]]; then
  echo "host missing AES-GCM PROVE pass"
  exit 1
fi

unset VIRE_BUDGET || true
mkdir -p data
python3 - <<'PY'
from pathlib import Path
lib = Path("src/rt-aes.vire").read_text()
prove = Path("aes-gcm-prove.vire").read_text()
if prove.startswith('use "src/rt-aes.vire"'):
    prove = prove.split("\n", 1)[1]
Path("data/aes-gcm-prove.vire").write_text(lib + "\n" + prove)
PY
rm -f data/aes-gcm-prove.hex data/aes-gcm-prove.elf
dotnet exec bin/Release/net10.0/vire.dll --compiler compile-native.vire data/aes-gcm-prove.vire data/aes-gcm-prove.hex
hex_to_bin data/aes-gcm-prove.hex data/aes-gcm-prove.elf
python3 - <<'PY'
from pathlib import Path
b = Path("data/aes-gcm-prove.elf").read_bytes()
assert b[:4] == b"\x7fELF", b[:4]
print("elf_magic", b[:4])
print("elf_bytes", len(b))
PY
chmod +x data/aes-gcm-prove.elf
ELF_OUT="$(./data/aes-gcm-prove.elf)"
ELF_CODE=$?
echo "$ELF_OUT"
echo "aes_gcm_elf_exit $ELF_CODE"
if [[ "$ELF_CODE" -ne 0 ]]; then
  echo "ELF aes-gcm-prove failed"
  exit 1
fi
HOST_NORM="$(printf '%s' "$HOST_OUT" | tr -d '\r')"
ELF_NORM="$(printf '%s' "$ELF_OUT" | tr -d '\r')"
if [[ "$HOST_NORM" != "$ELF_NORM" ]]; then
  echo "HOST_ELF_MISMATCH"
  exit 1
fi
AFTER_SRC="$(cat src/rt-aes.vire)"
if [[ "$AFTER_SRC" == *"sbox at"* ]]; then
  echo "PASS_AFTER still has sbox at"
  exit 1
fi
if [[ "$AFTER_SRC" == *"if flag == 1"* ]]; then
  echo "PASS_AFTER still has GHASH skip"
  exit 1
fi
echo "PASS_AFTER at $AFTER_SHA host and gen1 ELF AES-GCM outputs identical; no secret sbox index / GHASH skip in source"
echo "aes gcm linux prove ok"
