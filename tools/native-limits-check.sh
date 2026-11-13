#!/usr/bin/env bash
# FAIL_BEFORE / PASS_AFTER for native implementation limits (Linux host compile).
set -euo pipefail
Root=$(cd "$(dirname "$0")/.." && pwd)
cd "$Root"
export VIRE_BUDGET=5000000 VIRE_HEADLESS=1
VireDll="$Root/bin/Release/net10.0/vire.dll"
if [[ ! -f "$VireDll" ]]; then
  echo "missing $VireDll" >&2
  exit 1
fi
BaseSha=$(git rev-parse origin/native-compiler)
AfterSha=$(git rev-parse HEAD)
mkdir -p data
cp tests/native/deep-expr.vire data/deep-expr.vire
cp tests/native/million-hash.vire data/million-hash.vire
cp tests/native/long-ascii.vire data/long-ascii.vire

git show "$BaseSha:compile-native.vire" > compile-native.base.vire
set +e
before=$(dotnet exec "$VireDll" --compiler compile-native.base.vire data/deep-expr.vire data/deep-expr.base.hex 2>&1)
before_code=$?
set -e
echo "$before"
if [[ "$before" != *"definitions called too deeply"* ]]; then
  echo "FAIL expected base parser to hit MaxCalls 64" >&2
  exit 1
fi
echo "FAIL_BEFORE at $BaseSha: compile-native parseExpr MaxCalls 64 nested (1+(1+…)) depth 20 → definitions called too deeply (exit $before_code)"

host_deep=$(dotnet exec "$VireDll" data/deep-expr.vire)
echo "host_deep $host_deep"
if [[ "$host_deep" != "21" ]]; then
  echo "FAIL host deep-expr want 21" >&2
  exit 1
fi
after=$(dotnet exec "$VireDll" --compiler compile-native.vire data/deep-expr.vire data/deep-expr.hex)
echo "$after"
if [[ "$after" != *"compiled"* ]]; then
  echo "FAIL current compiler should compile deep-expr" >&2
  exit 1
fi

host_mb=$(dotnet exec "$VireDll" data/million-hash.vire)
echo "$host_mb"
if [[ "$host_mb" != *cdc76e5c9914fb9281a1c7e284d73e67f1809a48a497200e046d39ccc7112cd0* ]]; then
  echo "FAIL host FIPS 1M digest" >&2
  exit 1
fi
mb_comp=$(dotnet exec "$VireDll" --compiler compile-native.vire data/million-hash.vire data/million-hash.hex)
echo "$mb_comp"
if [[ "$mb_comp" != *"compiled"* ]]; then
  echo "FAIL compile million-hash" >&2
  exit 1
fi

host_long=$(dotnet exec "$VireDll" data/long-ascii.vire)
echo "host_long $host_long"
if [[ "$host_long" != "4096" ]]; then
  echo "FAIL host long-ascii" >&2
  exit 1
fi
long_comp=$(dotnet exec "$VireDll" --compiler compile-native.vire data/long-ascii.vire data/long-ascii.hex)
echo "$long_comp"
if [[ "$long_comp" != *"compiled"* ]]; then
  echo "FAIL compile long-ascii" >&2
  exit 1
fi

echo "PASS_AFTER at $AfterSha: host compile-native compiles deep-expr (20 nested +), FIPS 1M SHA, 4096-char ASCII literal; host deep-expr stdout=$host_deep"
echo "native limits linux check ok"
rm -f compile-native.base.vire
