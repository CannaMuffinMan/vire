#!/usr/bin/env bash
# FAIL_BEFORE / PASS_AFTER: string-keyed `at` on maps (host vs gen1 PE emu).
set -euo pipefail
Root=$(cd "$(dirname "$0")/.." && pwd)
cd "$Root"
export VIRE_BUDGET=5000000 VIRE_HEADLESS=1
VireDll="$Root/bin/Release/net10.0/vire.dll"
if [[ ! -f "$VireDll" ]]; then
  echo "missing $VireDll" >&2
  exit 1
fi
BaseSha=3946d1c6c4f3fc12e4a486da600bba354ad60c64
AfterSha=$(git rev-parse HEAD)
python3 -m pip install --user -q unicorn
mkdir -p data
cp tests/native/at-map.vire data/at-map.vire
cp tests/native/at-none.vire data/at-none.vire

Want=$'ada\ntrue\n42'

Work=$(mktemp -d)
git worktree add --detach "$Work" "$BaseSha"
( cd "$Work" && dotnet build vire.csproj -c Release -nologo )
cp tests/native/at-map.vire "$Work/data/at-map.vire"
( cd "$Work" && VIRE_BUDGET= dotnet exec bin/Release/net10.0/vire.dll --compiler compile-native.vire data/at-map.vire data/at-map.hex )
set +e
before=$(python3 tools/native-pe-emu.py "$Work/data/at-map.hex" 2>&1)
before_code=$?
set -e
echo "$before"
if [[ "$before" == *$Want* && "$before_code" -eq 0 ]]; then
  echo "FAIL expected base PE to miss string-keyed at after split" >&2
  git worktree remove --force "$Work"
  exit 1
fi
echo "FAIL_BEFORE at $BaseSha: gen1 PE split/at for u at \"id\" disagreed with host (emu exit $before_code)"
git worktree remove --force "$Work"

host=$(dotnet exec "$VireDll" data/at-map.vire)
host_code=$?
echo "$host"
if [[ "$host_code" -ne 0 ]]; then
  echo "FAIL host at-map exit $host_code" >&2
  exit 1
fi
host_n=$(printf '%s\n' "$host" | tr -d '\r')
if [[ "$host_n" != "$Want" ]]; then
  echo "FAIL host at-map stdout" >&2
  exit 1
fi
VIRE_BUDGET= dotnet exec "$VireDll" --compiler compile-native.vire data/at-map.vire data/at-map.hex
emu=$(python3 tools/native-pe-emu.py data/at-map.hex)
echo "$emu"
if [[ "$emu" != *$Want* ]]; then
  echo "FAIL emu at-map stdout" >&2
  exit 1
fi
if [[ "$emu" != *"EXIT 0"* ]]; then
  echo "FAIL emu at-map exit" >&2
  exit 1
fi

host_none=$(dotnet exec "$VireDll" data/at-none.vire 2>&1 || true)
echo "$host_none"
if [[ "$host_none" != *"at needs a list, text, or map"* ]]; then
  echo "FAIL host none-at message" >&2
  exit 1
fi
VIRE_BUDGET= dotnet exec "$VireDll" --compiler compile-native.vire data/at-none.vire data/at-none.hex
emu_none=$(python3 tools/native-pe-emu.py data/at-none.hex || true)
echo "$emu_none"
if [[ "$emu_none" != *"at needs a list, text, or map"* ]]; then
  echo "FAIL emu none-at message" >&2
  exit 1
fi

echo "PASS_AFTER at $AfterSha: host and gen1 PE (emu) identical for map at \"name\"/\"id\"; none-at same error"
echo "at-map linux check ok"
