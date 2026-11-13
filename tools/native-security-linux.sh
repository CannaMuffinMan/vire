#!/usr/bin/env bash
set -euo pipefail
root=$(cd "$(dirname "$0")/.." && pwd)
cd "$root"
export PATH="${DOTNET_ROOT:-$HOME/.dotnet}:$PATH"
BASE_SHA=7fd41b8814442a4348478c409c7720ad2b925dd9
HEAD_SHA=$(git rev-parse HEAD)
echo "FAIL_BEFORE_SHA $BASE_SHA"
echo "PASS_AFTER_SHA $HEAD_SHA"
dll=bin/Release/net10.0/vire.dll
if [[ ! -f $dll ]]; then
  dotnet build vire.csproj -c Release --nologo
fi

if git show "$BASE_SHA:src/pe.vire" | grep -q VirtualQuery; then
  echo "FAIL_BEFORE $BASE_SHA already had VirtualQuery"
else
  echo "FAIL_BEFORE $BASE_SHA IAT has no VirtualQuery"
fi
if git show "$BASE_SHA:src/rt-more.vire" | grep -q iat_mv; then
  echo "FAIL_BEFORE $BASE_SHA already had MoveFileExA"
else
  echo "FAIL_BEFORE $BASE_SHA rt_write had no MoveFileExA"
fi
if git show "$BASE_SHA:src/rt.vire" | grep -q crash_log_path; then
  echo "FAIL_BEFORE $BASE_SHA already had crash_log_path"
else
  echo "FAIL_BEFORE $BASE_SHA no dedicated data/crash.log path"
fi

grep -q VirtualQuery src/pe.vire
grep -q MoveFileExA src/pe.vire
grep -q crash_log_path src/rt.vire
grep -q iat_mv src/rt-more.vire
echo "PASS_AFTER sources contain VirtualQuery MoveFileExA crash_log_path"

export VIRE_FUZZ_ITERS="${VIRE_FUZZ_ITERS:-400}"
dotnet test tests/Vire.Tests/Vire.Tests.csproj -c Release --nologo \
  --filter "FullyQualifiedName~FuzzTests|FullyQualifiedName~NativeParserFuzzTests" \
  --logger "console;verbosity=detailed"

if [[ -f src/rt-pg.vire ]]; then
  echo "postgres parser present (pg_rows_parse/pg_err fuzzed on Windows)"
fi
if grep -RniE 'websocket|redis' src compile-native.vire >/dev/null 2>&1; then
  echo "unexpected WebSocket/Redis parser present"
  exit 1
fi
echo "residual: no WebSocket frame or Redis reply parsers on native-compiler"
echo "native_security_linux ok"
