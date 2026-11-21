#!/usr/bin/env bash
# Fail-before / pass-after for loopback HTTP/1.1 client + reverse-proxy primitive.
# Linux ELF host-vs-native. Windows PE: tools/rebuild-proxy-windows.ps1 (CouchStation).
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
export PATH="${HOME}/.dotnet:${PATH:-}"
export DOTNET_ROOT="${DOTNET_ROOT:-$HOME/.dotnet}"
export VIRE_HEADLESS=1
unset VIRE_BUDGET || true
unset FCG_API_TOKEN || true

AFTER_SHA="$(git rev-parse HEAD)"
BEFORE_SHA="4682595ee586c7440d06bdc2979b8b7e2c94812d"
VIRE_DLL="$ROOT/bin/Release/net10.0/vire.dll"
GUEST="$ROOT/tests/rebuild/guests/proxy-http.vire"
FAIL_GUEST="$ROOT/tests/rebuild/guests/proxy-fail.vire"

dotnet build vire.csproj -c Release --nologo
bash "$ROOT/tools/stage-compiler-src.sh"
mkdir -p data

hex_to_bin() {
  python3 - "$1" "$2" <<'PY'
import pathlib, sys
pathlib.Path(sys.argv[2]).write_bytes(bytes.fromhex(pathlib.Path(sys.argv[1]).read_text().strip()))
PY
}

STAGE="$ROOT/data/native-proxy"
mkdir -p "$STAGE"
cp "$ROOT/src/http-client.vire" "$STAGE/http-client.vire"

compile_guest() {
  local src="$1"
  local stem="$2"
  cp "$src" "$STAGE/${stem}.vire"
  rm -f "$STAGE/${stem}.hex" "$STAGE/${stem}.elf"
  dotnet exec "$VIRE_DLL" --compiler compile-native.vire "data/native-proxy/${stem}.vire" "data/native-proxy/${stem}.hex"
  hex_to_bin "$STAGE/${stem}.hex" "$STAGE/${stem}.elf"
  chmod +x "$STAGE/${stem}.elf"
}

echo "pass_after_sha $AFTER_SHA"
echo "fail_before_base $BEFORE_SHA"

PORTFILE="/tmp/vire-proxy-up-$$.port"
rm -f "$PORTFILE" /tmp/vire-proxy-up.port

python3 - "$PORTFILE" <<'PY' &
import socket, threading, os, time, sys

def handle(c):
    try:
        c.settimeout(2)
        data = b""
        while b"\r\n\r\n" not in data and len(data) < 65536:
            chunk = c.recv(4096)
            if not chunk:
                break
            data += chunk
        head = data.split(b"\r\n\r\n", 1)[0].decode("ascii", "replace")
        lines = head.split("\r\n")
        req = lines[0] if lines else ""
        parts = req.split(" ")
        path = parts[1] if len(parts) > 1 else "/"
        method = parts[0] if parts else "GET"
        body = b""
        if method == "POST":
            cl = 0
            for line in lines[1:]:
                if line.lower().startswith("content-length:"):
                    cl = int(line.split(":", 1)[1].strip())
            rest = data.split(b"\r\n\r\n", 1)[1] if b"\r\n\r\n" in data else b""
            while len(rest) < cl:
                rest += c.recv(4096)
            body = rest[:cl]
        if path.startswith("/hang"):
            time.sleep(8)
            c.close()
            return
        if path.startswith("/chunk"):
            payload = b"HTTP/1.1 200 OK\r\nTransfer-Encoding: chunked\r\n\r\n5\r\nhello\r\n0\r\n\r\n"
            c.sendall(payload)
            c.close()
            return
        if path.startswith("/clte"):
            payload = b"HTTP/1.1 200 OK\r\nContent-Length: 4\r\nTransfer-Encoding: chunked\r\n\r\nabcd"
            c.sendall(payload)
            c.close()
            return
        if path.startswith("/dupcl"):
            payload = b"HTTP/1.1 200 OK\r\nContent-Length: 1\r\nContent-Length: 2\r\n\r\nab"
            c.sendall(payload)
            c.close()
            return
        if path.startswith("/oversize"):
            payload = b"HTTP/1.1 200 OK\r\nContent-Length: 1000001\r\n\r\n" + (b"x" * 64)
            c.sendall(payload)
            c.close()
            return
        if path.startswith("/redir"):
            payload = b"HTTP/1.1 307 Error\r\nLocation: /sop\r\nContent-Length: 0\r\nConnection: close\r\n\r\n"
            c.sendall(payload)
            c.close()
            return
        if path.startswith("/echo"):
            if method == "POST":
                msg = b"echo-post:" + body
            else:
                msg = b"echo-get"
            payload = (
                b"HTTP/1.1 200 OK\r\nContent-Type: text/plain\r\nX-Keep: yes\r\n"
                b"Connection: close\r\nContent-Length: "
                + str(len(msg)).encode("ascii")
                + b"\r\n\r\n"
                + msg
            )
            c.sendall(payload)
            c.close()
            return
        if path.startswith("/up"):
            msg = body if method == "POST" else b"up-ok"
            payload = (
                b"HTTP/1.1 200 OK\r\nContent-Type: text/plain\r\nContent-Length: "
                + str(len(msg)).encode("ascii")
                + b"\r\n\r\n"
                + msg
            )
            c.sendall(payload)
            c.close()
            return
        c.sendall(b"HTTP/1.1 404 Error\r\nContent-Length: 0\r\n\r\n")
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

echo "=== FAIL_BEFORE (no primitive, as at $BEFORE_SHA) ==="
cp "$FAIL_GUEST" "$STAGE/proxy-fail.vire"
FAIL_OUT="$(dotnet exec "$VIRE_DLL" data/native-proxy/proxy-fail.vire || true)"
echo "$FAIL_OUT"
if echo "$FAIL_OUT" | grep -qx "echo-get"; then
  echo "FAIL_BEFORE expected mismatch, got echo-get"
  kill "$UP_PID" 2>/dev/null || true
  exit 1
fi
echo "FAIL_BEFORE at $BEFORE_SHA proxy contract mismatch as required"

compile_guest "$GUEST" "proxy-http"

run_pair() {
  local mode="$1"
  local want="$2"
  echo "--- mode $mode ---"
  HOST_OUT="$(dotnet exec "$VIRE_DLL" data/native-proxy/proxy-http.vire "$UP" "$mode")"
  NAT_OUT="$(./data/native-proxy/proxy-http.elf "$UP" "$mode")"
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

run_pair client-get echo-get
run_pair client-post "echo-post:hi-body"
run_pair client-chunk te
run_pair client-clte cl-te
run_pair client-dupcl dup-cl
run_pair client-oversize cl
run_pair client-timeout timeout
run_pair proxy-get echo-get
run_pair proxy-post "echo-post:from-proxy"
run_pair proxy-loc "/app/sop"
run_pair proxy-fail "bad gateway"
run_pair proxy-smuggle "bad gateway"

echo "HOST_NATIVE_MATCH"

echo "=== listen + proxy_reply host vs native ==="
run_listen() {
  local name="$1"
  shift
  local out="/tmp/vire-proxy-listen-${name}.out"
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
      kill "$UP_PID" 2>/dev/null || true
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
    kill "$UP_PID" 2>/dev/null || true
    exit 1
  fi
  echo "$pid $port"
}
read HOST_PID HOST_PORT < <(run_listen px-host dotnet exec "$VIRE_DLL" data/native-proxy/proxy-http.vire "$UP" listen)
read NAT_PID NAT_PORT < <(run_listen px-nat ./data/native-proxy/proxy-http.elf "$UP" listen)
python3 - "$HOST_PORT" "$NAT_PORT" <<'PY'
import socket, sys
def get(port, path, body=None):
    if body is None:
        req = f"GET {path} HTTP/1.1\r\nHost: x\r\nConnection: close\r\n\r\n".encode()
    else:
        payload = body.encode()
        req = f"POST {path} HTTP/1.1\r\nHost: x\r\nContent-Length: {len(payload)}\r\nConnection: close\r\n\r\n".encode() + payload
    s = socket.create_connection(("127.0.0.1", int(port)), 5)
    s.sendall(req); s.settimeout(5)
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
    raw = data.decode("utf-8", "replace")
    if not raw.startswith("HTTP/"):
        raise SystemExit("empty/bad http from %s %s %r" % (port, path, raw[:80]))
    return int(raw.split(" ")[1]), raw.split("\r\n\r\n", 1)[1]
for path, body, want in [("/proxy", None, "up-ok"), ("/proxy", "from-listen", "from-listen")]:
    hs, hb = get(sys.argv[1], path, body)
    ns, nb = get(sys.argv[2], path, body)
    if hs != 200 or ns != 200 or want not in hb or hb != nb:
        raise SystemExit("listen proxy %s %s/%r %s/%r" % (path, hs, hb, ns, nb))
print("listen+proxy_reply host-vs-native match")
PY
kill "$HOST_PID" 2>/dev/null || true
wait "$HOST_PID" 2>/dev/null || true
kill "$NAT_PID" 2>/dev/null || true
wait "$NAT_PID" 2>/dev/null || true

echo "PASS_AFTER at $AFTER_SHA"
kill "$UP_PID" 2>/dev/null || true
wait "$UP_PID" 2>/dev/null || true
echo "rebuild proxy diff ok"
