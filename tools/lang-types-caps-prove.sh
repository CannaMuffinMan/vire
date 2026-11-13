#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
HEAD_SHA="$(git rev-parse HEAD)"
BASE_SHA="$(git merge-base HEAD origin/native-compiler 2>/dev/null || git rev-parse origin/native-compiler)"
echo "HEAD_SHA $HEAD_SHA"
echo "BASE_SHA $BASE_SHA"

PROBE='can clock
define main
  let n: number be 1
  say n
end
'

fail_before() {
  echo "FAIL_BEFORE at $BASE_SHA: host Load and compile-native reject can/types"
  git checkout --force "$BASE_SHA"
  dotnet build vire.csproj -c Release --nologo
  mkdir -p data
  printf '%s' "$PROBE" > data/lang-probe.vire
  set +e
  dotnet exec bin/Release/net10.0/vire.dll data/lang-probe.vire > data/lang-probe.host.out 2> data/lang-probe.host.err
  host=$?
  dotnet exec bin/Release/net10.0/vire.dll compile-native.vire data/lang-probe.vire data/lang-probe.hex > data/lang-probe.native.out 2> data/lang-probe.native.err
  native=$?
  set -e
  echo "FAIL_BEFORE host_exit $host native_exit $native"
  cat data/lang-probe.host.err || true
  cat data/lang-probe.native.out || true
  if [ "$host" -eq 0 ]; then echo "FAIL_BEFORE host unexpectedly accepted types"; exit 1; fi
  if [ "$native" -eq 0 ]; then echo "FAIL_BEFORE native unexpectedly accepted types"; exit 1; fi
  echo "FAIL_BEFORE ok at $BASE_SHA"
}

pass_after() {
  echo "PASS_AFTER at $HEAD_SHA"
  git checkout --force "$HEAD_SHA"
  dotnet build vire.csproj -c Release --nologo
  dotnet test tests/Vire.Tests/Vire.Tests.csproj -c Release --nologo --filter "FullyQualifiedName~LangTypesCapsTests"
  mkdir -p data
  printf '%s' "$PROBE" > data/lang-probe.vire
  dotnet exec bin/Release/net10.0/vire.dll data/lang-probe.vire
  dotnet exec bin/Release/net10.0/vire.dll compile-native.vire data/lang-probe.vire data/lang-probe.hex | tee data/lang-probe.native.out
  grep -q "capabilities: clock" data/lang-probe.native.out
  grep -q "compiled" data/lang-probe.native.out
  echo "PASS_AFTER host and compile-native at $HEAD_SHA"
}

fail_before
pass_after
echo "lang-types-caps prove ok"
