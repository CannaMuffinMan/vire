#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
export DOTNET_ROOT="${DOTNET_ROOT:-$HOME/.dotnet}"
export PATH="$DOTNET_ROOT:$PATH"
export VIRE_BUDGET=5000000
export VIRE_HEADLESS=1
DLL="$ROOT/bin/Release/net10.0/vire.dll"
if [[ ! -f "$DLL" ]]; then
  echo "missing $DLL" >&2
  exit 1
fi
echo "uptime $(uptime)"
echo "nproc $(nproc)"
echo "dotnet $(dotnet --version)"
run() {
  local name="$1"
  shift
  local start end
  start=$(date +%s.%N)
  set +e
  "$@" >"/tmp/perf-$name.out" 2>"/tmp/perf-$name.err"
  local rc=$?
  set -e
  end=$(date +%s.%N)
  python3 - "$start" "$end" "$rc" "$name" <<'PY'
import sys
start, end, rc, name = sys.argv[1], sys.argv[2], sys.argv[3], sys.argv[4]
wall = float(end) - float(start)
print(f"phase {name} wall_s {wall:.3f} exit {rc}")
PY
  if [[ -s /tmp/perf-$name.err ]]; then
    grep -E "still running|total_steps|compiled|error" "/tmp/perf-$name.err" | tail -n 8 || true
  fi
  tail -n 3 "/tmp/perf-$name.out" || true
}
run loadpe dotnet exec "$DLL" probe-load-pe.vire
run openimage dotnet exec "$DLL" probe-open-image.vire
run hexof dotnet exec "$DLL" probe-hexof.vire
run hexbuiltin dotnet exec "$DLL" probe-hex-builtin.vire
run emitu8 dotnet exec "$DLL" probe-emitu8.vire
run emitlist dotnet exec "$DLL" probe-emitlist.vire
run buildexe dotnet exec "$DLL" probe-build-exe.vire || true
mkdir -p data/src
cp -f guest-hello.vire data/guest-hello.vire
run hello dotnet exec "$DLL" compile-native.vire data/guest-hello.vire data/guest-hello.hex
if [[ "${PERF_GEN1:-0}" == "1" ]]; then
  cp -f compile-native.vire data/compile-native.vire
  cp -f src/asm.vire src/pe.vire src/rt.vire src/rt-more.vire data/src/
  run gen1host dotnet exec "$DLL" compile-native.vire data/compile-native.vire data/gen1.hex
fi
