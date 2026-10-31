#!/bin/sh
set -u
root=$(CDPATH= cd -- "$(dirname "$0")" && pwd)
out="$root/observed"
mkdir -p "$out"

run() {
  name=$1
  shift
  echo "=== $name ==="
  "$@" >"$out/$name.out" 2>"$out/$name.err"
  code=$?
  echo "$code" >"$out/$name.exit"
  echo "exit $code"
  echo "--- stdout ---"
  cat "$out/$name.out"
  echo "--- stderr ---"
  cat "$out/$name.err"
}

run red-suite sudo docker run --rm vire-red tests.vire
run green-suite sudo docker run --rm vire tests.vire
run green-offline sudo docker run --rm --network none vire tests.vire

cat >"$out/hashvec.vire" <<'EOF'
define main
  say hash with "abc"
  say hash with ""
end
EOF
run hash-vector sudo docker run --rm -v "$out/hashvec.vire:/work/hashvec.vire:ro" vire hashvec.vire

cat >"$out/https.vire" <<'EOF'
define main
  say fetch with "https://example.com/"
end
EOF
run https-bare sudo docker run --rm -v "$out/https.vire:/work/https.vire:ro" vire https.vire
run https-with-host-ca sudo docker run --rm \
  -v /etc/ssl/certs/ca-certificates.crt:/etc/ssl/certs/ca-certificates.crt:ro \
  -v "$out/https.vire:/work/https.vire:ro" \
  vire https.vire

echo "abc ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad" >"$out/hash-expected.txt"
echo "empty e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855" >>"$out/hash-expected.txt"
