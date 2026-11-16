#!/usr/bin/env bash
# Linux native file read/write via raw syscalls (open/read/write/close/stat).
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
export PATH="${HOME}/.dotnet:${PATH:-}"
export DOTNET_ROOT="${DOTNET_ROOT:-$HOME/.dotnet}"
export VIRE_HEADLESS=1
unset VIRE_BUDGET || true
AFTER_SHA="$(git rev-parse HEAD)"
echo "pass_after_sha $AFTER_SHA"
dotnet build vire.csproj -c Release --nologo
mkdir -p data
cat > data/elf-files.vire <<'EOF'
define main
  write with "data/elf-write.txt", "abc"
  say (read with "data/elf-write.txt")
end
EOF
rm -f data/elf-files.hex data/elf-write.txt
dotnet exec bin/Release/net10.0/vire.dll --compiler compile-native.vire data/elf-files.vire data/elf-files.hex
python3 - <<'PY'
from pathlib import Path
Path("data/elf-files.elf").write_bytes(bytes.fromhex(Path("data/elf-files.hex").read_text().strip()))
PY
chmod +x data/elf-files.elf
OUT="$(./data/elf-files.elf | tr -d '\r')"
CODE=${PIPESTATUS[0]}
echo "$OUT"
echo "elf_files_exit $CODE"
BODY="$(tr -d '\r' < data/elf-write.txt)"
echo "elf_files_body $BODY"
if [[ "$CODE" -ne 0 || "$OUT" != "abc" || "$BODY" != "abc" ]]; then
  echo "native elf files failed out='$OUT'"
  exit 1
fi
echo "PASS_AFTER at $AFTER_SHA ELF write/read data/elf-write.txt"
echo "native elf files ok"
