#!/usr/bin/env bash
# Time-boxed in-process campaign. Does not run on pull_request check.yml.
# Override VIRE_FUZZ_SECONDS (wall) and/or VIRE_FUZZ_ITERS (per target).
set -euo pipefail
ROOT="$(git rev-parse --show-toplevel)"
cd "$ROOT"
export VIRE_FUZZ_SECONDS="${VIRE_FUZZ_SECONDS:-180}"
if [[ -z "${VIRE_FUZZ_ITERS:-}" ]]; then
  if [[ "$VIRE_FUZZ_SECONDS" != "0" ]]; then
    export VIRE_FUZZ_ITERS=2000000
  else
    export VIRE_FUZZ_ITERS=8000
  fi
fi
export VIRE_HEADLESS=1
echo "fuzz-campaign iters=$VIRE_FUZZ_ITERS seconds=$VIRE_FUZZ_SECONDS seed=${VIRE_FUZZ_SEED:-20261030}"
dotnet test tests/Vire.Tests/Vire.Tests.csproj -c Release --nologo --filter "FullyQualifiedName~Fuzz"
if [[ "${VIRE_FUZZ_NATIVE:-0}" == "1" ]]; then
  bash tools/fuzz-native-pe.sh
fi
echo "fuzz-campaign ok"
