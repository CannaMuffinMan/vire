#!/usr/bin/env bash
# Rerun host fail-after checks for PR42 findings F1,F3,F8,F12,F13 on this tree.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
export PATH="${DOTNET_ROOT:-$HOME/.dotnet}:$PATH"
dll=bin/Release/net10.0/vire.dll
[[ -f $dll ]] || dotnet build vire.csproj -c Release --nologo
tmp=$(mktemp -d)
printf 'define main\n  let a be [1, 2]\n  say (extend with a, a)\nend\n' > "$tmp/f1.vire"
out=$(dotnet exec "$dll" "$tmp/f1.vire")
echo "F1 $out"
[[ $out == $'[1, 2, 1, 2]\n' ]]
printf 'define main\n  say (extend with [], [2147483648])\nend\n' > "$tmp/f8.vire"
out=$(dotnet exec "$dll" "$tmp/f8.vire")
echo "F8 $out"
[[ $out == $'[0]\n' ]]
mkdir -p data
printf 'define main\n  say ([1 + 2] at 0)\nend\n' > data/list-expr.vire
dotnet exec "$dll" compile-native.vire data/list-expr.vire data/list-expr.hex >/tmp/f3c.txt
tail -1 /tmp/f3c.txt | grep -q compiled
echo F3 compiled
bash tools/native-arena-check.sh
echo copilot evidence ok
