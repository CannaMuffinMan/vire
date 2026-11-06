#!/usr/bin/env bash
# Linux-side invariants for the native 32MB arena and intern table.
# Does not run a Windows PE. That proof is tools/native-selfhost-proof.ps1.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
rt="$ROOT/src/rt.vire"
more="$ROOT/src/rt-more.vire"
pe="$ROOT/src/pe.vire"
native="$ROOT/compile-native.vire"
for n in 33554432 intern_fill at_text_alloc at_text_push; do
  true
done
grep -q 'emitU32 with image, 33554432' "$rt"
grep -q 'emitU32 with image, 33554432' "$more"
grep -q 'poke32 with head, 224, 33554432' "$pe"
grep -q 'poke32 with head, 240, 33554432' "$pe"
grep -q 'pin with labels, "intern_fill", image' "$rt"
grep -q 'emitU32 with image, 128' "$rt"
grep -q 'emitU32 with image, 4096' "$rt"
grep -q 'pin with labels, "at_text_alloc", image' "$more"
grep -q 'use "src/pe.vire"' "$native"
! grep -q '268435456' "$rt" "$more" "$pe"
! grep -q 'use "data/src/' "$native"
echo "native arena check ok"
