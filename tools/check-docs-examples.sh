#!/usr/bin/env bash
# Run docs/examples in interpreter and compiled modes; compare stdout/stderr/exit.
#   bash tools/check-docs-examples.sh
#   bash tools/check-docs-examples.sh --prove-broken
#   bash tools/check-docs-examples.sh --capture
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

MODE="check"
if [[ "${1:-}" == "--prove-broken" ]]; then MODE="prove-broken"; fi
if [[ "${1:-}" == "--capture" ]]; then MODE="capture"; fi

export VIRE_BUDGET="${VIRE_BUDGET:-5000000}"
if [[ -z "${VIRE_SEAL_KEY:-}" ]]; then
  export VIRE_SEAL_KEY="$(python3 -c 'import os,base64; print(base64.b64encode(os.urandom(32)).decode())')"
fi

if [[ -f "$ROOT/bin/Release/net10.0/vire.dll" ]]; then
  VIRE=( dotnet exec "$ROOT/bin/Release/net10.0/vire.dll" )
else
  dotnet build "$ROOT/vire.csproj" -c Release --nologo
  VIRE=( dotnet exec "$ROOT/bin/Release/net10.0/vire.dll" )
fi

norm() { python3 -c 'import sys; sys.stdout.write(sys.stdin.read().replace("\r\n","\n"))'; }

EX_SRC="$ROOT/docs/examples"
WORKDIR="$ROOT/data/docs-examples-run"
rm -rf "$WORKDIR"
mkdir -p "$WORKDIR"
cp -a "$EX_SRC/." "$WORKDIR/"

cp "$ROOT/compiler.vire" "$ROOT/data/docs-examples-compiler.vire"
rm -f "$ROOT/data/docs-examples-compiler.vc"
echo "compile compiler.vire once"
"${VIRE[@]}" compiler.vire data/docs-examples-compiler.vire data/docs-examples-compiler.vc >/dev/null

is_example() {
  local base="$1"
  local name dir
  name="$(basename "$base" .vire)"
  dir="$(dirname "$base")"
  if [[ "$MODE" == "capture" ]]; then
    case "$base" in
      */helpers/*|*/deps/*) return 1 ;;
    esac
    return 0
  fi
  [[ -f "$dir/$name.stdout" || -f "$dir/$name.stderr" || -f "$dir/$name.exit" ]]
}

read_exit() {
  local f="$1"
  if [[ -f "$f" ]]; then tr -d ' \t\r\n' < "$f"; else echo 0; fi
}

rel_under_data() {
  python3 -c 'import os,sys; print(os.path.normpath(sys.argv[1]))' "docs-examples-run/$1"
}

run_pair() {
  local rel="$1"
  local name dir
  name="$(basename "$rel" .vire)"
  dir="$(dirname "$rel")"
  if [[ "$dir" == "." ]]; then dir=""; fi
  local work="$WORKDIR"
  if [[ -n "$dir" ]]; then work="$WORKDIR/$dir"; fi
  mkdir -p "$work/data" "$work/site"
  local extra=()
  local argsfile="$work/$name.args"
  if [[ -f "$argsfile" ]]; then
    while IFS= read -r line || [[ -n "$line" ]]; do
      [[ -z "$line" ]] && continue
      extra+=("$line")
    done < "$argsfile"
  fi

  local i_out i_err i_code c_out c_err c_code
  i_out="$("${VIRE[@]}" "$work/$name.vire" "${extra[@]+"${extra[@]}"}" 2>"$work/$name.interp.err" | norm)"
  i_code=$?
  i_err="$(norm < "$work/$name.interp.err")"

  local leaf="$name.vire"
  if [[ -n "$dir" ]]; then leaf="$dir/$name.vire"; fi
  local src_arg dest_arg
  src_arg="$(rel_under_data "$leaf")"
  dest_arg="${src_arg%.vire}.vc"

  "${VIRE[@]}" run data/docs-examples-compiler.vc "$src_arg" "$dest_arg" >"$work/$name.compile.out" 2>"$work/$name.compile.err"
  local compile_code=$?
  if [[ $compile_code -ne 0 ]]; then
    echo "compile failed for $rel" >&2
    cat "$work/$name.compile.out" >&2
    cat "$work/$name.compile.err" >&2
    return 1
  fi

  c_out="$("${VIRE[@]}" run "data/$dest_arg" "${extra[@]+"${extra[@]}"}" 2>"$work/$name.comp.err" | norm)"
  c_code=$?
  c_err="$(norm < "$work/$name.comp.err")"

  if [[ "$i_out" != "$c_out" || "$i_err" != "$c_err" || "$i_code" != "$c_code" ]]; then
    echo "mode mismatch $rel" >&2
    echo " interp exit $i_code compiled exit $c_code" >&2
    echo " --- interp stdout ---" >&2
    printf '%s' "$i_out" >&2; echo >&2
    echo " --- compiled stdout ---" >&2
    printf '%s' "$c_out" >&2; echo >&2
    echo " --- interp stderr ---" >&2
    printf '%s' "$i_err" >&2; echo >&2
    echo " --- compiled stderr ---" >&2
    printf '%s' "$c_err" >&2; echo >&2
    return 1
  fi

  local want_out="" want_err="" want_code
  local src_dir="$EX_SRC"
  if [[ -n "$dir" ]]; then src_dir="$EX_SRC/$dir"; fi
  if [[ -f "$src_dir/$name.stdout" ]]; then
    want_out="$(norm < "$src_dir/$name.stdout")"
  fi
  if [[ -f "$src_dir/$name.stderr" ]]; then
    want_err="$(norm < "$src_dir/$name.stderr")"
  fi
  want_code="$(read_exit "$src_dir/$name.exit")"

  if [[ "$MODE" == "capture" ]]; then
    printf '%s' "$i_out" > "$src_dir/$name.stdout"
    if [[ -n "$i_err" ]]; then printf '%s' "$i_err" > "$src_dir/$name.stderr"; else rm -f "$src_dir/$name.stderr"; fi
    if [[ "$i_code" != "0" ]]; then echo "$i_code" > "$src_dir/$name.exit"; fi
    echo "captured $rel"
    return 0
  fi

  if [[ "$i_out" != "$want_out" || "$i_err" != "$want_err" || "$i_code" != "$want_code" ]]; then
    echo "expected mismatch $rel" >&2
    echo " exit got $i_code want $want_code" >&2
    echo " --- got stdout ---" >&2
    printf '%s' "$i_out" >&2; echo >&2
    echo " --- want stdout ---" >&2
    printf '%s' "$want_out" >&2; echo >&2
    echo " --- got stderr ---" >&2
    printf '%s' "$i_err" >&2; echo >&2
    echo " --- want stderr ---" >&2
    printf '%s' "$want_err" >&2; echo >&2
    return 1
  fi
  echo "ok $rel"
}

run_all() {
  set +e
  local failed=0
  local path rel
  while IFS= read -r path; do
    rel="${path#"$EX_SRC"/}"
    case "$rel" in
      helpers/*|deps/*) continue ;;
    esac
    if ! is_example "$path"; then continue; fi
    if ! run_pair "$rel"; then failed=1; fi
  done < <(find "$EX_SRC" -name '*.vire' | sort)
  return $failed
}

if [[ "$MODE" == "prove-broken" ]]; then
  if [[ ! -f "$EX_SRC/language-core.stdout" ]]; then
    echo "prove-broken needs language-core.stdout" >&2
    exit 1
  fi
  orig="$(cat "$EX_SRC/language-core.stdout")"
  printf 'BROKEN EXPECTED OUTPUT\n' > "$EX_SRC/language-core.stdout"
  set +e
  run_all
  status=$?
  set -e
  printf '%s' "$orig" > "$EX_SRC/language-core.stdout"
  if [[ $status -eq 0 ]]; then
    echo "prove-broken: checker accepted a bad expected file" >&2
    exit 1
  fi
  echo "prove-broken: checker rejected the bad example"
  exit 0
fi

run_all
echo "docs-examples ok"
