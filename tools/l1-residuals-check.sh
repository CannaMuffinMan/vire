#!/usr/bin/env bash
# Fail-before on #57 merge d818f169 vs pass-after HEAD for L1 residuals.
set -euo pipefail
root=$(cd "$(dirname "$0")/.." && pwd)
cd "$root"
dll=bin/Release/net10.0/vire.dll
if [[ ! -f $dll ]]; then
  dotnet build vire.csproj -c Release --nologo
fi
sha=d818f1691ed8659538a10255c58211ebc1316e00
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
body='define main
  let n be 0
  while n < 100
    let n be n + 1
  end
  say "emitU8"
end
'
printf '%s' "$body" > "$work/hello.vire"
printf '%s' "$body" > "$work/compiler.vire"

run_old=
if git cat-file -e "$sha^{commit}"; then
  old=$(mktemp -d)
  git worktree add --detach "$old" "$sha" >/dev/null
  (cd "$old" && dotnet build vire.csproj -c Release --nologo >/dev/null)
  old_dll=$old/bin/Release/net10.0/vire.dll
  hello_old=$(cd "$work" && VIRE_BUDGET=10 dotnet exec "$old_dll" hello.vire >/tmp/l1-hello-old.txt 2>&1; echo $?)
  guest_old=$(cd "$work" && VIRE_BUDGET=10 dotnet exec "$old_dll" compiler.vire >/tmp/l1-guest-old.txt 2>&1; echo $?)
  echo "compiler_claim_fail_before d818f169 hello=$hello_old guest=$guest_old"
  test "$hello_old" != 0
  test "$guest_old" = 0
  git worktree remove --force "$old"
  run_old=1
fi

hello_new=$(cd "$work" && VIRE_BUDGET=10 dotnet exec "$root/$dll" hello.vire >/tmp/l1-hello-new.txt 2>&1; echo $?)
guest_new=$(cd "$work" && VIRE_BUDGET=10 dotnet exec "$root/$dll" compiler.vire >/tmp/l1-guest-new.txt 2>&1; echo $?)
flag_new=$(cd "$work" && VIRE_BUDGET=10 dotnet exec "$root/$dll" --compiler compiler.vire >/tmp/l1-flag-new.txt 2>&1; echo $?)
echo "compiler_claim_pass_after hello=$hello_new guest=$guest_new flagged=$flag_new"
test "$hello_new" != 0
test "$guest_new" != 0
test "$flag_new" != 0
grep -q 'VIRE_TEST_TOCTOU_MS' "$root/VirePaths.cs" && { echo 'product still reads VIRE_TEST_TOCTOU_MS'; exit 1; }
echo l1 residuals check ok
