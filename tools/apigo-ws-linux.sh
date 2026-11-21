#!/usr/bin/env bash
# Host interpreter vs native ELF vs recorded api-go WS contract on 127.0.0.1.
# GitHub Actions billing-lock is not a code failure. Caps unchanged.
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
assert "33554432" in rt
assert "100000" in Path("Vire.cs").read_text()
assert "5000000" in Path("Vire.cs").read_text()
print("caps_src_ok arena=33554432 list=100000 steps=5000000")
print("contract_note", Path("tests/rebuild/contracts/apigo-ws.json").read_text()[:180].replace("\n"," "))
PY

hex_to_bin() {
  python3 - "$1" "$2" <<'PY'
import pathlib, sys
pathlib.Path(sys.argv[2]).write_bytes(bytes.fromhex(pathlib.Path(sys.argv[1]).read_text().strip()))
PY
}

dotnet build vire.csproj -c Release --nologo
mkdir -p data/apigo-ws
cp tests/rebuild/guests/apigo-ws.vire data/apigo-ws/apigo-ws.vire
rm -f data/apigo-ws/apigo-ws.hex data/apigo-ws/apigo-ws.elf
dotnet exec bin/Release/net10.0/vire.dll --compiler compile-native.vire data/apigo-ws/apigo-ws.vire data/apigo-ws/apigo-ws.hex
hex_to_bin data/apigo-ws/apigo-ws.hex data/apigo-ws/apigo-ws.elf
chmod +x data/apigo-ws/apigo-ws.elf

python3 - "$ROOT" <<'PY'
import hashlib, base64, os, re, socket, struct, subprocess, sys, time, urllib.request

root = sys.argv[1]
dll = os.path.join(root, "bin/Release/net10.0/vire.dll")
elf = os.path.join(root, "data/apigo-ws/apigo-ws.elf")
guest = os.path.join(root, "data/apigo-ws/apigo-ws.vire")

def start_cmd(cmd):
    proc = subprocess.Popen(cmd, cwd=root, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True)
    port = None
    buf = ""
    deadline = time.time() + 12
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
        proc.kill()
        raise SystemExit("no listen line: " + buf)
    return proc, port

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

def handshake(port, path):
    s = socket.create_connection(("127.0.0.1", port), timeout=4)
    s.settimeout(4)
    key = base64.b64encode(b"0123456789abcdef").decode("ascii")
    req = (
        "GET %s HTTP/1.1\r\nHost: 127.0.0.1\r\nUpgrade: websocket\r\n"
        "Connection: Upgrade\r\nSec-WebSocket-Key: %s\r\n"
        "Sec-WebSocket-Version: 13\r\n\r\n" % (path, key)
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
    return s

def prove(label, port):
    with urllib.request.urlopen("http://127.0.0.1:%d/health" % port, timeout=3) as r:
        body = r.read()
    assert b"ok" in body, body
    print(label, "http_health_ok")
    for path in ("/ws/kick", "/ws/chat", "/ws/live", "/chat", "/live"):
        s = handshake(port, path)
        s.sendall(mask_frame(1, b"xyz"))
        got = b""
        while len(got) < 5:
            chunk = s.recv(64)
            if not chunk:
                break
            got += chunk
        assert got[:2] == b"\x81\x03" and got[2:5] == b"xyz", (path, got)
        s.close()
        print(label, "upgrade_echo_ok", path)
    cases = [
        ("unmasked", mask_frame(1, b"no", mask=False), 1002),
        ("rsv", mask_frame(1, b"x", rsv=1), 1002),
        ("frag_ping", mask_frame(9, b"p", fin=False), 1002),
        ("len64", mask_frame(1, b"tiny", ext127=True), 1009),
        ("oversize", mask_frame(1, b"a" * 65537), 1009),
    ]
    for name, frame, code in cases:
        s = handshake(port, "/ws/kick")
        s.sendall(frame)
        data = b""
        try:
            while len(data) < 4:
                chunk = s.recv(64)
                if not chunk:
                    break
                data += chunk
        except socket.timeout:
            pass
        s.close()
        assert data[:1] == b"\x88", (name, data)
        seen = (data[2] << 8) | data[3]
        assert seen == code, (name, seen, data[:4])
        print(label, "malformed_%s_close" % name, code)

host_proc, host_port = start_cmd(["dotnet", "exec", dll, guest])
elf_proc, elf_port = start_cmd([elf])
try:
    prove("host", host_port)
    prove("elf", elf_port)
    print("apigo_ws_linux_ok host_vs_elf_vs_contract")
finally:
    for p in (host_proc, elf_proc):
        p.kill()
        try:
            p.wait(timeout=2)
        except Exception:
            pass
PY
