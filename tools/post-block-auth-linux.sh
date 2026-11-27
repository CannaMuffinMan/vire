#!/usr/bin/env bash
# Linux proof that POST /block is deny-by-default Bearer.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
export PATH="${HOME}/.dotnet:${PATH:-}"
export DOTNET_ROOT="${DOTNET_ROOT:-$HOME/.dotnet}"
export DOTNET_CLI_TELEMETRY_OPTOUT=1
echo "pass_after_sha $(git rev-parse HEAD)"
dotnet test tests/Vire.Tests/Vire.Tests.csproj -c Release --nologo \
  --filter "FullyQualifiedName~BlockAuthTests|FullyQualifiedName~ChainTests"
echo "post-block-auth linux ok"
