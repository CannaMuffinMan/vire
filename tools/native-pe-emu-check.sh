#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
export VIRE_BUDGET="${VIRE_BUDGET:-5000000}"
python3 -m pip install --user -q unicorn
if [[ -f "$ROOT/bin/Release/net10.0/vire.dll" ]]; then
  VIRE=(dotnet exec "$ROOT/bin/Release/net10.0/vire.dll")
else
  VIRE=(dotnet run --no-build -c Release --project "$ROOT/vire.csproj" --)
fi
WORKDIR="$ROOT/data/native-pe-emu"
rm -rf "$WORKDIR"
mkdir -p "$WORKDIR"
cp "$ROOT/tests/native/intern-chars.vire" "$WORKDIR/intern-chars.vire"
cp "$ROOT/tests/native/hello-stage.vire" "$WORKDIR/hello-stage.vire"
VIRE_BUDGET= "${VIRE[@]}" --compiler compile-native.vire data/native-pe-emu/intern-chars.vire data/native-pe-emu/intern-chars.hex pe
out="$(python3 "$ROOT/tools/native-pe-emu.py" "$WORKDIR/intern-chars.hex")"
echo "$out"
echo "$out" | grep -q 'EXIT 0'
echo "$out" | grep -q 'HEAP_SIZE 0x2000000'
echo "$out" | grep -q 'FAULTS \[\]'
printf '%s\n' "$out" | awk '/STDOUT_BEGIN/{p=1;next} /STDOUT_END/{p=0} p' | tr -d '\r' | grep -qx 'A'
printf '%s\n' "$out" | awk '/STDOUT_BEGIN/{p=1;next} /STDOUT_END/{p=0} p' | tr -d '\r' > "$WORKDIR/got.txt"
printf 'A\nb\n9\nAb9\n' > "$WORKDIR/want.txt"
cmp -s "$WORKDIR/got.txt" "$WORKDIR/want.txt"
VIRE_BUDGET= "${VIRE[@]}" --compiler compile-native.vire data/native-pe-emu/hello-stage.vire data/native-pe-emu/hello-stage.hex pe
out="$(python3 "$ROOT/tools/native-pe-emu.py" "$WORKDIR/hello-stage.hex")"
echo "$out"
echo "$out" | grep -q 'EXIT 0'
printf '%s\n' "$out" | awk '/STDOUT_BEGIN/{p=1;next} /STDOUT_END/{p=0} p' | tr -d '\r' > "$WORKDIR/hello.txt"
printf 'hello from stage\n' > "$WORKDIR/hello-want.txt"
cmp -s "$WORKDIR/hello.txt" "$WORKDIR/hello-want.txt"
echo "native pe emu ok"
