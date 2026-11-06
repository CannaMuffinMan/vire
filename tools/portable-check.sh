#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
export VIRE_BUDGET="${VIRE_BUDGET:-5000000}"
export VIRE_SEAL_KEY="${VIRE_SEAL_KEY:-$(python3 -c 'import os,base64; print(base64.b64encode(bytes([3]*32)).decode())')}"

if [[ -f "$ROOT/bin/Release/net10.0/vire.dll" ]]; then
  VIRE=(dotnet exec "$ROOT/bin/Release/net10.0/vire.dll")
else
  VIRE=(dotnet run --no-build -c Release --project "$ROOT/vire.csproj" --)
fi

echo "host $(uname -s) $(uname -m)"
echo "skip work.vire: show waits on a window; not headless"
echo "skip board.vire: show waits on a window; not headless"
echo "skip serve.vire: listen binds a socket and does not exit"
echo "skip optional/live.vire: fetch needs the public network"

run_ok() {
  local rel="$1"
  local want="$2"
  local start end
  start="$(python3 -c 'import time; print(time.perf_counter())')"
  local out
  out="$("${VIRE[@]}" "$rel" 2>&1)" || { echo "FAIL $rel exit $?"; echo "$out"; exit 1; }
  end="$(python3 -c 'import time; print(time.perf_counter())')"
  if ! printf '%s\n' "$out" | grep -Fqx "$want"; then
    echo "FAIL $rel missing line: $want"
    echo "$out"
    exit 1
  fi
  python3 -c "print('TIME interp $rel {:.3f}s'.format(float('$end')-float('$start')))"
}

run_fail() {
  local rel="$1"
  local want="$2"
  set +e
  local out
  out="$("${VIRE[@]}" "$rel" 2>&1)"
  local code=$?
  set -e
  if [[ "$code" -eq 0 ]]; then
    echo "FAIL $rel should fail"
    echo "$out"
    exit 1
  fi
  if ! printf '%s\n' "$out" | grep -Fq "$want"; then
    echo "FAIL $rel missing error: $want"
    echo "$out"
    exit 1
  fi
  echo "TIME interp $rel fail-ok"
}

run_ok samples/hello.vire "hello from vire"
run_ok samples/deps-demo.vire "alpha beta hi 3 y"
run_fail samples/deps-missing.vire "deps.lock does not name missingkit"
run_ok count.vire "5"
run_ok term.vire "hello from any machine"
run_ok vault.vire "vault written"

WORKDIR="$ROOT/data/portable-check"
rm -rf "$WORKDIR"
mkdir -p "$WORKDIR"
cp "$ROOT/samples/hello.vire" "$WORKDIR/hello.vire"
cp "$ROOT/compiler.vire" "$WORKDIR/compiler.vire"
start="$(python3 -c 'import time; print(time.perf_counter())')"
"${VIRE[@]}" compiler.vire data/portable-check/hello.vire data/portable-check/hello.vc
end="$(python3 -c 'import time; print(time.perf_counter())')"
python3 -c "print('TIME compiler.vire samples/hello.vire {:.3f}s'.format(float('$end')-float('$start')))"
interp="$("${VIRE[@]}" samples/hello.vire)"
compiled="$("${VIRE[@]}" run data/portable-check/hello.vc)"
if [[ "$interp" != "$compiled" ]]; then
  echo "FAIL interpreter vs compiler.vire hello"
  echo "interp=$interp"
  echo "compiled=$compiled"
  exit 1
fi
echo "bytecode hello matches interpreter"

if [[ -f "$ROOT/compile-native.vire" ]]; then
  start="$(python3 -c 'import time; print(time.perf_counter())')"
  "${VIRE[@]}" compile-native.vire data/portable-check/hello.vire data/portable-check/hello.hex
  end="$(python3 -c 'import time; print(time.perf_counter())')"
  python3 -c "print('TIME compile-native.vire samples/hello.vire {:.3f}s'.format(float('$end')-float('$start')))"
  echo "native hex emitted; PE execute unproven on this host unless Windows"
fi

echo "portable-check ok"
