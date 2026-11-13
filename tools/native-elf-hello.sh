#!/usr/bin/env bash
# FAIL_BEFORE at native-compiler: host hello hex is PE (MZ), not an ELF that prints hello.
# PASS_AFTER: host-compiled ELF prints "hello from stage" and exits 0 on this Linux.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
export PATH="${HOME}/.dotnet:${PATH:-}"
export DOTNET_ROOT="${DOTNET_ROOT:-$HOME/.dotnet}"
export VIRE_HEADLESS=1
unset VIRE_BUDGET || true
BASE_SHA="${NATIVE_ELF_BASE_SHA:-$(git merge-base HEAD origin/native-compiler 2>/dev/null || git rev-parse HEAD^)}"
AFTER_SHA="$(git rev-parse HEAD)"
echo "fail_before_sha $BASE_SHA"
echo "pass_after_sha $AFTER_SHA"

hex_to_bin() {
  python3 - "$1" "$2" <<'PY'
import pathlib, sys
p = pathlib.Path(sys.argv[1])
raw = p.read_text().strip()
pathlib.Path(sys.argv[2]).write_bytes(bytes.fromhex(raw))
PY
}

WORKDIR="$(mktemp -d)"
cleanup() { rm -rf "$WORKDIR"; }
trap cleanup EXIT
git clone --quiet --no-hardlinks --no-checkout "$ROOT" "$WORKDIR/base"
git -C "$WORKDIR/base" checkout --quiet "$BASE_SHA"
git -C "$WORKDIR/base" rev-parse HEAD | awk '{print "fail_before_checkout "$1}'
dotnet build "$WORKDIR/base/vire.csproj" -c Release --nologo >/tmp/native-elf-fail-before-build.log
mkdir -p "$WORKDIR/base/data"
cp "$WORKDIR/base/guest-hello.vire" "$WORKDIR/base/data/guest-hello.vire"
set +e
(
  cd "$WORKDIR/base"
  dotnet exec bin/Release/net10.0/vire.dll --compiler compile-native.vire data/guest-hello.vire data/guest-hello.hex
) >"$WORKDIR/base-hello.out" 2>&1
BEFORE_CODE=$?
set -e
echo "fail_before_compile_exit $BEFORE_CODE"
if [[ "$BEFORE_CODE" -ne 0 ]]; then
  echo "FAIL_BEFORE at $BASE_SHA host compile of hello failed (expected PE emit, not ELF)"
  cat "$WORKDIR/base-hello.out" || true
  exit 1
fi
hex_to_bin "$WORKDIR/base/data/guest-hello.hex" "$WORKDIR/base-hello.bin"
MAGIC="$(python3 -c "print(open('$WORKDIR/base-hello.bin','rb').read(2).decode('latin1'))")"
echo "fail_before_magic $MAGIC"
if [[ "$MAGIC" != "MZ" ]]; then
  echo "FAIL_BEFORE expected MZ PE at $BASE_SHA"
  exit 1
fi
chmod +x "$WORKDIR/base-hello.bin" || true
set +e
"$WORKDIR/base-hello.bin" >/tmp/native-elf-fail-before-run.out 2>/tmp/native-elf-fail-before-run.err
RUN_CODE=$?
set -e
echo "fail_before_run_exit $RUN_CODE"
if [[ "$RUN_CODE" -eq 0 ]]; then
  echo "FAIL_BEFORE PE unexpectedly ran on Linux"
  exit 1
fi
echo "FAIL_BEFORE at $BASE_SHA hello hex is PE MZ and does not execute as ELF on Linux"

dotnet build "$ROOT/vire.csproj" -c Release --nologo
mkdir -p "$ROOT/data"
cp "$ROOT/guest-hello.vire" "$ROOT/data/guest-hello.vire"
rm -f "$ROOT/data/guest-hello.hex"
dotnet exec "$ROOT/bin/Release/net10.0/vire.dll" --compiler compile-native.vire data/guest-hello.vire data/guest-hello.hex
hex_to_bin "$ROOT/data/guest-hello.hex" "$ROOT/data/guest-hello.elf"
python3 - <<'PY'
from pathlib import Path
b = Path("data/guest-hello.elf").read_bytes()
assert b[:4] == b"\x7fELF", b[:4]
print("elf_magic", b[:4])
print("elf_bytes", len(b))
PY
chmod +x "$ROOT/data/guest-hello.elf"
OUT="$("$ROOT/data/guest-hello.elf")"
CODE=$?
echo "$OUT"
echo "hello_elf_exit $CODE"
if [[ "$CODE" -ne 0 || "$OUT" != "hello from stage" ]]; then
  echo "hello ELF failed"
  exit 1
fi
echo "PASS_AFTER at $AFTER_SHA gen1 ELF prints hello and exits 0"
echo "native elf hello ok"
