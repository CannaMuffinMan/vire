#!/usr/bin/env bash
set -euo pipefail
root=$(cd "$(dirname "$0")/.." && pwd)
cd "$root"
export PATH="${DOTNET_ROOT:-$HOME/.dotnet}:$PATH"
unset VIRE_BUDGET
dll=bin/Release/net10.0/vire.dll
if [[ ! -f $dll ]]; then
  dotnet build vire.csproj -c Release --nologo
fi
work=data/sec-emu
rm -rf "$work"
mkdir -p "$work/data"
python3 - <<'PY' > /dev/null
import unicorn
PY

printf 'define main\n  say "hello from vire"\nend\n' > "$work/hello.vire"
printf 'define main\n  say (read with "data/note.txt")\nend\n' > "$work/read.vire"
printf 'define main\n  write with "data/note.txt", "hacked"\nend\n' > "$work/write.vire"
printf 'define boom with n\n  if n > 0\n    boom with (n - 1)\n  end\nend\ndefine main\n  boom with 65\n  say "survived"\nend\n' > "$work/deep.vire"
printf 'TRUNCATED' > "$work/data/bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"
printf 'FULL' > "$work/data/bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbSECRET"
printf 'SECRET' > "$work/data/note.txt"

compile() {
  local src=$1 hex=$2
  dotnet exec "$dll" compile-native.vire "$src" "$hex"
}

compile "$work/hello.vire" "$work/hello.hex"
compile "$work/read.vire" "$work/read.hex"
compile "$work/write.vire" "$work/write.hex"
compile "$work/deep.vire" "$work/deep.hex"

emu() {
  python3 tools/native-sec-emu.py "$@"
}

hello=$(emu "$work/hello.hex" "$work" plain)
echo "$hello"
echo "$hello" | grep -F -q 'EXIT 0'
echo "$hello" | grep -F -q "b'hello from vire"
echo "$hello" | grep -F -q 'HEAP_SIZE 0x2000000'

# Long sibling names: parent GFA must be exactly "data", not a 47-byte prefix.
printf 'define main\n  say (read with "data/bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbSECRET")\nend\n' > "$work/longread.vire"
compile "$work/longread.vire" "$work/longread.hex"
long=$(emu "$work/longread.hex" "$work" plain)
echo "$long"
echo "$long" | grep -F -q "('data', 16)"
echo "$long" | grep -F -q "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbSECRET"
echo "$long" | grep -F -q "b'FULL"

parent=$(emu "$work/read.hex" "$work" reparse-parent)
echo "$parent"
echo "$parent" | grep -F -q "('data', 1056)"
echo "$parent" | grep -F -q 'CREATE []'
echo "$parent" | grep -F -q 'files stay inside the program folder'

nlink=$(emu "$work/write.hex" "$work" nlink2)
echo "$nlink"
echo "$nlink" | grep -F -q 'files stay inside the program folder'
test "$(cat "$work/data/note.txt")" = "SECRET"
echo "$nlink" | grep -F -q ', 3, 2097280)'
if echo "$nlink" | grep -F -q ', 2, 2097280)'; then
  echo 'nlink2 used CREATE_ALWAYS'
  exit 1
fi

deep=$(emu "$work/deep.hex" "$work" plain)
echo "$deep"
echo "$deep" | grep -F -q 'definitions called too deeply'
if echo "$deep" | grep -F -q survived; then
  echo 'deep recursion survived'
  exit 1
fi

printf 'outside-keep' > "$work/outside.txt"
printf 'define main\n  write with "data/../outside.txt", "hacked"\nend\n' > "$work/dotdot.vire"
compile "$work/dotdot.vire" "$work/dotdot.hex"
dot=$(emu "$work/dotdot.hex" "$work" plain)
echo "$dot"
echo "$dot" | grep -F -q 'files stay inside the program folder'
test "$(cat "$work/outside.txt")" = "outside-keep"
echo "$dot" | grep -F -q 'CREATE []'

printf 'define main\n  say (read with "data/' > "$work/long110.vire"
python3 -c "print('b'*110, end='')" >> "$work/long110.vire"
printf '")\nend\n' >> "$work/long110.vire"
compile "$work/long110.vire" "$work/long110.hex"
long110=$(emu "$work/long110.hex" "$work" plain)
echo "$long110"
echo "$long110" | grep -F -q 'EXIT 1'
echo "$long110" | grep -F -q 'FAULTS []'

mkdir -p "$work/outside-dir"
printf 'secret' > "$work/outside-dir/secret.txt"
ln -s "$work/outside-dir" "$work/data/linkdir"
printf 'define main\n  say (read with "data/linkdir/secret.txt")\nend\n' > "$work/parentlink.vire"
compile "$work/parentlink.vire" "$work/parentlink.hex"
plink=$(emu "$work/parentlink.hex" "$work" plain)
echo "$plink"
echo "$plink" | grep -F -q 'files stay inside the program folder'
echo "$plink" | grep -F -q 'CREATE []'

echo native sec emu check ok
