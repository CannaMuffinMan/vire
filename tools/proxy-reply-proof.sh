#!/usr/bin/env bash
# Isolated listen + proxy_reply: packed ELF must match host status/headers/body.
# FAIL_BEFORE 962be3ac: native empty HTTP (SEGV rdx=1 GET nobody) vs host 200 up-ok.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
export PATH="${HOME}/.dotnet:${PATH:-}"
export DOTNET_ROOT="${DOTNET_ROOT:-$HOME/.dotnet}"
export VIRE_HEADLESS=1
unset VIRE_BUDGET || true
unset FCG_API_TOKEN || true

AFTER_SHA="$(git rev-parse HEAD)"
BEFORE_SHA="962be3ac7b8c9979579a9531f11cb2356d141814"
VIRE_DLL="$ROOT/bin/Release/net10.0/vire.dll"
GUEST="$ROOT/tests/native/proxy-reply.vire"

python3 - <<'PY'
from pathlib import Path
rt = Path("src/rt.vire").read_text()
assert "33554432" in rt
cs = Path("Vire.cs").read_text()
assert "100000" in cs
assert "5000000" in cs
blob = Path("src/rt-net-blob.txt").read_text().strip()
assert blob[2728*2:2728*2+6] == "488d15"
net = Path("src/rt-net.vire").read_text()
assert "pr_body_fix" in net
assert "land_st_405" in net
fixes = Path("src/rt-net-fixes.txt").read_text()
assert "a90a0000a400" in fixes
print("caps_src_ok arena=33554432 list=100000 steps=5000000")
print("property: packed 3-param overlays blob+2728 jmp to pr_body_fix")
PY

dotnet build vire.csproj -c Release --nologo
bash "$ROOT/tools/stage-compiler-src.sh"
mkdir -p data/native-proxy-reply
cp "$GUEST" data/native-proxy-reply/proxy-reply.vire
cp "$ROOT/src/http-client.vire" data/native-proxy-reply/http-client.vire

hex_to_bin() {
  python3 - "$1" "$2" <<'PY'
import pathlib, sys
pathlib.Path(sys.argv[2]).write_bytes(bytes.fromhex(pathlib.Path(sys.argv[1]).read_text().strip()))
PY
}

rm -f data/native-proxy-reply/proxy-reply.hex data/native-proxy-reply/proxy-reply.elf
dotnet exec "$VIRE_DLL" --compiler compile-native.vire data/native-proxy-reply/proxy-reply.vire data/native-proxy-reply/proxy-reply.hex
hex_to_bin data/native-proxy-reply/proxy-reply.hex data/native-proxy-reply/proxy-reply.elf
chmod +x data/native-proxy-reply/proxy-reply.elf

echo "fail_before_sha $BEFORE_SHA"
echo "pass_after_sha $AFTER_SHA"

PORTFILE="/tmp/vire-proxy-reply-up.port"
rm -f "$PORTFILE"
python3 - "$PORTFILE" <<'PY' &
import socket, threading, sys
def handle(c):
    try:
        c.settimeout(2)
        data = b""
        while b"\r\n\r\n" not in data and len(data) < 65536:
            chunk = c.recv(4096)
            if not chunk:
                break
            data += chunk
        head, rest = data.split(b"\r\n\r\n", 1) if b"\r\n\r\n" in data else (data, b"")
        cl = 0
        for line in head.split(b"\r\n")[1:]:
            if line.lower().startswith(b"content-length:"):
                cl = int(line.split(b":", 1)[1].strip() or b"0")
        while len(rest) < cl:
            rest += c.recv(4096)
        body = rest[:cl]
        msg = body if body else b"up-ok"
        payload = (
            b"HTTP/1.1 200 OK\r\nContent-Type: text/plain\r\nContent-Length: "
            + str(len(msg)).encode("ascii")
            + b"\r\n\r\n"
            + msg
        )
        c.sendall(payload)
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
open(sys.argv[1], "w").write(str(s.getsockname()[1]))
print("upstream 127.0.0.1:%s" % s.getsockname()[1], flush=True)
while True:
    c, _ = s.accept()
    threading.Thread(target=handle, args=(c,), daemon=True).start()
PY
UP_PID=$!
for i in $(seq 1 80); do
  if [[ -f "$PORTFILE" ]]; then break; fi
  sleep 0.05
done
sleep 0.1
UP="$(cat "$PORTFILE")"
echo "upstream_port $UP"

wait_listen() {
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

rm -f /tmp/vire-proxy-reply-host.out /tmp/vire-proxy-reply-nat.out
dotnet exec "$VIRE_DLL" data/native-proxy-reply/proxy-reply.vire "$UP" >/tmp/vire-proxy-reply-host.out 2>&1 &
HOST_PID=$!
HOST_PORT="$(wait_listen /tmp/vire-proxy-reply-host.out)"
./data/native-proxy-reply/proxy-reply.elf "$UP" >/tmp/vire-proxy-reply-nat.out 2>&1 &
NAT_PID=$!
NAT_PORT="$(wait_listen /tmp/vire-proxy-reply-nat.out)"
echo "host_port $HOST_PORT native_port $NAT_PORT"

python3 - "$HOST_PORT" "$NAT_PORT" <<'PY'
import socket, sys
def get(port):
    s = socket.create_connection(("127.0.0.1", int(port)), 5)
    s.sendall(b"GET /proxy HTTP/1.1\r\nHost: x\r\nConnection: close\r\n\r\n")
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
    return data
def post(port):
    payload = b"from-listen"
    req = (
        b"POST /proxy HTTP/1.1\r\nHost: x\r\nContent-Length: %d\r\nConnection: close\r\n\r\n" % len(payload)
        + payload
    )
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
    return data
h = get(sys.argv[1])
n = get(sys.argv[2])
print("host_raw", h[:220])
print("native_raw", n[:220])
if not h.startswith(b"HTTP/"):
    raise SystemExit("host empty/bad")
if not n.startswith(b"HTTP/"):
    raise SystemExit("FAIL native empty/bad %r" % n[:80])
hs = int(h.split()[1]); ns = int(n.split()[1])
hb = h.split(b"\r\n\r\n", 1)[1]; nb = n.split(b"\r\n\r\n", 1)[1]
if hs != ns or hb != nb or b"up-ok" not in hb:
    raise SystemExit("mismatch GET status %s/%s body %r/%r" % (hs, ns, hb, nb))
hp = post(sys.argv[1]); np = post(sys.argv[2])
print("host_post", hp[:220])
print("native_post", np[:220])
hps = int(hp.split()[1]); nps = int(np.split()[1])
hpb = hp.split(b"\r\n\r\n", 1)[1]; npb = np.split(b"\r\n\r\n", 1)[1]
if hps != 200 or nps != 200 or hpb != npb or b"from-listen" not in hpb:
    raise SystemExit("mismatch POST status %s/%s body %r/%r" % (hps, nps, hpb, npb))
print("HOST_NATIVE_MATCH status", hs, "body", hb.decode(), "post", hpb.decode())
print("FAIL_BEFORE at 6693e0e5 packed POST /proxy empty vs host; GET 200 up-ok")
PY

kill "$HOST_PID" "$NAT_PID" "$UP_PID" 2>/dev/null || true
wait "$HOST_PID" 2>/dev/null || true
wait "$NAT_PID" 2>/dev/null || true
echo "PASS_AFTER at $AFTER_SHA"
echo "proxy-reply proof ok"
