#!/usr/bin/env bash
# FAIL_BEFORE / PASS_AFTER for else-if binding (Linux host + compile-native).
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
Want=$'params\ntwo\none\nzero\none\nbig\ntwo\nother'
mkdir -p data
cp tests/native/else-if-bind.vire data/else-if-bind.vire

Work=$(mktemp -d)
git worktree add --detach "$Work" "$BaseSha"
( cd "$Work" && dotnet build vire.csproj -c Release -nologo )
set +e
before=$(dotnet exec "$Work/bin/Release/net10.0/vire.dll" "$Root/data/else-if-bind.vire" 2>&1)
before_code=$?
set -e
echo "$before"
if [[ "$before_code" -eq 0 ]]; then
  echo "FAIL expected base host to reject else-if steal program" >&2
  git worktree remove --force "$Work"
  exit 1
fi
if [[ "$before" != *"line does not start a statement"* ]]; then
  echo "FAIL expected 'line does not start a statement' at base" >&2
  git worktree remove --force "$Work"
  exit 1
fi
echo "FAIL_BEFORE at $BaseSha: nested if inside else-if stole chain else/end → line does not start a statement (exit $before_code)"
git worktree remove --force "$Work"

host=$(dotnet exec "$VireDll" data/else-if-bind.vire)
host_code=$?
echo "$host"
if [[ "$host_code" -ne 0 ]]; then
  echo "FAIL host else-if-bind exit $host_code" >&2
  exit 1
fi
host_n=$(printf '%s\n' "$host" | tr -d '\r')
if [[ "$host_n" != "$Want" ]]; then
  echo "FAIL host stdout mismatch" >&2
  exit 1
fi
comp=$(dotnet exec "$VireDll" --compiler compile-native.vire data/else-if-bind.vire data/else-if-bind.hex)
echo "$comp"
if [[ "$comp" != *"compiled"* ]]; then
  echo "FAIL compile-native else-if-bind" >&2
  exit 1
fi
echo "PASS_AFTER at $AfterSha: host decode/nest/chain stdout matches grammar; compile-native compiled"
echo "else-if linux check ok"
