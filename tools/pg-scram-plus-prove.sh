#!/usr/bin/env bash
# Host interpreter: RFC 7677 / RFC 5802 gs2 SCRAM-SHA-256-PLUS on loopback only.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
export VIRE_BUDGET=5000000
export VIRE_HEADLESS=1
PIN=6693e0e5d78c9df775d0531a39a14a574239cfac
echo "pg_scram_plus_fail_before_sha $PIN"
echo "pass_after_sha $(git rev-parse HEAD)"

if ! git cat-file -e "${PIN}^{commit}" 2>/dev/null; then
  git fetch --depth 1 origin "$PIN"
fi
PINDIR="$(mktemp -d "${TMPDIR:-/tmp}/vire-pg-scram-plus-fail-before.XXXXXX")"
rmdir "$PINDIR"
git worktree add --detach "$PINDIR" "$PIN"
cleanup_pin() { git worktree remove --force "$PINDIR" >/dev/null 2>&1 || rm -rf "$PINDIR"; }
trap cleanup_pin EXIT
pin_src="$PINDIR/src/rt-pg.vire"
echo "FAIL_BEFORE pin src $pin_src"
if ! grep -Fq 'c=biws' "$pin_src"; then
  echo "FAIL_BEFORE expected c=biws downgrade at $PIN" >&2
  exit 1
fi
if grep -Fq 'p=tls-server-end-point' "$pin_src"; then
  echo "FAIL_BEFORE unexpected PLUS gs2 at $PIN" >&2
  exit 1
fi
if ! grep -Fq 'let body be "SCRAM-SHA-256"' "$pin_src"; then
  echo "FAIL_BEFORE expected SASL init without -PLUS at $PIN" >&2
  exit 1
fi
if ! grep -Fq 'TODO(VIRE-FINISH-NOW): guest SCRAM-SHA-256-PLUS' "$pin_src"; then
  echo "FAIL_BEFORE expected PLUS TODO at $PIN" >&2
  exit 1
fi
echo "FAIL_BEFORE at $PIN: SCRAM-SHA-256-PLUS unsupported; client-final c=biws; SASL init never -PLUS"

cleanup_pin
trap - EXIT

VIRE_DLL="$ROOT/bin/Release/net10.0/vire.dll"
if [[ ! -f "$VIRE_DLL" ]]; then
  dotnet build "$ROOT/vire.csproj" -c Release
fi
set +e
plus_out="$(dotnet exec "$VIRE_DLL" pg-scram-plus-prove.vire)"
plus_code=$?
set -e
printf '%s\n' "$plus_out"
echo "pg_scram_plus_exit $plus_code"
if [[ "$plus_code" != "0" ]]; then
  echo "pg-scram-plus-prove exit $plus_code" >&2
  exit 1
fi
if ! grep -Fq "PG SCRAM PLUS PROVE pass" <<<"$plus_out"; then
  echo "plus prove missing pass line" >&2
  exit 1
fi
if ! grep -Fq "PLUS client-final p PASS" <<<"$plus_out"; then
  echo "plus prove missing client-final" >&2
  exit 1
fi
if ! grep -Fq "plus-only no bind REJECT" <<<"$plus_out"; then
  echo "plus prove missing downgrade-refusal" >&2
  exit 1
fi
echo "PASS_AFTER at $(git rev-parse HEAD) RFC7677 c= binding and PLUS refuse"
echo "loopback_only 127.0.0.1 (xUnit PgScramPlusTests)"
echo "caps arena 33554432 list 100000 steps 5000000 itemCap 1e6"
