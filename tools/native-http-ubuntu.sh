#!/usr/bin/env bash
set -euo pipefail
Root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$Root"
export VIRE_BUDGET=5000000 VIRE_HEADLESS=1
VireDll="$Root/bin/Release/net10.0/vire.dll"
BaseSha="9ea4561d12236f7f2f44858f137d7c948836df65"
AfterSha="$(git rev-parse HEAD)"
echo "fail_before_sha $BaseSha"
echo "pass_after_sha $AfterSha"
git cat-file -e "${BaseSha}^{commit}" || git fetch --depth 1 origin "$BaseSha"
fb="$Root/data/http-fail-before"
rm -rf "$fb"
git worktree add --detach "$fb" "$BaseSha"
cleanup() { git worktree remove --force "$fb" >/dev/null 2>&1 || true; }
trap cleanup EXIT
if [[ -f "$fb/src/http.vire" ]]; then
  echo "base already has src/http.vire" >&2
  exit 1
fi
mkdir -p "$fb/data"
printf 'use "src/http.vire"\ndefine main\n  say 1\nend\n' > "$fb/data/http-missing.vire"
echo "fail_before_checkout $(git -C "$fb" rev-parse HEAD)"
set +e
before_out="$(cd "$fb" && dotnet exec "$VireDll" --compiler compile-native.vire data/http-missing.vire data/http-missing.hex 2>&1)"
before_code=$?
set -e
echo "$before_out"
echo "fail_before_compile_exit $before_code"
if [[ "$before_code" -eq 0 ]]; then
  echo "fail-before compile unexpectedly succeeded" >&2
  exit 1
fi
echo "FAIL_BEFORE at $BaseSha: src/http.vire missing; HTTP framework guest would not compile"
echo "http_prove_host_start"
host_out="$(dotnet exec "$VireDll" http-prove.vire)"
host_code=$?
echo "$host_out"
echo "http_prove_host_exit $host_code"
if [[ "$host_code" -ne 0 ]]; then
  exit 1
fi
echo "PASS_AFTER at $AfterSha host http-prove"
