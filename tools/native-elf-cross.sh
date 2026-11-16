#!/usr/bin/env bash
# Ubuntu: Linux-built ELF hello must match the Windows-PE-compiler hello and run.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
export PATH="${HOME}/.dotnet:${PATH:-}"
export DOTNET_ROOT="${DOTNET_ROOT:-$HOME/.dotnet}"
export VIRE_HEADLESS=1
unset VIRE_BUDGET || true
AFTER_SHA="$(git rev-parse HEAD)"
echo "pass_after_sha $AFTER_SHA"
WIN_HEX="${1:-$ROOT/data/win-linux-hello.hex}"
if [[ ! -f "$WIN_HEX" ]]; then
  echo "missing windows hello hex $WIN_HEX"
  exit 1
fi
bash "$ROOT/tools/stage-compiler-src.sh"
dotnet build vire.csproj -c Release --nologo
mkdir -p data
cp guest-hello.vire data/guest-hello.vire

hex_to_bin() {
  python3 - "$1" "$2" <<'PY'
import pathlib, sys
pathlib.Path(sys.argv[2]).write_bytes(bytes.fromhex(pathlib.Path(sys.argv[1]).read_text().strip()))
PY
}

rm -f data/gen1.hex data/linux-hello.hex
dotnet exec bin/Release/net10.0/vire.dll --compiler compile-native.vire data/compile-native.vire data/gen1.hex
hex_to_bin data/gen1.hex data/gen1.elf
chmod +x data/gen1.elf
./data/gen1.elf data/guest-hello.vire data/linux-hello.hex elf
hex_to_bin data/linux-hello.hex data/linux-hello.elf
hex_to_bin "$WIN_HEX" data/win-linux-hello.elf
python3 - <<'PY'
from pathlib import Path
linux = Path("data/linux-hello.elf").read_bytes()
win = Path("data/win-linux-hello.elf").read_bytes()
assert linux[:4] == b"\x7fELF", linux[:4]
assert win[:4] == b"\x7fELF", win[:4]
print("linux_hello_bytes", len(linux))
print("win_hello_bytes", len(win))
if linux != win:
    print("cross_target_hello_bytes_differ")
    raise SystemExit(1)
print("cross_target_hello_bytes_identical")
PY
chmod +x data/linux-hello.elf data/win-linux-hello.elf
OUT_L="$(./data/linux-hello.elf)"
OUT_W="$(./data/win-linux-hello.elf)"
echo "linux_hello_out $OUT_L"
echo "win_hello_out $OUT_W"
if [[ "$OUT_L" != "hello from stage" || "$OUT_W" != "hello from stage" ]]; then
  echo "cross target hello stdout mismatch"
  exit 1
fi
echo "PASS_AFTER at $AFTER_SHA windows PE gen1 ELF hello matches Linux and runs"
echo "native elf cross-target ok"
