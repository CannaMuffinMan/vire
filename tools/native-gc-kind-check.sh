#!/usr/bin/env bash
# Host compile-native + Unicorn: gc-kind-stress and gc-churn.
# gc-churn needs a high insn cap; bump after a successful collection is << 32MB.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
export VIRE_HEADLESS=1
python3 -m pip install --user -q unicorn
if [[ -f "$ROOT/bin/Release/net10.0/vire.dll" ]]; then
  VIRE=(dotnet exec "$ROOT/bin/Release/net10.0/vire.dll")
else
  VIRE=(dotnet run --no-build -c Release --project "$ROOT/vire.csproj" --)
fi
WORKDIR="$ROOT/data/native-gc-kind"
rm -rf "$WORKDIR"
mkdir -p "$WORKDIR"

run_guest() {
  local name="$1"
  local src="$2"
  local count="$3"
  local want="$4"
  local maxbump="$5"
  cp "$src" "$WORKDIR/$name.vire"
  VIRE_BUDGET= "${VIRE[@]}" --compiler compile-native.vire "data/native-gc-kind/$name.vire" "data/native-gc-kind/$name.hex"
  local out
  out="$(python3 "$ROOT/tools/native-pe-emu.py" "$WORKDIR/$name.hex" "$count")"
  echo "$out"
  echo "$out" | grep -q 'EXIT 0'
  echo "$out" | grep -q 'FAULTS \[\]'
  printf '%s\n' "$out" | awk '/STDOUT_BEGIN/{p=1;next} /STDOUT_END/{p=0} p' | tr -d '\r' | grep -qx "$want"
  local bump
  bump="$(printf '%s\n' "$out" | awk '/HEAP_BUMP/{print $2}')"
  python3 - "$bump" "$maxbump" "$name" <<'PY'
import sys
bump = int(sys.argv[1], 16)
maxb = int(sys.argv[2], 16)
name = sys.argv[3]
if bump > maxb:
    raise SystemExit(f"{name} HEAP_BUMP {hex(bump)} exceeds {hex(maxb)}")
print(f"{name} HEAP_BUMP {hex(bump)} <= {hex(maxb)}")
PY
}

run_guest gc-kind-stress "$ROOT/tests/native/gc-kind-stress.vire" 200000000 "gc-kind-stress ok" 0x200000
echo "native gc-kind check ok"
