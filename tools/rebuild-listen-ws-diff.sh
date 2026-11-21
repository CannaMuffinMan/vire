#!/usr/bin/env bash
# Listen-side RFC 6455 Upgrade hijack: client -> Vire listen -> loopback WS upstream.
# FAIL_BEFORE: PR #125 head 69048e0d (proxy tunnel only; listen wraps JSON).
# Host VireListen vs native ELF transcripts. Caps 32MB / 100000 / 5M.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
export PATH="${HOME}/.dotnet:${PATH:-}"
export DOTNET_ROOT="${DOTNET_ROOT:-$HOME/.dotnet}"
export VIRE_HEADLESS=1
unset VIRE_BUDGET || true
unset FCG_API_TOKEN || true

AFTER_SHA="$(git rev-parse HEAD)"
BEFORE_SHA="69048e0d7537e7945bdefd3148e251ee88ab1fc4"
VIRE_DLL="$ROOT/bin/Release/net10.0/vire.dll"
GUEST="$ROOT/tests/rebuild/guests/listen-ws.vire"

python3 - <<'PY'
from pathlib import Path
rt = Path("src/rt.vire").read_text()
assert "33554432" in rt
cs = Path("Vire.cs").read_text()
assert "100000" in cs[:4000] or "100000" in cs
assert "5000000" in cs
print("caps_src_ok arena=33554432 list=100000 steps=5000000")
print("contract", Path("tests/rebuild/contracts/listen-ws.json").name)
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

STAGE="$ROOT/data/native-listen-ws"
mkdir -p "$STAGE"
cp "$GUEST" "$STAGE/listen-ws.vire"

compile_guest() {
  local src="$1"
  local stem="$2"
  cp "$src" "$STAGE/${stem}.vire"
  rm -f "$STAGE/${stem}.hex" "$STAGE/${stem}.elf"
  dotnet exec "$VIRE_DLL" --compiler compile-native.vire "data/native-listen-ws/${stem}.vire" "data/native-listen-ws/${stem}.hex"
  hex_to_bin "$STAGE/${stem}.hex" "$STAGE/${stem}.elf"
  chmod +x "$STAGE/${stem}.elf"
}

echo "pass_after_sha $AFTER_SHA"
echo "fail_before_sha $BEFORE_SHA"

if git cat-file -e "${BEFORE_SHA}^{commit}" 2>/dev/null; then
  if git show "${BEFORE_SHA}:VireListen.cs" | grep -q "TryWsHijack"; then
    echo "FAIL_BEFORE marker missing: base already hijacks"
    exit 1
  fi
  echo "FAIL_BEFORE at $BEFORE_SHA VireListen has no TryWsHijack (listen wrapped Upgrade as HTTP JSON)"
else
  echo "FAIL_BEFORE sha $BEFORE_SHA not in this clone"
  exit 1
fi

PORTFILE="/tmp/vire-listen-ws-up-$$.port"
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
        upgrade = hdr(lines, "upgrade")
        connection = hdr(lines, "connection")
        key = hdr(lines, "sec-websocket-key")
        version = hdr(lines, "sec-websocket-version")
        if method != "GET" or not has_token(upgrade, "websocket") or not has_token(connection, "upgrade") or version != "13" or len(key) != 24:
            c.sendall(b"HTTP/1.1 400 Error\r\nContent-Length: 0\r\nConnection: close\r\n\r\n")
            c.close()
            return
        accept = base64.b64encode(hashlib.sha1((key + GUID).encode("ascii")).digest())
        c.sendall(b"HTTP/1.1 101 Switching Protocols\r\nUpgrade: websocket\r\nConnection: Upgrade\r\nSec-WebSocket-Accept: " + accept + b"\r\n\r\n")
        buf = rest
        while True:
            buf = read_exact(c, 2, buf)
            if buf is None:
                break
            b0, b1 = buf[0], buf[1]
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
                c.sendall(bytes([0x80 | op, ln]) + payload)
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

compile_guest "$GUEST" "listen-ws"

run_listen() {
  local bin="$1"
  local out="$2"
  rm -f "$out"
  "$bin" "$UP" >"$out" 2>&1 &
  echo $!
}

wait_port() {
  local out="$1"
  local i
  for i in $(seq 1 200); do
    if grep -q "listening on 127.0.0.1:" "$out" 2>/dev/null; then
      sed -n 's/.*listening on 127.0.0.1:\([0-9]*\).*/\1/p' "$out" | head -1
      return 0
    fi
    sleep 0.05
  done
  cat "$out"
  echo "no listen port"
  return 1
}

transcript() {
  python3 - "$1" "$2" <<'PY'
import socket, sys
port = int(sys.argv[1])
mode = sys.argv[2]
req_bad = (
    b"GET /ws/echo HTTP/1.1\r\nHost: 127.0.0.1\r\nUpgrade: h2c\r\nConnection: Upgrade\r\n\r\n"
)
req_ok = (
    b"GET /ws/echo HTTP/1.1\r\nHost: 127.0.0.1\r\nUpgrade: websocket\r\nConnection: Upgrade\r\n"
    b"Sec-WebSocket-Key: dGhlIHNhbXBsZSBub25jZQ==\r\nSec-WebSocket-Version: 13\r\n\r\n"
)
req_ref = (
    b"GET /ws/refuse HTTP/1.1\r\nHost: 127.0.0.1\r\nUpgrade: websocket\r\nConnection: Upgrade\r\n"
    b"Sec-WebSocket-Key: dGhlIHNhbXBsZSBub25jZQ==\r\nSec-WebSocket-Version: 13\r\n\r\n"
)
s = socket.create_connection(("127.0.0.1", port), 5)
s.settimeout(5)
if mode == "bad":
    s.sendall(req_bad)
    data = s.recv(4096)
    s.close()
    sys.stdout.buffer.write(data)
    sys.exit(0)
if mode == "refuse":
    s.sendall(req_ref)
    data = s.recv(4096)
    s.close()
    sys.stdout.buffer.write(data)
    sys.exit(0)
s.sendall(req_ok)
buf = b""
while b"\r\n\r\n" not in buf:
    chunk = s.recv(4096)
    if not chunk:
        break
    buf += chunk
head, rest = buf.split(b"\r\n\r\n", 1) if b"\r\n\r\n" in buf else (buf, b"")
# text hi, ping, close
frames = bytes([0x81, 0x82, 0, 0, 0, 0]) + b"hi" + bytes([0x89, 0x80, 0, 0, 0, 0]) + bytes([0x88, 0x80, 0, 0, 0, 0])
s.sendall(frames)
got = rest
while len(got) < 16:
    chunk = s.recv(4096)
    if not chunk:
        break
    got += chunk
s.close()
sys.stdout.buffer.write(head + b"\r\n\r\n" + got)
PY
}

HOST_PID="$(run_listen "dotnet exec $VIRE_DLL data/native-listen-ws/listen-ws.vire" /tmp/vire-listen-ws-host.out)"
HPORT="$(wait_port /tmp/vire-listen-ws-host.out)"
NAT_PID="$(run_listen "$STAGE/listen-ws.elf" /tmp/vire-listen-ws-nat.out)"
NPORT="$(wait_port /tmp/vire-listen-ws-nat.out)"
echo "host_listen $HPORT native_listen $NPORT"

compare_mode() {
  local mode="$1"
  local want="$2"
  HOST_T="$(transcript "$HPORT" "$mode" | python3 -c 'import sys; d=sys.stdin.buffer.read(); print(d.hex() if sys.argv[1]=="echo" else d.decode("latin1","replace"))' "$mode")"
  NAT_T="$(transcript "$NPORT" "$mode" | python3 -c 'import sys; d=sys.stdin.buffer.read(); print(d.hex() if sys.argv[1]=="echo" else d.decode("latin1","replace"))' "$mode")"
  echo "--- mode $mode ---"
  echo "host ${HOST_T//$'\n'/ | }"
  echo "native ${NAT_T//$'\n'/ | }"
  if [[ "$HOST_T" != "$NAT_T" ]]; then
    echo "HOST_NATIVE_MISMATCH mode $mode"
    kill "$HOST_PID" "$NAT_PID" "$UP_PID" 2>/dev/null || true
    exit 3
  fi
  if [[ -n "$want" ]] && ! echo "$HOST_T" | grep -q "$want"; then
    echo "missing $want"
    kill "$HOST_PID" "$NAT_PID" "$UP_PID" 2>/dev/null || true
    exit 2
  fi
  echo "HOST_NATIVE_MATCH mode $mode"
}

# echo mode prints hex of full transcript
HOST_E="$(transcript "$HPORT" echo | python3 -c 'import sys; print(sys.stdin.buffer.read().hex())')"
NAT_E="$(transcript "$NPORT" echo | python3 -c 'import sys; print(sys.stdin.buffer.read().hex())')"
echo "host_echo_hex $HOST_E"
echo "native_echo_hex $NAT_E"
if [[ "$HOST_E" != "$NAT_E" ]]; then
  echo "HOST_NATIVE_MISMATCH echo hex"
  kill "$HOST_PID" "$NAT_PID" "$UP_PID" 2>/dev/null || true
  exit 3
fi
echo "$HOST_E" | grep -q "81026869" || { echo "missing text echo"; exit 2; }
echo "$HOST_E" | grep -q "8a00" || { echo "missing pong"; exit 2; }
echo "$HOST_E" | grep -q "8800" || { echo "missing close"; exit 2; }
python3 - <<PY
t = bytes.fromhex("$HOST_E")
assert t.startswith(b"HTTP/1.1 101 Switching Protocols\r\n")
assert b"Upgrade: websocket" in t
assert b"Sec-WebSocket-Accept: s3pPLMBiTxaQ9kYGzzhZRbK+xOo=" in t
print("echo_headers_ok")
PY

compare_mode bad "400"
compare_mode refuse "403"

echo "HOST_NATIVE_MATCH"
echo "PASS_AFTER at $AFTER_SHA"
kill "$HOST_PID" "$NAT_PID" "$UP_PID" 2>/dev/null || true
wait "$HOST_PID" "$NAT_PID" "$UP_PID" 2>/dev/null || true
echo "rebuild listen ws diff ok"
