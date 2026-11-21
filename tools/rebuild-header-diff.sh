#!/usr/bin/env bash
# Host vs native: allowlisted request headers + CRLF refusal on Set-Cookie/Location.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
export PATH="${HOME}/.dotnet:${PATH:-}"
export DOTNET_ROOT="${DOTNET_ROOT:-$HOME/.dotnet}"
export VIRE_HEADLESS=1
unset VIRE_BUDGET || true
unset FCG_API_TOKEN || true

AFTER_SHA="$(git rev-parse HEAD)"
BEFORE_SHA="b0d6fcb47359f3e771d4e4a92ac6f6a3b035061f"
VIRE_DLL="$ROOT/bin/Release/net10.0/vire.dll"
STAGE="$ROOT/data/native-headers"
mkdir -p "$STAGE" data

dotnet build vire.csproj -c Release --nologo
bash "$ROOT/tools/stage-compiler-src.sh"

hex_to_bin() {
  python3 - "$1" "$2" <<'PY'
import pathlib, sys
pathlib.Path(sys.argv[2]).write_bytes(bytes.fromhex(pathlib.Path(sys.argv[1]).read_text().strip()))
PY
}

echo "pass_after_sha $AFTER_SHA"
echo "fail_before_base $BEFORE_SHA"

cp "$ROOT/tests/rebuild/guests/header-inject.vire" "$STAGE/header-inject.vire"
rm -f "$STAGE/header-inject.hex" "$STAGE/header-inject.elf"
dotnet exec "$VIRE_DLL" --compiler compile-native.vire "data/native-headers/header-inject.vire" "data/native-headers/header-inject.hex"
hex_to_bin "$STAGE/header-inject.hex" "$STAGE/header-inject.elf"
chmod +x "$STAGE/header-inject.elf"

run_listen() {
  local name="$1"
  shift
  local out="/tmp/vire-hdr-${name}.out"
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
  kill "$1" 2>/dev/null || true
  wait "$1" 2>/dev/null || true
}

read HOST_PID HOST_PORT < <(run_listen hdr-host dotnet exec "$VIRE_DLL" "$STAGE/header-inject.vire")
read NAT_PID NAT_PORT < <(run_listen hdr-nat "$STAGE/header-inject.elf")
python3 - "$HOST_PORT" "$NAT_PORT" <<'PY'
import socket, sys

def raw(port, path, extra=""):
    req = f"GET {path} HTTP/1.1\r\nHost: example.test\r\nCookie: a=1\r\nAuthorization: Bearer z\r\nX-Evil: no\r\n{extra}Connection: close\r\n\r\n".encode()
    s = socket.create_connection(("127.0.0.1", int(port)), 5)
    s.sendall(req)
    s.settimeout(5)
    data = b""
    while True:
        try:
            c = s.recv(4096)
        except socket.timeout:
            break
        if not c:
            break
        data += c
    s.close()
    text = data.decode("utf-8", "replace")
    st = int(text.split(" ")[1])
    head, _, body = text.partition("\r\n\r\n")
    return st, head, body

for port, lab in [(sys.argv[1], "host"), (sys.argv[2], "native")]:
    st, head, body = raw(port, "/echo-head")
    if "Cookie: a=1" not in body or "Host: example.test" not in body or "Authorization: Bearer z" not in body:
        raise SystemExit(lab + " missing allowlisted head " + body)
    if "X-Evil" in body:
        raise SystemExit(lab + " leaked X-Evil")
    st, head, body = raw(port, "/set-ok")
    if st != 200 or "Set-Cookie: sid=safe; Path=/" not in head or "Location: /next" not in head:
        raise SystemExit(lab + " missing allowlisted reply " + head)
    for path in ("/inject-location", "/inject-cookie"):
        st, head, body = raw(port, path)
        if st != 500:
            raise SystemExit(lab + " " + path + " expected 500 got " + str(st) + " " + head)
        if "stolen=1" in head or "Location: /evil" in head:
            raise SystemExit(lab + " injected header escaped: " + head)
print("header allowlist + CRLF refusal host-vs-native match")
PY
stop_guest "$HOST_PID"
stop_guest "$NAT_PID"
echo "PASS_AFTER at $AFTER_SHA"
