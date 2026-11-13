#!/usr/bin/env bash
# Interpret every runnable homepage sample with the in-repo host runner.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../../.." && pwd)"
cd "$ROOT"
DLL="$ROOT/bin/Release/net10.0/vire.dll"
if [[ ! -f "$DLL" ]]; then
  echo "missing $DLL" >&2
  exit 1
fi
MANIFEST="$ROOT/site/vire/examples/manifest.txt"
WORKDIR="$ROOT/data/site-vire-host"
rm -rf "$WORKDIR"
mkdir -p "$WORKDIR"
cp "$ROOT"/site/vire/examples/*.vire "$WORKDIR/"
fail=0
while IFS= read -r line || [[ -n "$line" ]]; do
  [[ -z "$line" || "$line" == \#* ]] && continue
  name="$line"
  base="${name%.vire}"
  want_file="$ROOT/site/vire/examples/${base}.out"
  echo "host $name"
  got="$(dotnet exec "$DLL" "$WORKDIR/$name")"
  want="$(cat "$want_file")"
  got_trim="$(printf '%s' "$got" | tr -d '\r')"
  want_trim="$(printf '%s' "$want" | tr -d '\r')"
  if [[ "$got_trim" != "$want_trim" ]]; then
    echo "FAIL host $name"
    echo "want:"
    printf '%s\n' "$want_trim"
    echo "got:"
    printf '%s\n' "$got_trim"
    fail=1
  else
    echo "PASS host $name"
  fi
done < "$MANIFEST"
exit "$fail"
