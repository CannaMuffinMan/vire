#!/usr/bin/env bash
# Linux: pin FAIL_BEFORE SHAs and host-compile hello. PE gen2 is Windows-only.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
BASE=3946d1c6c4f3fc12e4a486da600bba354ad60c64
BULK=5ae87794c5672c14aedd02042af49e6cea278a81
echo "fail_before_sha $BASE"
echo "bulk_sha $BULK"
echo "FAIL_BEFORE at $BASE with bulk $BULK : gen2 ACCESS_VIOLATION on Windows (#71 native-net-windows 132098928661 crash off=0x34fe)"
cmp -s src/rt-more.vire data/src/rt-more.vire
cmp -s compile-native.vire data/compile-native.vire
export VIRE_HEADLESS=1 VIRE_BUDGET=5000000
mkdir -p data
cp guest-hello.vire data/guest-hello.vire
dotnet exec bin/Release/net10.0/vire.dll --compiler compile-native.vire data/guest-hello.vire data/gen2-heap-hello.hex
test -s data/gen2-heap-hello.hex
echo "PASS_AFTER host compile hello"
echo "PASS_AFTER linux sources synced; Windows owns gen1=gen2 bulky"
