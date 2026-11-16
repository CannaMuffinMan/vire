#!/usr/bin/env bash
# Linux native self-host: host gen1 ELF, gen1 hello, gen1 gen2, sha256 match.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
export PATH="${HOME}/.dotnet:${PATH:-}"
export DOTNET_ROOT="${DOTNET_ROOT:-$HOME/.dotnet}"
export VIRE_HEADLESS=1
unset VIRE_BUDGET || true
AFTER_SHA="$(git rev-parse HEAD)"
echo "pass_after_sha $AFTER_SHA"
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

rm -f data/gen1.hex
dotnet exec bin/Release/net10.0/vire.dll --compiler compile-native.vire data/compile-native.vire data/gen1.hex
hex_to_bin data/gen1.hex data/gen1.elf
chmod +x data/gen1.elf
echo "gen1_exe_bytes $(wc -c < data/gen1.elf)"
python3 - <<'PY'
from pathlib import Path
b = Path("data/gen1.elf").read_bytes()
assert b[:4] == b"\x7fELF"
print("gen1_elf_ok")
PY

rm -f data/gen1-hello.hex
./data/gen1.elf data/guest-hello.vire data/gen1-hello.hex
hex_to_bin data/gen1-hello.hex data/gen1-hello.elf
chmod +x data/gen1-hello.elf
HELLO="$(./data/gen1-hello.elf)"
echo "$HELLO"
if [[ "$HELLO" != "hello from stage" ]]; then
  echo "gen1 hello stdout mismatch"
  exit 1
fi
echo "step_gen1_hello ok"

rm -f data/gen2.hex
./data/gen1.elf data/compile-native.vire data/gen2.hex
H1="$(sha256sum data/gen1.hex | awk '{print $1}')"
H2="$(sha256sum data/gen2.hex | awk '{print $1}')"
echo "gen1_sha256 $H1"
echo "gen2_sha256 $H2"
if [[ "$H1" != "$H2" ]]; then
  echo "gen1/gen2 SHA-256 differ"
  exit 1
fi
echo "PASS_AFTER at $AFTER_SHA sha256(gen1)==sha256(gen2)"
echo "native elf selfhost ok"
