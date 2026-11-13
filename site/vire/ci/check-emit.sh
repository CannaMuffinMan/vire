#!/usr/bin/env bash
# Host-emit a Windows PE hex for every runnable homepage sample.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../../.." && pwd)"
cd "$ROOT"
DLL="$ROOT/bin/Release/net10.0/vire.dll"
if [[ ! -f "$DLL" ]]; then
  echo "missing $DLL" >&2
  exit 1
fi
WORKDIR="$ROOT/data/site-vire-emit"
rm -rf "$WORKDIR"
mkdir -p "$WORKDIR"
cp "$ROOT"/site/vire/examples/*.vire "$WORKDIR/"
fail=0
while IFS= read -r line || [[ -n "$line" ]]; do
  [[ -z "$line" || "$line" == \#* ]] && continue
  name="$line"
  base="${name%.vire}"
  echo "emit $name"
  if ! VIRE_BUDGET= dotnet exec "$DLL" --compiler compile-native.vire \
      "data/site-vire-emit/$name" "data/site-vire-emit/${base}.hex" | tee /tmp/site-vire-emit.out; then
    echo "FAIL emit $name"
    fail=1
    continue
  fi
  if ! grep -q compiled /tmp/site-vire-emit.out; then
    echo "FAIL emit $name missing compiled"
    fail=1
    continue
  fi
  if [[ ! -s "$WORKDIR/${base}.hex" ]]; then
    echo "FAIL emit $name empty hex"
    fail=1
    continue
  fi
  echo "PASS emit $name"
done < "$ROOT/site/vire/examples/manifest.txt"
exit "$fail"
