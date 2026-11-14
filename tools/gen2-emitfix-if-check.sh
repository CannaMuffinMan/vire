#!/usr/bin/env bash
# Linux: pin FAIL_BEFORE SHA. PE gen2 is Windows-only.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
FAIL=c0e82e009be51f763d410d58238fd67dedd3e8ff
echo "fail_before_sha $FAIL"
echo "FAIL_BEFORE at $FAIL: extra emitFix if without payload-zero alloc crashed gen2."
grep -q 'begins with name, "rt_ws"' compile-native.vire
grep -q 'try_zero_loop' src/rt-more.vire
if grep -q 'use "src/rt-ws.vire"' compile-native.vire; then
  echo "compile-native must not use rt-ws.vire on selfhost" >&2
  exit 1
fi
cmp -s src/rt-more.vire data/src/rt-more.vire
cmp -s compile-native.vire data/compile-native.vire
echo "PASS_AFTER linux sources synced; extra emitFix if + payload zero; Windows owns FAIL_BEFORE crash and gen1=gen2"
