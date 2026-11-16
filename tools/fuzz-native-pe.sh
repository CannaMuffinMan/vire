#!/usr/bin/env bash
# Bounded native PE fuzz on Linux via Unicorn. Compiles a few mutated guests
# with the host compile-native (not an outside compiler).
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
export VIRE_HEADLESS=1
VIRE_DLL="$ROOT/bin/Release/net10.0/vire.dll"
if [[ ! -f "$VIRE_DLL" ]]; then
  dotnet build "$ROOT/vire.csproj" -c Release
fi
python3 -m pip install --user -q unicorn
WORKDIR="$ROOT/data/fuzz-native"
rm -rf "$WORKDIR"
mkdir -p "$WORKDIR"
N="${VIRE_FUZZ_NATIVE_ITERS:-4}"
SEEDS=(
  "$ROOT/tests/native/hello-stage.vire"
  "$ROOT/tests/fuzz/corpus/hello.vire"
  "$ROOT/tests/fuzz/corpus/grammar-builtins.vire"
  "$ROOT/tests/fuzz/corpus/grammar-lists.vire"
  "$ROOT/tests/fuzz/corpus/loop.vire"
  "$ROOT/guest-hello.vire"
)
ok=0
fail=0
start=$(date +%s)
budget="${VIRE_FUZZ_NATIVE_SECONDS:-240}"
for i in $(seq 0 $((N - 1))); do
  now=$(date +%s)
  if (( now - start > budget )); then
    echo "native pe fuzz time budget $budget s reached after $i"
    break
  fi
  seed="${SEEDS[$((i % ${#SEEDS[@]}))]}"
  guest="$WORKDIR/g$i.vire"
  python3 - "$seed" "$guest" "$i" <<'PY'
import sys
src = open(sys.argv[1], encoding="utf-8", errors="replace").read()
idx = int(sys.argv[3])
# Deterministic mutate: flip a comment or append a say.
if idx % 2 == 0:
    src = src.replace("say", "say", 1)
    src = "~ fuzz " + str(idx) + "\n" + src
else:
    if "end\n" in src:
        src = src.replace("end\n", "  say (length with \"x\")\nend\n", 1)
open(sys.argv[2], "w", encoding="utf-8").write(src)
PY
  rel="data/fuzz-native/g$i.vire"
  hexrel="data/fuzz-native/g$i.hex"
  set +e
  # Linux compile-native defaults to ELF after #78; force PE for Unicorn PE emu.
  VIRE_BUDGET= dotnet exec "$VIRE_DLL" --compiler compile-native.vire "$rel" "$hexrel" pe >"$WORKDIR/g$i.compile.out" 2>"$WORKDIR/g$i.compile.err"
  code=$?
  set -e
  if [[ $code -ne 0 ]]; then
    echo "native compile g$i exit $code (guest error is ok if fail-closed)"
    if grep -q "internal error" "$WORKDIR/g$i.compile.err" "$WORKDIR/g$i.compile.out" 2>/dev/null; then
      echo "SECURITY-ish: internal error compiling $rel" >&2
      mkdir -p tests/fuzz/findings
      cp "$guest" "tests/fuzz/findings/native-compile-g$i.vire"
      fail=$((fail + 1))
    fi
    continue
  fi
  set +e
  out=$(python3 "$ROOT/tools/native-pe-emu.py" "$WORKDIR/g$i.hex")
  emu=$?
  set -e
  echo "$out" | tee "$WORKDIR/g$i.emu.txt"
  if echo "$out" | grep -q "FAULTS \[\]"; then
    ok=$((ok + 1))
  else
    echo "native emu fault g$i" >&2
    mkdir -p tests/fuzz/findings
    cp "$guest" "tests/fuzz/findings/native-emu-g$i.vire"
    fail=$((fail + 1))
  fi
  _=$emu
done
echo "native pe fuzz compiled_ok_or_emu_clean=$ok faults=$fail"
if [[ $fail -ne 0 ]]; then
  echo "native pe fuzz recorded faults; see tests/fuzz/findings (not a silent fix)"
fi
echo "native pe fuzz done"
