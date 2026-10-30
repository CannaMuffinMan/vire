#!/usr/bin/env bash
# Time-boxed in-process fuzz (text corpus only). Override VIRE_FUZZ_ITERS to stretch.
set -euo pipefail
ROOT="$(git rev-parse --show-toplevel)"
cd "$ROOT"
export VIRE_FUZZ_ITERS="${VIRE_FUZZ_ITERS:-20000}"
dotnet test tests/Vire.Tests/Vire.Tests.csproj -c Release --nologo --filter "FullyQualifiedName~Fuzz"
