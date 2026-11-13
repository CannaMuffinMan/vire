#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
mkdir -p "$ROOT/data/src"
cp "$ROOT/compile-native.vire" "$ROOT/data/compile-native.vire"
cp "$ROOT/src/asm.vire" "$ROOT/src/pe.vire" "$ROOT/src/rt.vire" "$ROOT/src/rt-more.vire" "$ROOT/src/rt-net.vire" \
  "$ROOT/src/rt-tls.vire" \
  "$ROOT/src/rt-tls-blob.txt" "$ROOT/src/rt-tls-pins.txt" "$ROOT/src/rt-tls-fixes.txt" \
  "$ROOT/src/rt-tls-names.txt" \
  "$ROOT/src/rt-net-blob.txt" "$ROOT/src/rt-net-pins.txt" "$ROOT/src/rt-net-fixes.txt" \
  "$ROOT/src/rt-net-json-blob.txt" "$ROOT/src/rt-net-json-pins.txt" "$ROOT/src/rt-net-json-fixes.txt" \
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
    ("src/rt-tls.vire", "data/src/rt-tls.vire"),
    ("src/rt-tls-blob.txt", "data/src/rt-tls-blob.txt"),
    ("src/rt-tls-pins.txt", "data/src/rt-tls-pins.txt"),
    ("src/rt-tls-fixes.txt", "data/src/rt-tls-fixes.txt"),
    ("src/rt-tls-names.txt", "data/src/rt-tls-names.txt"),
    ("src/rt-net-blob.txt", "data/src/rt-net-blob.txt"),
    ("src/rt-net-pins.txt", "data/src/rt-net-pins.txt"),
    ("src/rt-net-fixes.txt", "data/src/rt-net-fixes.txt"),
    ("src/rt-net-json-blob.txt", "data/src/rt-net-json-blob.txt"),
    ("src/rt-net-json-pins.txt", "data/src/rt-net-json-pins.txt"),
    ("src/rt-net-json-fixes.txt", "data/src/rt-net-json-fixes.txt"),
]
for a, b in pairs:
    ha = hashlib.sha256(open(os.path.join(root, a), "rb").read()).hexdigest()
    hb = hashlib.sha256(open(os.path.join(root, b), "rb").read()).hexdigest()
    if ha != hb:
        raise SystemExit("stage mismatch " + a + " " + b)
    print("staged", b, ha[:16])
print("stage-compiler-src ok")
PY
