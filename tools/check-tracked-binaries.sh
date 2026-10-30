#!/usr/bin/env bash
# Fail if git tracks build binaries (.exe .dll .pdb .hex) or compiler .vc outputs.
# Fixture .vc files under tests/fixtures/ are allowed (old-seal samples).
set -euo pipefail
ROOT="$(git rev-parse --show-toplevel)"
cd "$ROOT"
fail=0
while IFS= read -r path; do
  [[ -z "$path" ]] && continue
  lower="${path,,}"
  case "$lower" in
    tests/fixtures/*)
      continue
      ;;
    bin/*|obj/*|dist/*|publish/*)
      echo "tracked build output: $path" >&2
      fail=1
      continue
      ;;
  esac
  ext="${lower##*.}"
  case "$ext" in
    exe|dll|pdb|hex)
      echo "tracked binary: $path" >&2
      fail=1
      ;;
    vc)
      echo "tracked .vc build output: $path" >&2
      fail=1
      ;;
  esac
done < <(git ls-files)
if [[ "$fail" -ne 0 ]]; then
  exit 1
fi
echo "no tracked build binaries"
