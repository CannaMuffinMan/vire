#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
mkdir -p "$ROOT/data/src"
cp "$ROOT/compile-native.vire" "$ROOT/data/compile-native.vire"
cp "$ROOT/src/asm.vire" "$ROOT/src/pe.vire" "$ROOT/src/rt.vire" "$ROOT/src/rt-more.vire" "$ROOT/src/rt-net.vire" \
  "$ROOT/src/rt-net-blob.hex" "$ROOT/src/rt-net-pins.hex" "$ROOT/src/rt-net-fixes.hex" \
  "$ROOT/src/rt-net-json-blob.hex" "$ROOT/src/rt-net-json-pins.hex" "$ROOT/src/rt-net-json-fixes.hex" \
  "$ROOT/data/src/"
python3 - <<PY
import hashlib, os
root = "$ROOT"
pairs = [
    ("compile-native.vire", "data/compile-native.vire"),
    ("src/asm.vire", "data/src/asm.vire"),
    ("src/pe.vire", "data/src/pe.vire"),
    ("src/rt.vire", "data/src/rt.vire"),
    ("src/rt-more.vire", "data/src/rt-more.vire"),
    ("src/rt-net.vire", "data/src/rt-net.vire"),
    ("src/rt-net-blob.hex", "data/src/rt-net-blob.hex"),
    ("src/rt-net-pins.hex", "data/src/rt-net-pins.hex"),
    ("src/rt-net-fixes.hex", "data/src/rt-net-fixes.hex"),
    ("src/rt-net-json-blob.hex", "data/src/rt-net-json-blob.hex"),
    ("src/rt-net-json-pins.hex", "data/src/rt-net-json-pins.hex"),
    ("src/rt-net-json-fixes.hex", "data/src/rt-net-json-fixes.hex"),
]
for a, b in pairs:
    ha = hashlib.sha256(open(os.path.join(root, a), "rb").read()).hexdigest()
    hb = hashlib.sha256(open(os.path.join(root, b), "rb").read()).hexdigest()
    if ha != hb:
        raise SystemExit("stage mismatch " + a + " " + b)
    print("staged", b, ha[:16])
print("stage-compiler-src ok")
PY
