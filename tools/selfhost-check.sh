#!/usr/bin/env bash
# Stage-1/2/3 self-host check for compiler.vire.
# Real CLI:
#   dotnet exec vire.dll compiler.vire data/compiler.vire data/stage1.vc
#   dotnet exec vire.dll run data/stage1.vc compiler.vire stage2.vc
# Stage 2+ run with the .vc sandbox root = data/, so remaining args are
# relative to data/ (compiler.vire and stageN.vc names only).
# Seal: throwaway VIRE_SEAL for this process only. The current VIRE1 XOR seal is
# deterministic, so sealed .vc hashes match. If C5 adds a random nonce, compare
# unsealed payloads instead of the files.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
export VIRE_SEAL="selfhost-test-seal-not-a-secret"
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

hash1="$(sha256sum data/stage1.vc | awk '{print $1}')"
hash2="$(sha256sum data/stage2.vc | awk '{print $1}')"
hash3="$(sha256sum data/stage3.vc | awk '{print $1}')"
echo "stage1 $hash1"
echo "stage2 $hash2"
echo "stage3 $hash3"
if [[ "$hash1" != "$hash2" || "$hash2" != "$hash3" ]]; then
  echo "selfhost hashes differ" >&2
  exit 1
fi
echo "selfhost ok"
