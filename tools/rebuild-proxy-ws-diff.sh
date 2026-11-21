#!/usr/bin/env bash
# Fail-before / pass-after: RFC 6455 upgrade through the reverse-proxy primitive.
# FAIL_BEFORE is PR #107 head (hop-by-hop strip of Upgrade). Linux ELF host-vs-native.
# Windows PE: tools/rebuild-proxy-ws-windows.ps1 (CouchStation).
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
export PATH="${HOME}/.dotnet:${PATH:-}"
export DOTNET_ROOT="${DOTNET_ROOT:-$HOME/.dotnet}"
export VIRE_HEADLESS=1
unset VIRE_BUDGET || true
unset FCG_API_TOKEN || true

AFTER_SHA="$(git rev-parse HEAD)"
BEFORE_SHA="cec3896320411cccdc016f59fedd1114ffb823e3"
VIRE_DLL="$ROOT/bin/Release/net10.0/vire.dll"
GUEST="$ROOT/tests/rebuild/guests/proxy-http.vire"
HTTP_NOW="$ROOT/src/http-client.vire"

python3 - <<'PY'
from pathlib import Path
rt = Path("src/rt.vire").read_text()
assert "33554432" in rt
cs = Path("Vire.cs").read_text()
assert "100000" in cs[:4000] or "100000" in cs
assert "5000000" in cs
print("caps_src_ok arena=33554432 list=100000 steps=5000000")
print("contract", Path("tests/rebuild/contracts/proxy/ws-echo.json").name)
PY

dotnet build vire.csproj -c Release --nologo
bash "$ROOT/tools/stage-compiler-src.sh"
mkdir -p data

hex_to_bin() {
  python3 - "$1" "$2" <<'PY'
import pathlib, sys
pathlib.Path(sys.argv[2]).write_bytes(bytes.fromhex(pathlib.Path(sys.argv[1]).read_text().strip()))
PY
}

STAGE="$ROOT/data/native-proxy-ws"
mkdir -p "$STAGE"
cp "$HTTP_NOW" "$STAGE/http-client.vire"
cp "$GUEST" "$STAGE/proxy-http.vire"

compile_guest() {
  local src="$1"
  local stem="$2"
  cp "$src" "$STAGE/${stem}.vire"
  rm -f "$STAGE/${stem}.hex" "$STAGE/${stem}.elf"
  dotnet exec "$VIRE_DLL" --compiler compile-native.vire "data/native-proxy-ws/${stem}.vire" "data/native-proxy-ws/${stem}.hex"
  hex_to_bin "$STAGE/${stem}.hex" "$STAGE/${stem}.elf"
  chmod +x "$STAGE/${stem}.elf"
}

echo "pass_after_sha $AFTER_SHA"
echo "fail_before_sha $BEFORE_SHA"

PORTFILE="/tmp/vire-proxy-ws-up-$$.port"
rm -f "$PORTFILE"

python3 - "$PORTFILE" <<'PY' &
import base64, hashlib, os, socket, sys, threading

GUID = "258EAFA5-E914-47DA-95CA-C5AB0DC85B11"

def hdr(lines, name):
    want = name.lower() + ":"
    for line in lines[1:]:
        if line.lower().startswith(want):
            return line.split(":", 1)[1].strip()
    return ""

def has_token(value, token):
    parts = [p.strip().lower() for p in value.split(",")]
    return token.lower() in parts

def read_exact(c, n, buf):
    while len(buf) < n:
        chunk = c.recv(4096)
        if not chunk:
            return None
        buf += chunk
    return buf

def handle(c):
    try:
        c.settimeout(5)
        data = b""
        while b"\r\n\r\n" not in data and len(data) < 16384:
            chunk = c.recv(4096)
            if not chunk:
                break
            data += chunk
        if b"\r\n\r\n" not in data:
            c.close()
            return
        head, rest = data.split(b"\r\n\r\n", 1)
        lines = head.decode("ascii", "replace").split("\r\n")
        req = lines[0] if lines else ""
        parts = req.split(" ")
        path = parts[1] if len(parts) > 1 else "/"
        method = parts[0] if parts else "GET"
        if path.startswith("/ws/refuse"):
            body = b"forbidden"
            c.sendall(b"HTTP/1.1 403 Error\r\nContent-Length: " + str(len(body)).encode("ascii") + b"\r\nConnection: close\r\n\r\n" + body)
            c.close()
            return
        if not path.startswith("/ws/"):
            c.sendall(b"HTTP/1.1 404 Error\r\nContent-Length: 0\r\n\r\n")
            c.close()
            return
        upgrade = hdr(lines, "upgrade")
        connection = hdr(lines, "connection")
        key = hdr(lines, "sec-websocket-key")
        version = hdr(lines, "sec-websocket-version")
        if method != "GET" or not has_token(upgrade, "websocket") or not has_token(connection, "upgrade") or version != "13" or len(key) != 24:
            c.sendall(b"HTTP/1.1 400 Error\r\nContent-Length: 0\r\nConnection: close\r\n\r\n")
            c.close()
            return
        accept = base64.b64encode(hashlib.sha1((key + GUID).encode("ascii")).digest())
        c.sendall(
            b"HTTP/1.1 101 Switching Protocols\r\nUpgrade: websocket\r\nConnection: Upgrade\r\nSec-WebSocket-Accept: "
            + accept
            + b"\r\n\r\n"
        )
        buf = rest
        while True:
            buf = read_exact(c, 2, buf)
            if buf is None:
                break
            b0 = buf[0]
            b1 = buf[1]
            op = b0 & 0x0F
            masked = (b1 & 0x80) != 0
            ln = b1 & 0x7F
            off = 2
            if ln == 126:
                buf = read_exact(c, off + 2, buf)
                if buf is None:
                    break
                ln = (buf[2] << 8) | buf[3]
                off = 4
            elif ln == 127:
                c.close()
                return
            need = off + (4 if masked else 0) + ln
            buf = read_exact(c, need, buf)
            if buf is None:
                break
            payload = buf[off:]
            if masked:
                mask = payload[:4]
                payload = payload[4:4 + ln]
                payload = bytes(payload[i] ^ mask[i & 3] for i in range(len(payload)))
            else:
                payload = payload[:ln]
            buf = buf[need:]
            if op == 8:
                c.sendall(bytes([0x88, 0x00]))
                break
            if op == 9:
                c.sendall(bytes([0x8A, len(payload)]) + payload)
                continue
            if op in (1, 2):
                if ln < 126:
                    c.sendall(bytes([0x80 | op, ln]) + payload)
                else:
                    c.sendall(bytes([0x80 | op, 126, (ln >> 8) & 0xFF, ln & 0xFF]) + payload)
        c.close()
    except Exception:
        try:
            c.close()
        except Exception:
            pass

s = socket.socket()
s.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
s.bind(("127.0.0.1", 0))
s.listen(32)
port = s.getsockname()[1]
open(sys.argv[1], "w").write(str(port))
print("upstream 127.0.0.1:%s" % port, flush=True)
while True:
    c, _ = s.accept()
    threading.Thread(target=handle, args=(c,), daemon=True).start()
PY
UP_PID=$!
for i in $(seq 1 50); do
  if [[ -f "$PORTFILE" ]]; then break; fi
  sleep 0.05
done
UP="$(cat "$PORTFILE")"
echo "upstream_port $UP"

echo "=== FAIL_BEFORE (PR #107 http-client at $BEFORE_SHA) ==="
git show "$BEFORE_SHA:src/http-client.vire" > "$STAGE/http-client.vire"
FAIL_OUT="$(dotnet exec "$VIRE_DLL" data/native-proxy-ws/proxy-http.vire "$UP" proxy-ws || true)"
echo "$FAIL_OUT"
if echo "$FAIL_OUT" | grep -q "81026869"; then
  echo "FAIL_BEFORE unexpectedly tunneled echo"
  kill "$UP_PID" 2>/dev/null || true
  exit 1
fi
if echo "$FAIL_OUT" | grep -qx "101"; then
  echo "FAIL_BEFORE unexpectedly returned 101"
  kill "$UP_PID" 2>/dev/null || true
  exit 1
fi
echo "FAIL_BEFORE at $BEFORE_SHA websocket handshake failed as required"

cp "$HTTP_NOW" "$STAGE/http-client.vire"
compile_guest "$GUEST" "proxy-http"

run_pair() {
  local mode="$1"
  local want="$2"
  echo "--- mode $mode ---"
  HOST_OUT="$(dotnet exec "$VIRE_DLL" data/native-proxy-ws/proxy-http.vire "$UP" "$mode")"
  NAT_OUT="$(./data/native-proxy-ws/proxy-http.elf "$UP" "$mode")"
  echo "host_out ${HOST_OUT//$'\n'/ | }"
  echo "native_out ${NAT_OUT//$'\n'/ | }"
  if [[ "$HOST_OUT" != "$NAT_OUT" ]]; then
    echo "HOST_NATIVE_MISMATCH mode $mode"
    kill "$UP_PID" 2>/dev/null || true
    exit 3
  fi
  if [[ -n "$want" ]]; then
    if ! echo "$HOST_OUT" | grep -q "$want"; then
      echo "missing $want in $mode"
      kill "$UP_PID" 2>/dev/null || true
      exit 2
    fi
  fi
  echo "HOST_NATIVE_MATCH mode $mode"
}

run_pair proxy-ws "810268698800"
run_pair proxy-ws "s3pPLMBiTxaQ9kYGzzhZRbK+xOo="
run_pair proxy-ws-bad "400"
run_pair proxy-ws-refuse "403"

echo "HOST_NATIVE_MATCH"
echo "PASS_AFTER at $AFTER_SHA"
kill "$UP_PID" 2>/dev/null || true
wait "$UP_PID" 2>/dev/null || true
echo "rebuild proxy ws diff ok"
