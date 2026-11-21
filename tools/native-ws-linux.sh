#!/usr/bin/env bash
# Compile a listen guest to ELF, prove HTTP still works, RFC 6455 echo vs
# Python websockets, and fail-closed malformed frames. Caps unchanged.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
export PATH="${HOME}/.dotnet:${PATH:-}"
export DOTNET_ROOT="${DOTNET_ROOT:-$HOME/.dotnet}"
export VIRE_HEADLESS=1
unset VIRE_BUDGET || true

python3 - <<'PY'
from pathlib import Path
rt = Path("src/rt.vire").read_text()
more = Path("src/rt-more.vire").read_text()
assert "33554432" in rt and "33554432" in more
assert Path("src/rt.vire").read_text() == Path("data/src/rt.vire").read_text()
assert Path("compile-native.vire").read_text() == Path("data/compile-native.vire").read_text()
print("caps_src_ok arena=33554432")
PY

hex_to_bin() {
  python3 - "$1" "$2" <<'PY'
import pathlib, sys
pathlib.Path(sys.argv[2]).write_bytes(bytes.fromhex(pathlib.Path(sys.argv[1]).read_text().strip()))
PY
}

dotnet build vire.csproj -c Release --nologo
mkdir -p data/native-ws
cp tests/native/ws-echo.vire data/native-ws/ws-echo.vire
rm -f data/native-ws/ws-echo.hex data/native-ws/ws-echo.elf
dotnet exec bin/Release/net10.0/vire.dll --compiler compile-native.vire data/native-ws/ws-echo.vire data/native-ws/ws-echo.hex
hex_to_bin data/native-ws/ws-echo.hex data/native-ws/ws-echo.elf
chmod +x data/native-ws/ws-echo.elf
python3 - <<'PY'
from pathlib import Path
b = Path("data/native-ws/ws-echo.elf").read_bytes()
assert b[:4] == b"\x7fELF"
assert b"Switching Protocols" in b
assert b"258EAFA5-E914-47DA-95CA-C5AB0DC85B11" in b
print("guest_elf_ok", len(b))
PY

python3 -m pip install -q websockets
python3 - "$ROOT" <<'PY'
import os, re, socket, struct, subprocess, sys, time, hashlib, base64, urllib.request

root = sys.argv[1]
elf = os.path.join(root, "data/native-ws/ws-echo.elf")
proc = subprocess.Popen([elf], cwd=root, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True)
port = None
try:
    deadline = time.time() + 8
    buf = ""
    while time.time() < deadline:
        line = proc.stdout.readline()
        if not line:
            break
        buf += line
        m = re.search(r"listening on 127\.0\.0\.1:(\d+)", line)
        if m:
            port = int(m.group(1))
            break
    if port is None:
        raise SystemExit("no listen line: " + buf)

    # HTTP path on the same listener
    with urllib.request.urlopen("http://127.0.0.1:%d/health" % port, timeout=3) as r:
        body = r.read()
    assert b"ok" in body, body
    print("http_health_ok", body)

    import asyncio
    try:
        import websockets
    except ImportError:
        raise SystemExit("python websockets missing")

    async def echo_round():
        uri = "ws://127.0.0.1:%d/" % port
        async with websockets.connect(uri, open_timeout=5, close_timeout=5) as ws:
            await ws.send("hello-ws")
            got = await asyncio.wait_for(ws.recv(), 5)
            assert got == "hello-ws", got
            await ws.send(b"\x00\x01\x02\xff")
            gotb = await asyncio.wait_for(ws.recv(), 5)
            assert gotb == b"\x00\x01\x02\xff", gotb
            pong = await ws.ping()
            await asyncio.wait_for(pong, 5)
        print("python_websockets_echo_ok")

    asyncio.run(echo_round())

    def connect():
        s = socket.create_connection(("127.0.0.1", port), timeout=3)
        s.settimeout(3)
        return s

    def handshake(s):
        key = base64.b64encode(b"0123456789abcdef").decode("ascii")
        req = (
            "GET / HTTP/1.1\r\nHost: 127.0.0.1\r\nUpgrade: websocket\r\n"
            "Connection: Upgrade\r\nSec-WebSocket-Key: %s\r\n"
            "Sec-WebSocket-Version: 13\r\n\r\n" % key
        )
        s.sendall(req.encode("ascii"))
        data = b""
        while b"\r\n\r\n" not in data:
            chunk = s.recv(4096)
            if not chunk:
                break
            data += chunk
        assert b"101" in data, data
        accept = base64.b64encode(hashlib.sha1((key + "258EAFA5-E914-47DA-95CA-C5AB0DC85B11").encode("ascii")).digest())
        assert accept in data, data
        return data

    def mask_frame(opcode, payload, fin=True, mask=True, rsv=0, ext127=False):
        b0 = (0x80 if fin else 0) | (rsv << 4) | opcode
        n = len(payload)
        hdr = bytes([b0])
        maskbit = 0x80 if mask else 0
        if ext127:
            hdr += bytes([maskbit | 127]) + struct.pack("!Q", n)
        elif n < 126:
            hdr += bytes([maskbit | n])
        elif n < 65536:
            hdr += bytes([maskbit | 126]) + struct.pack("!H", n)
        else:
            hdr += bytes([maskbit | 127]) + struct.pack("!Q", n)
        if mask:
            m = b"\x37\xfa\x21\x3d"
            hdr += m
            payload = bytes(payload[i] ^ m[i % 4] for i in range(len(payload)))
        return hdr + payload

    s = connect()
    handshake(s)
    s.sendall(mask_frame(1, b"xyz"))
    got = b""
    while len(got) < 5:
        chunk = s.recv(64)
        if not chunk:
            break
        got += chunk
    assert got[:2] == b"\x81\x03" and got[2:5] == b"xyz", got
    print("masked_text_echo_ok")
    s.close()

    cases = []
    # unmasked client frame
    s = connect(); handshake(s); s.sendall(mask_frame(1, b"no", mask=False)); cases.append(("unmasked", s))
    # RSV bits
    s = connect(); handshake(s); s.sendall(mask_frame(1, b"x", rsv=1)); cases.append(("rsv", s))
    # control fragmented
    s = connect(); handshake(s); s.sendall(mask_frame(9, b"p", fin=False)); cases.append(("frag_ping", s))
    # 64-bit length (fail closed: either non-minimal or over 64k)
    s = connect(); handshake(s)
    s.sendall(mask_frame(1, b"tiny", ext127=True)); cases.append(("len64", s))
    # payload cap
    big = b"a" * 65537
    s = connect(); handshake(s); s.sendall(mask_frame(1, big)); cases.append(("oversize", s))

    for name, sock in cases:
        data = b""
        try:
            while True:
                chunk = sock.recv(64)
                if not chunk:
                    break
                data += chunk
                if len(data) >= 4:
                    break
        except socket.timeout:
            pass
        sock.close()
        assert data[:1] == b"\x88", (name, data)
        print("malformed_%s_close" % name, data[:4])

    print("native_ws_linux_ok")
finally:
    proc.kill()
    try:
        proc.wait(timeout=2)
    except Exception:
        pass
PY
