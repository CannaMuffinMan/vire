#!/usr/bin/env bash
# Stage-1/2/3 self-host check for compiler.vire.
# Real CLI:
#   dotnet exec vire.dll compiler.vire data/compiler.vire data/stage1.vc
#   dotnet exec vire.dll run data/stage1.vc compiler.vire stage2.vc
# Stage 2+ run with the .vc sandbox root = data/, so remaining args are
# relative to data/ (compiler.vire and stageN.vc names only).
# Seal: throwaway 32-byte key in VIRE_SEAL_KEY (base64). VC2 uses a random
# nonce, so sealed files differ. This script compares unsealed payloads
# byte-for-byte via payload-write + cmp, and also payload-sha256.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
export VIRE_SEAL_KEY="$(python3 -c 'import os,base64; print(base64.b64encode(os.urandom(32)).decode())')"
export VIRE_BUDGET="${VIRE_BUDGET:-5000000}"
WORKDIR="$ROOT/data"
mkdir -p "$WORKDIR"
cp "$ROOT/compiler.vire" "$WORKDIR/compiler.vire"
rm -f "$WORKDIR"/stage1.vc "$WORKDIR"/stage2.vc "$WORKDIR"/stage3.vc

if [[ -f "$ROOT/bin/Release/net10.0/vire.dll" ]]; then
  VIRE=( dotnet exec "$ROOT/bin/Release/net10.0/vire.dll" )
else
  VIRE=( dotnet run --no-build -c Release --project "$ROOT/vire.csproj" -- )
fi

run_vire() { "${VIRE[@]}" "$@"; }

echo "stage 1: interpreter compiles compiler.vire"
run_vire compiler.vire data/compiler.vire data/stage1.vc

echo "stage 2: stage1.vc compiles compiler.vire"
run_vire run data/stage1.vc compiler.vire stage2.vc

echo "stage 3: stage2.vc compiles compiler.vire"
run_vire run data/stage2.vc compiler.vire stage3.vc

hash1="$(run_vire payload-sha256 data/stage1.vc | tail -n 1)"
hash2="$(run_vire payload-sha256 data/stage2.vc | tail -n 1)"
hash3="$(run_vire payload-sha256 data/stage3.vc | tail -n 1)"
echo "stage1 $hash1"
echo "stage2 $hash2"
echo "stage3 $hash3"
if [[ "$hash1" != "$hash2" || "$hash2" != "$hash3" ]]; then
  echo "selfhost hashes differ" >&2
  exit 1
fi
run_vire payload-write data/stage1.vc data/stage1.bin
run_vire payload-write data/stage2.vc data/stage2.bin
run_vire payload-write data/stage3.vc data/stage3.bin
if ! cmp -s data/stage1.bin data/stage2.bin; then
  echo "stage-1 payload bytes != stage-2 payload bytes" >&2
  exit 1
fi
if ! cmp -s data/stage2.bin data/stage3.bin; then
  echo "stage-2 payload bytes != stage-3 payload bytes" >&2
  exit 1
fi
echo "selfhost ok"
