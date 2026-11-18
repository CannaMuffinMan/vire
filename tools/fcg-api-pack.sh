#!/usr/bin/env bash
# compile-native `read` only opens data/ or site/. Flatten the listen guest there.
set -euo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"
mkdir -p "$root/data"
{
  grep -v '^use ' "$root/api/redis-cmd.vire"
  echo
  grep -v '^use ' "$root/api/fcg-routes.vire"
  echo
  grep -v '^use ' "$root/fcg-api.vire" | grep -v '^~'
} > "$root/data/fcg-api-guest.vire"
echo "packed data/fcg-api-guest.vire"
