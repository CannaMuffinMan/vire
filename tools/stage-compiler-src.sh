#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
mkdir -p "$ROOT/data/src"
cp "$ROOT/compile-native.vire" "$ROOT/data/compile-native.vire"
cp "$ROOT/src/asm.vire" "$ROOT/src/pe.vire" "$ROOT/src/rt.vire" "$ROOT/src/rt-more.vire" "$ROOT/data/src/"
python3 - <<PY
import hashlib, os
root = "$ROOT"
pairs = [
    ("compile-native.vire", "data/compile-native.vire"),
    ("src/asm.vire", "data/src/asm.vire"),
    ("src/pe.vire", "data/src/pe.vire"),
    ("src/rt.vire", "data/src/rt.vire"),
    ("src/rt-more.vire", "data/src/rt-more.vire"),
]
for a, b in pairs:
    ha = hashlib.sha256(open(os.path.join(root, a), "rb").read()).hexdigest()
    hb = hashlib.sha256(open(os.path.join(root, b), "rb").read()).hexdigest()
    if ha != hb:
        raise SystemExit("stage mismatch " + a + " " + b)
    print("staged", b, ha[:16])
print("stage-compiler-src ok")
PY
