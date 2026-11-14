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

run_textcat() {
  local keep="$1"
  python3 - "$ROOT/tests/native/gc-textcat-nearfull.vire" "$WORKDIR/textcat-$keep.vire" "$keep" <<'PY'
import sys
src, dst, keep = sys.argv[1], sys.argv[2], sys.argv[3]
text = open(src, encoding="utf-8").read().replace("while n < 470", f"while n < {keep}", 1)
open(dst, "w", encoding="utf-8").write(text)
PY
  VIRE_BUDGET= "${VIRE[@]}" --compiler compile-native.vire "data/native-gc-kind/textcat-$keep.vire" "data/native-gc-kind/textcat-$keep.hex"
  local out
  out="$(python3 "$ROOT/tools/native-pe-emu.py" "$WORKDIR/textcat-$keep.hex" 0 || true)"
  echo "$out"
  python3 - "$keep" "$out" <<'PY'
import sys
keep, out = sys.argv[1], sys.argv[2]
faults = ""
for line in out.splitlines():
    if line.startswith("FAULTS "):
        faults = line[len("FAULTS "):]
body = []
on = False
for line in out.splitlines():
    if line.strip() == "STDOUT_BEGIN":
        on = True
        continue
    if line.strip() == "STDOUT_END":
        on = False
        continue
    if on:
        body.append(line.replace("\r", ""))
text = "\n".join(body)
if faults not in ("[]",):
    raise SystemExit(f"textcat keep={keep} crashed faults={faults}")
if "textcat corrupt" in text:
    raise SystemExit(f"textcat keep={keep} corrupt")
if "textcat ok" in text or "out of memory" in text:
    print(f"textcat keep={keep} fail-closed ok")
    raise SystemExit(0)
raise SystemExit(f"textcat keep={keep} unexpected out={text!r} faults={faults}")
PY
}

# Full 300..490 is the Windows PE proof (native speed). Unicorn samples the
# crash keeps plus a fitting keep.
for keep in 300 470 478 482 490; do
  run_textcat "$keep"
done
echo "native gc-kind check ok"
