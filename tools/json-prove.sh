#!/usr/bin/env bash
set -euo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$root"
export VIRE_BUDGET=5000000
export VIRE_HEADLESS=1
dll="$root/bin/Release/net10.0/vire.dll"
if [[ ! -f "$dll" ]]; then
  echo "missing $dll" >&2
  exit 1
fi

BASE_SHA="${JSON_FAIL_BEFORE_SHA:-9ea4561d12236f7f2f44858f137d7c948836df65}"
AFTER_SHA="$(git rev-parse HEAD)"
echo "fail_before_sha $BASE_SHA"
echo "pass_after_sha $AFTER_SHA"

wt="${RUNNER_TEMP:-/tmp}/vire-json-fail-before"
rm -rf "$wt"
git worktree add --detach "$wt" "$BASE_SHA"
(
  cd "$wt"
  dotnet build vire.csproj -c Release -o "$wt/out"
  cat > "$wt/json-fail-before.vire" <<'EOF'
define main
  let row be parse with "[01]"
  say "FAIL_BEFORE parse accepted [01] as " + (text with (row at 0)) + " at 9ea4561d12236f7f2f44858f137d7c948836df65"
end
EOF
  before=$(dotnet exec "$wt/out/vire.dll" json-fail-before.vire)
  echo "$before"
  echo "$before" | grep -q "FAIL_BEFORE parse accepted"
  echo "$before" | grep -q " as 1 "
  if [[ -f "$wt/src/rt-json.vire" ]]; then
    echo "base already has rt-json.vire" >&2
    exit 1
  fi
)
git worktree remove --force "$wt"
echo "FAIL_BEFORE at $BASE_SHA: builtin parse accepted [01]; src/rt-json.vire absent"

start=$(date +%s)
out=$(dotnet exec "$dll" json-prove.vire)
end=$(date +%s)
echo "$out"
echo "json_host_sec $((end-start))"
echo "$out" | grep -q "JSON PROVE pass"
echo "$out" | grep -q "y_true PASS"
echo "$out" | grep -q "y_string_u20ac enc PASS"
echo "$out" | grep -q "y_string_surrogate enc PASS"
echo "$out" | grep -q "stable keys PASS"
echo "$out" | grep -q "i_object_duplicate last-wins PASS"
echo "$out" | grep -q "n_number_leading_zero REJECT"
echo "$out" | grep -q "n_too_deep REJECT"
echo "$out" | grep -q "schema_check PASS"
echo "$out" | grep -q "FUZZ seed 20261113 PASS"
echo "PASS_AFTER host json-prove at $AFTER_SHA"

vec="$root/tests/json/vectors"
lib="$(cat "$root/src/rt-json.vire")"
run_vec() {
  local kind="$1" f="$2" want="$3"
  local name raw lit
  name="$(basename "$f")"
  lit="$(python3 -c 'import json,sys; print(json.dumps(sys.stdin.read()))' < "$f")"
  cat > "$root/json-vec-run.vire" <<EOF
$lib
define main
  let got be json_decode with $lit
  if (got at 0) != "$want"
    say "VEC FAIL $name"
    halt with 1
  end
  if "$want" == "ok"
    say "VEC $name PASS"
  else
    say "VEC $name REJECT"
  end
end
EOF
  vout=$(dotnet exec "$dll" json-vec-run.vire)
  echo "$vout"
  if [[ "$want" == "ok" ]]; then
    echo "$vout" | grep -q "VEC $name PASS"
  else
    echo "$vout" | grep -q "VEC $name REJECT"
  fi
  rm -f "$root/json-vec-run.vire"
}
for f in "$vec"/y_*.json; do run_vec y "$f" ok; done
for f in "$vec"/n_*.json; do run_vec n "$f" bad; done
for f in "$vec"/i_*.json; do run_vec i "$f" ok; done
echo "JSONTestSuite-style vectors host ok"
echo "json linux prove ok"
