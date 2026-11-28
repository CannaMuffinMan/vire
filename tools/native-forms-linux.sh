#!/usr/bin/env bash
# Host vs native ELF for tracked data/native-forms try-miss.vire and for-list.vire.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
export PATH="${HOME}/.dotnet:${PATH:-}"
export DOTNET_ROOT="${DOTNET_ROOT:-$HOME/.dotnet}"
export VIRE_HEADLESS=1
unset VIRE_BUDGET || true

AFTER_SHA="$(git rev-parse HEAD)"
BEFORE_SHA="6693e0e5d78c9df775d0531a39a14a574239cfac"
VIRE_DLL="$ROOT/bin/Release/net10.0/vire.dll"

python3 - <<'PY'
from pathlib import Path
rt = Path("src/rt.vire").read_text()
assert "33554432" in rt
cs = Path("Vire.cs").read_text()
assert "100000" in cs
assert "5000000" in cs
print("caps_src_ok arena=33554432 list=100000 steps=5000000")
PY

dotnet build vire.csproj -c Release --nologo
bash "$ROOT/tools/stage-compiler-src.sh"

echo "=== FAIL_BEFORE at $BEFORE_SHA ==="
if git cat-file -e "$BEFORE_SHA:data/native-forms/try-miss.vire" 2>/dev/null; then
  echo "FAIL_BEFORE unexpectedly had try-miss.vire"
  exit 1
fi
echo "FAIL_BEFORE at $BEFORE_SHA missing data/native-forms/try-miss.vire and for-list.vire"

hex_to_bin() {
  python3 - "$1" "$2" <<'PY'
import pathlib, sys
pathlib.Path(sys.argv[2]).write_bytes(bytes.fromhex(pathlib.Path(sys.argv[1]).read_text().strip()))
PY
}

for program in try-miss for-list; do
  src="data/native-forms/${program}.vire"
  hex="data/native-forms/${program}.hex"
  elf="data/native-forms/${program}.elf"
  rm -f "$hex" "$elf"
  dotnet exec "$VIRE_DLL" --compiler compile-native.vire "$src" "$hex"
  hex_to_bin "$hex" "$elf"
  chmod +x "$elf"
  HOST="$(dotnet exec "$VIRE_DLL" "$src")"
  NAT="$("./$elf")"
  echo "host_$program $HOST"
  echo "native_$program $NAT"
  if [[ "$HOST" != "$NAT" ]]; then
    echo "HOST_NATIVE_MISMATCH $program"
    exit 3
  fi
  echo "HOST_NATIVE_MATCH $program"
done

echo "PASS_AFTER at $AFTER_SHA"
echo "native forms ok"
