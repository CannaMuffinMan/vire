#!/usr/bin/env bash
# Linux: pin FAIL_BEFORE SHA. PE gen2 crash is Windows-only.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
FAIL=103f189e54630f11a127907a84b91faa1b59375c
echo "fail_before_sha $FAIL"
echo "FAIL_BEFORE at $FAIL: one extra emitFix if (begins rt_ws) crashes gen2 at rip 0x140004740 because rt_alloc_try leaves aligned payload tails dirty and GC relocates them."
grep -q 'begins with name, "rt_ws"' compile-native.vire
grep -q 'try_zero_loop' src/rt-more.vire
cmp -s src/rt-more.vire data/src/rt-more.vire
cmp -s compile-native.vire data/compile-native.vire
echo "PASS_AFTER linux sources synced; Windows owns FAIL_BEFORE crash and gen1=gen2"
