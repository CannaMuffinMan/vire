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
python3 -m pip install --user -q unicorn
python3 - <<'PY' > /dev/null
import unicorn
PY

printf 'define main\n  say "hello from vire"\nend\n' > "$work/hello.vire"
printf 'can fs.read data\ndefine main\n  say (read with "data/note.txt")\nend\n' > "$work/read.vire"
printf 'can fs.write data\ndefine main\n  write with "data/note.txt", "hacked"\nend\n' > "$work/write.vire"
printf 'define main\n  say (extend with [], [2147483648, 549755813888, 2147483649])\nend\n' > "$work/wrap.vire"
printf 'define boom with n\n  if n > 0\n    boom with (n - 1)\n  end\nend\ndefine main\n  boom with 65\n  say "survived"\nend\n' > "$work/deep.vire"
printf 'TRUNCATED' > "$work/data/bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"
printf 'FULL' > "$work/data/bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbSECRET"
printf 'SECRET' > "$work/data/note.txt"

compile() {
  local src=$1 hex=$2
  VIRE_BUDGET= dotnet exec "$dll" --compiler compile-native.vire "$src" "$hex"
}

compile "$work/hello.vire" "$work/hello.hex"
compile "$work/read.vire" "$work/read.hex"
compile "$work/write.vire" "$work/write.hex"
compile "$work/wrap.vire" "$work/wrap.hex"
compile "$work/deep.vire" "$work/deep.hex"

emu() {
  python3 tools/native-sec-emu.py "$@"
}

hello=$(emu "$work/hello.hex" "$work" plain)
echo "$hello"
echo "$hello" | grep -F -q 'EXIT 0'
echo "$hello" | grep -F -q "b'hello from vire"
echo "$hello" | grep -F -q 'HEAP_SIZE 0x2000000'

wrap=$(emu "$work/wrap.hex" "$work" plain)
echo "$wrap"
echo "$wrap" | grep -F -q 'EXIT 0'
echo "$wrap" | grep -F -q '[0, 0, 1]'

# Long sibling names: parent GFA must be exactly "data", not a 47-byte prefix.
printf 'can fs.read data\ndefine main\n  say (read with "data/bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbSECRET")\nend\n' > "$work/longread.vire"
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
printf 'can fs.write data\ndefine main\n  write with "data/../outside.txt", "hacked"\nend\n' > "$work/dotdot.vire"
compile "$work/dotdot.vire" "$work/dotdot.hex"
dot=$(emu "$work/dotdot.hex" "$work" plain)
echo "$dot"
echo "$dot" | grep -F -q 'files stay inside the program folder'
test "$(cat "$work/outside.txt")" = "outside-keep"
echo "$dot" | grep -F -q 'CREATE []'

printf 'can fs.read data\ndefine main\n  say (read with "data/' > "$work/long110.vire"
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
printf 'can fs.read data\ndefine main\n  say (read with "data/linkdir/secret.txt")\nend\n' > "$work/parentlink.vire"
compile "$work/parentlink.vire" "$work/parentlink.hex"
plink=$(emu "$work/parentlink.hex" "$work" plain)
echo "$plink"
echo "$plink" | grep -F -q 'files stay inside the program folder'
echo "$plink" | grep -F -q 'CREATE []'

printf 'can fs.write data\ndefine main\n  write with "data/payload.bat.", "pwn"\nend\n' > "$work/dotbat.vire"
compile "$work/dotbat.vire" "$work/dotbat.hex"
dotbat=$(emu "$work/dotbat.hex" "$work" plain)
echo "$dotbat"
echo "$dotbat" | grep -F -q 'files stay inside the program folder'
echo "$dotbat" | grep -F -q 'CREATE []'
test ! -e "$work/data/payload.bat."
test ! -e "$work/data/payload.bat"

printf 'SECRET-KEEP-ME-LONG' > "$work/data/note.txt"
mkdir -p "$work/outside"
printf 'SECRET-KEEP-ME-LONG' > "$work/outside/note.txt"
race=$(emu "$work/write.hex" "$work" walk-open-race)
echo "$race"
echo "$race" | grep -F -q 'files stay inside the program folder'
test "$(cat "$work/outside/note.txt")" = "SECRET-KEEP-ME-LONG"
if [[ -f $work/data.real/note.txt ]]; then
  test "$(cat "$work/data.real/note.txt")" = "SECRET-KEEP-ME-LONG"
fi
if echo "$race" | grep -F -q "b'hacked'"; then
  echo 'walk-open-race wrote hacked'
  exit 1
fi

vuln_sha=7c7c8ea3dcc4030ba8714fc2330d30b67f8d6867
vuln_dir=$(mktemp -d)
git cat-file -e "$vuln_sha^{commit}"
git archive "$vuln_sha" compile-native.vire src data/src data/compile-native.vire | tar -C "$vuln_dir" -xf -
if [[ -f $vuln_dir/compile-native.vire ]]; then
  mkdir -p "$vuln_dir/data"
  python3 - <<PY
from pathlib import Path
work = Path(r"$work")
vuln = Path(r"$vuln_dir") / "data"
for name in ("wrap.vire", "dotbat.vire", "write.vire"):
    src = work / name
    if not src.exists():
        continue
    text = "\n".join(ln for ln in src.read_text().splitlines() if not ln.startswith("can "))
    (vuln / name).write_text(text + "\n")
PY
  (cd "$vuln_dir" && VIRE_BUDGET= dotnet exec "$root/$dll" --compiler compile-native.vire data/wrap.vire data/wrap-vuln.hex)
  wrap_v=$(emu "$vuln_dir/data/wrap-vuln.hex" "$work" plain)
  echo "$wrap_v"
  echo "$wrap_v" | grep -F -q '[0, 0, 1]' && { echo 'F8 fail-before expected wrap mismatch'; exit 1; }
  echo F8_fail_before_native_not_001
  (cd "$vuln_dir" && VIRE_BUDGET= dotnet exec "$root/$dll" --compiler compile-native.vire data/dotbat.vire data/dotbat-vuln.hex)
  rm -f "$work/data/payload.bat" "$work/data/payload.bat."
  dotbat_v=$(emu "$vuln_dir/data/dotbat-vuln.hex" "$work" plain)
  echo "$dotbat_v"
  if [[ -e $work/data/payload.bat || -e $work/data/payload.bat. ]]; then
    echo trailing_dot_fail_before_created
  else
    echo trailing_dot_fail_before_emu_may_not_strip
  fi
  rm -f "$work/data/payload.bat" "$work/data/payload.bat."

  rm -rf "$work/data" "$work/data.real" "$work/outside"
  mkdir -p "$work/data" "$work/outside" "$vuln_dir/data"
  printf 'SECRET-KEEP-ME-LONG' > "$work/data/note.txt"
  printf 'SECRET-KEEP-ME-LONG' > "$work/outside/note.txt"
  (cd "$vuln_dir" && VIRE_BUDGET= dotnet exec "$root/$dll" --compiler compile-native.vire data/write.vire data/write-vuln.hex)
  cp "$vuln_dir/data/write-vuln.hex" "$work/write-vuln.hex"
  race_v=$(emu "$work/write-vuln.hex" "$work" walk-open-race)
  echo "$race_v"
  test "$(cat "$work/outside/note.txt")" = "hacked"
  test "$(cat "$work/data.real/note.txt")" = "SECRET-KEEP-ME-LONG"
else
  echo 'walk-open-race fail-before skipped (no 7c7c8ea tree)'
  exit 1
fi
rm -rf "$vuln_dir"

echo native sec emu check ok
