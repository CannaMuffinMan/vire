#!/usr/bin/env bash
# Time-boxed in-process fuzz (text corpus + campaign). Override VIRE_FUZZ_ITERS / VIRE_FUZZ_SECONDS.
set -euo pipefail
ROOT="$(git rev-parse --show-toplevel)"
cd "$ROOT"
export VIRE_FUZZ_ITERS="${VIRE_FUZZ_ITERS:-20000}"
export VIRE_FUZZ_SECONDS="${VIRE_FUZZ_SECONDS:-0}"
bash tools/fuzz-campaign.sh
