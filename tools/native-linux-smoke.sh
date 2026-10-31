#!/usr/bin/env bash
# Native compiler smoke on Linux. Compiles hello plus every tests/native
# fixture to a static ELF (no libc) and checks stdout/stderr/exit against
# interpreter mode, except native-interp-ok overflow/heap cases that follow
# the Windows native safety errors.
set -euo pipefail
Root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$Root"
export VIRE_BUDGET=5000000
Work="$Root/data/native-linux-smoke"
rm -rf "$Work"
mkdir -p "$Work"

if [[ -f "$Root/bin/Release/net10.0/vire.dll" ]]; then
  Vire=(dotnet exec "$Root/bin/Release/net10.0/vire.dll")
else
  echo "missing vire build" >&2
  exit 1
fi

hex_to_bin() {
  python3 - "$1" "$2" <<'PY'
import sys
hexpath, outpath = sys.argv[1], sys.argv[2]
raw = open(hexpath, "r", encoding="utf-8").read().strip()
open(outpath, "wb").write(bytes.fromhex(raw))
PY
}

want_of() {
  local path="$1"
  local line
  while IFS= read -r line; do
    if [[ "$line" == "~ native-compile-error: "* ]]; then
      echo "compile|1|${line#~ native-compile-error: }"
      return
    fi
    if [[ "$line" == "~ native-error: "* ]]; then
      echo "error|1|${line#~ native-error: }"
      return
    fi
    if [[ "$line" == "~ native-ok: "* ]]; then
      echo "ok|0|${line#~ native-ok: }"
      return
    fi
  done < "$path"
  echo "missing native comment in $path" >&2
  exit 1
}

failed=0
run_one() {
  local name="$1"
  local src="$2"
  local kind="$3"
  local want_code="$4"
  local want_text="$5"
  local copy="$Work/$name.vire"
  cp "$src" "$copy"
  local src_rel="data/native-linux-smoke/$name.vire"
  local hex_rel="data/native-linux-smoke/$name.hex"
  set +e
  "${Vire[@]}" compile-native.vire "$src_rel" "$hex_rel" linux
  local cc=$?
  set -e
  if [[ "$kind" == "compile" ]]; then
    if [[ "$cc" -ne 0 ]]; then
      echo "PASS $name compile-error"
      return
    fi
    echo "FAIL compile $name expected compile error $want_text exit=$cc"
    failed=1
    return
  fi
  if [[ "$cc" -ne 0 ]]; then
    echo "FAIL compile $name exit=$cc"
    failed=1
    return
  fi
  local bin="$Work/$name.bin"
  hex_to_bin "$Root/$hex_rel" "$bin"
  chmod +x "$bin"
  if ! python3 - "$bin" <<'PY'
import sys
b = open(sys.argv[1], "rb").read(4)
if b != b"\x7fELF":
    sys.exit(1)
PY
  then
    echo "FAIL $name not ELF"
    failed=1
    return
  fi
  set +e
  local got
  got="$("$bin" 2>&1)"
  local exitc=$?
  set -e
  got="$(printf '%s' "$got" | tr -d '\r')"
  if [[ "$kind" == "ok" ]]; then
    if [[ "$got" == "$want_text" && "$exitc" -eq "$want_code" ]]; then
      echo "PASS $name"
      return
    fi
  else
    if [[ "$got" == *"$want_text"* && "$exitc" -eq "$want_code" ]]; then
      echo "PASS $name"
      return
    fi
  fi
  echo "FAIL run $name exit=$exitc wantExit=$want_code got=$got"
  failed=1
}

run_one hello samples/hello.vire ok 0 "hello from vire"
for path in tests/native/*.vire; do
  name="$(basename "$path" .vire)"
  meta="$(want_of "$path")"
  kind="${meta%%|*}"
  rest="${meta#*|}"
  code="${rest%%|*}"
  text="${rest#*|}"
  run_one "$name" "$path" "$kind" "$code" "$text"
done

if [[ "$failed" -ne 0 ]]; then
  exit 1
fi
echo "native linux smoke ok"
exit 0
