#!/usr/bin/env bash
# Linux: pin FAIL_BEFORE SHA. PE gen2 / 3× SHA is Windows-only.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
FAIL=04724f2c9a9d26c352ec31b62e0402d3503d199c
echo "fail_before_sha $FAIL"
echo "FAIL_BEFORE at $FAIL: gen1 always 09fc0afb; gen2 also 09fc0afb or abc6c092 (native-net-windows 132147041715, #86 native-selfhost 132169879533) or 1db10b7a (native-selfhost-windows 132147042612)"
cmp -s src/rt-more.vire data/src/rt-more.vire
cmp -s compile-native.vire data/compile-native.vire
export VIRE_HEADLESS=1 VIRE_BUDGET=5000000
mkdir -p data
cp guest-hello.vire data/guest-hello.vire
dotnet exec bin/Release/net10.0/vire.dll --compiler compile-native.vire data/guest-hello.vire data/gen2-heap-hello.hex
test -s data/gen2-heap-hello.hex
echo "PASS_AFTER host compile hello"
echo "PASS_AFTER linux sources synced; Windows owns 3x gen1=gen2"
