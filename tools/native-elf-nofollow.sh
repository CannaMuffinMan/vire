#!/usr/bin/env bash
# FAIL_BEFORE: Linux ELF CreateFile shim uses open(2) and follows parent/leaf
# symlinks. PASS_AFTER: openat(O_NOFOLLOW) refuses; outside stays KEEP.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
export PATH="${HOME}/.dotnet:${PATH:-}"
export DOTNET_ROOT="${DOTNET_ROOT:-$HOME/.dotnet}"
export VIRE_HEADLESS=1
unset VIRE_BUDGET || true
BEFORE_SHA="${NATIVE_ELF_NOFOLLOW_BEFORE:-6d5414b2e0a26ef2f8148846edc59cf5dbded278}"
AFTER_SHA="$(git rev-parse HEAD)"
echo "fail_before_sha $BEFORE_SHA"
echo "pass_after_sha $AFTER_SHA"

hex_to_bin() {
  python3 - "$1" "$2" <<'PY'
import pathlib, sys
p = pathlib.Path(sys.argv[1])
pathlib.Path(sys.argv[2]).write_bytes(bytes.fromhex(p.read_text().strip()))
PY
}

WORKDIR="$(mktemp -d)"
cleanup() { rm -rf "$WORKDIR"; }
trap cleanup EXIT

probe_elf() {
  local tree="$1"
  local tag="$2"
  mkdir -p "$tree/data" "$WORKDIR/outside-$tag"
  printf 'KEEP\n' > "$WORKDIR/outside-$tag/note.txt"
  cat > "$tree/data/nf-write.vire" <<'EOF'
define main
  write with "data/note.txt", "HACKED"
end
EOF
  (
    cd "$tree"
    unset VIRE_BUDGET || true
    dotnet exec bin/Release/net10.0/vire.dll --compiler compile-native.vire data/nf-write.vire data/nf-write.hex
  )
  hex_to_bin "$tree/data/nf-write.hex" "$WORKDIR/nf-$tag.bin"
  chmod +x "$WORKDIR/nf-$tag.bin"
  rm -rf "$tree/data"
  ln -s "$WORKDIR/outside-$tag" "$tree/data"
  set +e
  ( cd "$tree" && strace -e open,openat -o "$WORKDIR/trace-$tag.txt" -- "$WORKDIR/nf-$tag.bin" ) >"$WORKDIR/run-$tag.out" 2>&1
  local code=$?
  set -e
  local body
  body="$(tr -d '\r\n' < "$WORKDIR/outside-$tag/note.txt")"
  echo "${tag}_exit $code"
  echo "${tag}_outside $body"
  echo "${tag}_stdout $(tr '\n' ' ' < "$WORKDIR/run-$tag.out")"
  echo "${tag}_trace $(tr '\n' '|' < "$WORKDIR/trace-$tag.txt" | head -c 400)"
  if [[ "$tag" == "before" ]]; then
    if ! grep -E 'open(at)?\(' "$WORKDIR/trace-$tag.txt" | grep -v O_NOFOLLOW | grep -q .; then
      echo "FAIL_BEFORE expected open(2) without O_NOFOLLOW at $BEFORE_SHA" >&2
      cat "$WORKDIR/trace-$tag.txt" >&2
      exit 1
    fi
    if grep -q O_NOFOLLOW "$WORKDIR/trace-$tag.txt"; then
      echo "FAIL_BEFORE unexpected O_NOFOLLOW at $BEFORE_SHA" >&2
      exit 1
    fi
  else
    if [[ "$body" != "KEEP" ]]; then
      echo "PASS_AFTER expected outside KEEP, got $body" >&2
      exit 1
    fi
    if ! grep -q O_NOFOLLOW "$WORKDIR/trace-$tag.txt"; then
      echo "PASS_AFTER missing O_NOFOLLOW openat" >&2
      cat "$WORKDIR/trace-$tag.txt" >&2
      exit 1
    fi
    if grep -E '^open\(' "$WORKDIR/trace-$tag.txt" | grep -q .; then
      echo "PASS_AFTER still uses open()" >&2
      cat "$WORKDIR/trace-$tag.txt" >&2
      exit 1
    fi
  fi
}

host_write_probe() {
  local tree="$1"
  local tag="$2"
  local out="$WORKDIR/host-out-$tag"
  mkdir -p "$tree/data" "$out"
  printf 'KEEP' > "$out/note.txt"
  rm -rf "$tree/data"
  ln -s "$out" "$tree/data"
  cat > "$tree/data-host.vire" <<'EOF'
define main
  write with "data/note.txt", "HACKED"
end
EOF
  # program folder is tree; but write sandbox is tree/data via the symlink
  printf 'define main\n  write with "data/note.txt", "HACKED"\nend\n' > "$tree/host-nf.vire"
  rm -rf "$tree/data"
  mkdir -p "$tree/data"
  # leaf/parent: replace data dir with symlink after placing the program
  rmdir "$tree/data" 2>/dev/null || rm -rf "$tree/data"
  ln -s "$out" "$tree/data"
  set +e
  ( cd "$tree" && unset VIRE_BUDGET && dotnet exec bin/Release/net10.0/vire.dll host-nf.vire ) >"$WORKDIR/host-$tag.out" 2>&1
  local code=$?
  set -e
  local body
  body="$(cat "$out/note.txt")"
  echo "host_${tag}_exit $code"
  echo "host_${tag}_outside $body"
  if [[ "$tag" == "before" ]]; then
    if [[ "$body" != "HACKED" ]]; then
      echo "FAIL_BEFORE host write should follow data/ symlink" >&2
      cat "$WORKDIR/host-$tag.out" >&2
      exit 1
    fi
  else
    if [[ "$body" != "KEEP" ]]; then
      echo "PASS_AFTER host write followed symlink" >&2
      cat "$WORKDIR/host-$tag.out" >&2
      exit 1
    fi
  fi
}

if ! git cat-file -t "$BEFORE_SHA" >/dev/null 2>&1; then
  git fetch origin "$BEFORE_SHA"
fi
git clone --quiet --no-hardlinks --no-checkout "$ROOT" "$WORKDIR/base"
git -C "$WORKDIR/base" checkout --quiet "$BEFORE_SHA"
dotnet build "$WORKDIR/base/vire.csproj" -c Release --nologo >/tmp/native-elf-nofollow-before-build.log
probe_elf "$WORKDIR/base" before
echo "FAIL_BEFORE at $BEFORE_SHA ELF CreateFile shim used open() without O_NOFOLLOW (followed data/)"

dotnet build "$ROOT/vire.csproj" -c Release --nologo
mkdir -p "$WORKDIR/after"
tar -C "$ROOT" --exclude=.git --exclude=bin --exclude=obj --exclude=tests/Vire.Tests/bin --exclude=tests/Vire.Tests/obj -cf - . | tar -C "$WORKDIR/after" -xf -
cp -a "$ROOT/bin" "$WORKDIR/after/bin"
probe_elf "$WORKDIR/after" after
host_write_probe "$WORKDIR/after" after
echo "PASS_AFTER at $AFTER_SHA ELF openat O_NOFOLLOW; host write outside=KEEP"

# Host compiler output leaf symlink (isolated tree)
OUT="$WORKDIR/host-out"
HOST="$WORKDIR/host"
mkdir -p "$HOST/data" "$OUT"
cp "$ROOT/bin/Release/net10.0/vire.dll" "$HOST/" 2>/dev/null || true
printf 'KEEP' > "$OUT/guest-hello.hex"
ln -s "$OUT/guest-hello.hex" "$HOST/data/nf-host.hex"
cp "$ROOT/guest-hello.vire" "$HOST/data/guest-hello.vire"
cp "$ROOT/compile-native.vire" "$HOST/"
mkdir -p "$HOST/src"
cp -a "$ROOT/src/." "$HOST/src/"
set +e
( cd "$HOST" && unset VIRE_BUDGET && dotnet exec "$ROOT/bin/Release/net10.0/vire.dll" --compiler compile-native.vire data/guest-hello.vire data/nf-host.hex ) >"$WORKDIR/host-leaf.out" 2>&1
host_code=$?
set -e
echo "host_leaf_exit $host_code"
echo "host_leaf_body $(tr -d '\r\n' < "$OUT/guest-hello.hex" | head -c 16)"
if [[ "$(cat "$OUT/guest-hello.hex")" == "KEEP" && "$host_code" -ne 0 ]]; then
  echo "PASS_AFTER host compiler leaf symlink refused"
else
  echo "host compiler leaf symlink was followed or succeeded" >&2
  cat "$WORKDIR/host-leaf.out" >&2
  exit 1
fi
echo "native elf nofollow ok"
