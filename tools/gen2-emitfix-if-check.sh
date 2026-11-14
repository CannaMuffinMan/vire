#!/usr/bin/env bash
# Linux: pin FAIL_BEFORE SHA and in-tree fixture. PE gen2 is Windows-only.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
FAIL=103f189e54630f11a127907a84b91faa1b59375c
FIX=tests/native/fixtures/gc-tagged-walk
echo "fail_before_sha $FAIL"
echo "FAIL_BEFORE at $FAIL: same WS compile-native/rt-ws fixture, untagged GC walks treat 33554432 as a heap pointer (job 132251062134 gen1 c31d0598 vs gen2 fccdd69f, mov rcx 0x2000000 vs 0xd4d328)."
test -f "$FIX/rt-ws.vire"
test -f "$FIX/compile-native.vire"
ws=$(sha256sum "$FIX/rt-ws.vire" | awk '{print $1}')
cn=$(sha256sum "$FIX/compile-native.vire" | awk '{print $1}')
test "$ws" = "2a0d152692b18feb9458f6220900081827b3344b748639f603011997e322f2e3"
test "$cn" = "d86df081935e3bce9cbfba3ce1fec79c5aa229336be53ade0569a72d960b07bd"
grep -q 'rt_gc_mark_tagged' src/rt-more.vire
grep -q 'try_zero_loop' src/rt-more.vire
cmp -s src/rt-more.vire data/src/rt-more.vire
cmp -s compile-native.vire data/compile-native.vire
echo "PASS_AFTER linux sources synced; fixture SHAs pinned; Windows owns FAIL_BEFORE diverge and gen1=gen2"
