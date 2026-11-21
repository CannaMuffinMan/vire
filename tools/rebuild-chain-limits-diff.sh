#!/usr/bin/env bash
# Isolated host(VireListen)-vs-native-ELF harness for fcgcpa chain remainder:
# segment rotate at 512 KB, HTTP 507 when storage is full, 503 on tamper,
# migrate of old data/chain.json, concurrent POSTs, previousHash/hash aliases.
# FAIL_BEFORE at 5c3ed01abe2a12a34fca74b915d5e39a9f05fde3 (integration PR #112 tip:
# native GET /chain + bounded POST /block). Snapshot guest is
# tests/rebuild/fail-before-chain-remainder.vire (no rotate/507/tamper-verify/migrate/aliases).
# PASS_AFTER compiles guest-chain.vire. Contracts: tests/rebuild/contracts/fcg-chain-remainder.json
# plus alias cases from fcg-chain.json. Loopback 127.0.0.1 only. Caps unchanged.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
export PATH="${HOME}/.dotnet:${PATH:-}"
export DOTNET_ROOT="${DOTNET_ROOT:-$HOME/.dotnet}"
export VIRE_HEADLESS=1
unset VIRE_BUDGET || true

AFTER_SHA="$(git rev-parse HEAD)"
BEFORE_SHA="5c3ed01abe2a12a34fca74b915d5e39a9f05fde3"
CONTRACT="$ROOT/tests/rebuild/contracts/fcg-chain-remainder.json"
FAIL_SRC="$ROOT/tests/rebuild/fail-before-chain-remainder.vire"
GOOD_SRC="$ROOT/guest-chain.vire"
REMAINDER_PY="$ROOT/tools/rebuild-chain-remainder.py"
VIRE_DLL="$ROOT/bin/Release/net10.0/vire.dll"
FIX_SRC="$ROOT/data/rebuild/chain"
FIX_DST="$ROOT/data/chain"

python3 - <<'PY'
from pathlib import Path
rt = Path("src/rt.vire").read_text()
assert "33554432" in rt
cs = Path("Vire.cs").read_text()
assert "if (list.Count > 100000)" in cs
assert "MaxSteps = 1000000" in cs or "5000000" in cs
assert "5000000" in cs
doc = Path("tests/rebuild/contracts/fcg-chain-remainder.json").read_text()
assert "post_block_rotate_512k" in doc
assert "post_block_full_507" in doc
assert "get_chain_migrate_old" in doc
assert "post_block_concurrent_indexes" in doc
assert "post_block_tamper_503" in doc
assert "previousHash" in Path("guest-chain.vire").read_text()
assert "524288" in Path("guest-chain.vire").read_text()
assert "chain full" in Path("api/fcgcpa.vire").read_text()
print("caps_src_ok arena=33554432 list=100000 steps=5000000")
print("contract fcg-chain-remainder.json recorded")
PY

if [[ ! -f "$CONTRACT" || ! -f "$FIX_SRC/head.json" || ! -f "$FAIL_SRC" || ! -f "$GOOD_SRC" ]]; then
  echo "missing chain remainder contract, fixtures, or guests"
  exit 1
fi

dotnet build vire.csproj -c Release --nologo
mkdir -p data

install_fixtures() {
  rm -rf "$FIX_DST"
  mkdir -p "$FIX_DST"
  cp "$FIX_SRC/head.json" "$FIX_DST/head.json"
  cp "$FIX_SRC/000001.json" "$FIX_DST/000001.json"
  cp "$FIX_SRC/blocks.json" "$FIX_DST/blocks.json"
  rm -f "$ROOT/data/chain.json"
}

hex_to_bin() {
  python3 - "$1" "$2" <<'PY'
import pathlib, sys
pathlib.Path(sys.argv[2]).write_bytes(bytes.fromhex(pathlib.Path(sys.argv[1]).read_text().strip()))
PY
}

compile_listen_guest() {
  local src="$1"
  local stem="$2"
  python3 - "$src" "$ROOT/rebuild-chain-limits-run.vire" "data/${stem}.vire" <<'PY'
from pathlib import Path
import sys
text = Path(sys.argv[1]).read_text()
text = text.replace("listen with 18080", "listen with 0")
Path(sys.argv[2]).write_text(text)
Path(sys.argv[3]).write_text(text)
PY
  rm -f "data/${stem}.hex" "data/${stem}.elf"
  dotnet exec "$VIRE_DLL" --compiler compile-native.vire "data/${stem}.vire" "data/${stem}.hex"
  hex_to_bin "data/${stem}.hex" "data/${stem}.elf"
  chmod +x "data/${stem}.elf"
}

run_cmd() {
  local name="$1"
  shift
  local out="/tmp/vire-rebuild-limits-${name}.out"
  rm -f "$out"
  "$@" >"$out" 2>&1 &
  local pid=$!
  local i
  for i in $(seq 1 200); do
    if grep -q "listening on 127.0.0.1:" "$out" 2>/dev/null; then
      break
    fi
    if ! kill -0 "$pid" 2>/dev/null; then
      cat "$out"
      echo "guest $name exited before listen"
      exit 1
    fi
    sleep 0.05
  done
  local port
  port="$(sed -n 's/.*listening on 127.0.0.1:\([0-9]*\).*/\1/p' "$out" | head -1)"
  if [[ -z "$port" ]]; then
    cat "$out"
    echo "no listen port for $name"
    kill "$pid" 2>/dev/null || true
    wait "$pid" 2>/dev/null || true
    exit 1
  fi
  echo "$pid $port"
}

stop_guest() {
  local pid="$1"
  kill "$pid" 2>/dev/null || true
  wait "$pid" 2>/dev/null || true
}

echo "fail_before_sha $BEFORE_SHA"
echo "pass_after_sha $AFTER_SHA"
echo "property: rotate@512KiB, 507 full, 503 tamper, migrate chain.json, previousHash/hash aliases, concurrent indexes"
echo "platform: Linux ELF host VireListen vs native. Windows PE: tools/rebuild-chain-limits-windows.ps1 (CouchStation; unproven here)"
echo "residual: proof re-hash of stored JSON, not MAC. Native has no erase (empty chain.json). Native listen single-threaded; host ChainRouteLock. Caps arena 32MB / list 100000 / steps 5M unchanged."

install_fixtures
echo "FAIL_BEFORE compile snapshot guest (GET/POST without remainder)"
compile_listen_guest "$FAIL_SRC" "rebuild-chain-limits-fail"
ids="$(run_cmd fail "./data/rebuild-chain-limits-fail.elf")"
FPID="${ids%% *}"
FPORT="${ids##* }"
echo "fail_before_listen 127.0.0.1:$FPORT"
set +e
python3 "$REMAINDER_PY" run "$FPORT" "$FIX_SRC" "$FIX_DST" fail-before
FCODE=$?
set -e
stop_guest "$FPID"
install_fixtures
if [[ "$FCODE" -eq 0 ]]; then
  echo "FAIL_BEFORE expected remainder mismatch, got match"
  exit 1
fi
if [[ "$FCODE" -ne 2 ]]; then
  echo "FAIL_BEFORE harness error $FCODE"
  exit 1
fi
echo "FAIL_BEFORE at $BEFORE_SHA remainder contract mismatch as required"

echo "PASS_AFTER compile guest-chain.vire native ELF"
compile_listen_guest "$GOOD_SRC" "rebuild-chain-limits"
ids="$(run_cmd native "./data/rebuild-chain-limits.elf")"
GPID="${ids%% *}"
GPORT="${ids##* }"
echo "native_listen 127.0.0.1:$GPORT"
echo "PASS_AFTER host listen guest-chain.vire"
ids="$(run_cmd host dotnet exec "$VIRE_DLL" "$ROOT/rebuild-chain-limits-run.vire")"
HPID="${ids%% *}"
HPORT="${ids##* }"
echo "host_listen 127.0.0.1:$HPORT"

install_fixtures
python3 "$REMAINDER_PY" run "$GPORT" "$FIX_SRC" "$FIX_DST" pass-after
echo "native remainder contract ok"
stop_guest "$GPID"
stop_guest "$HPID"

install_fixtures
ids="$(run_cmd native "./data/rebuild-chain-limits.elf")"
GPID="${ids%% *}"
GPORT="${ids##* }"
ids="$(run_cmd host dotnet exec "$VIRE_DLL" "$ROOT/rebuild-chain-limits-run.vire")"
HPID="${ids%% *}"
HPORT="${ids##* }"
python3 "$REMAINDER_PY" run "$HPORT" "$FIX_SRC" "$FIX_DST" pass-after
echo "host remainder contract ok"
stop_guest "$GPID"
stop_guest "$HPID"

install_fixtures
ids="$(run_cmd native "./data/rebuild-chain-limits.elf")"
GPID="${ids%% *}"
GPORT="${ids##* }"
ids="$(run_cmd host dotnet exec "$VIRE_DLL" "$ROOT/rebuild-chain-limits-run.vire")"
HPID="${ids%% *}"
HPORT="${ids##* }"
python3 "$REMAINDER_PY" pair "$HPORT" "$GPORT" "$FIX_SRC" "$FIX_DST"
stop_guest "$GPID"
stop_guest "$HPID"
install_fixtures
echo "PASS_AFTER at $AFTER_SHA native ELF matches host VireListen vs fcg-chain-remainder.json (rotate/507/tamper/migrate/previousHash/concurrent)"
echo "rebuild chain limits diff ok"
