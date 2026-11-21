#!/usr/bin/env bash
# Loopback UDP DNS fixture + native ELF resolve. No external network.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
export PATH="${HOME}/.dotnet:${PATH:-}"
export DOTNET_ROOT="${DOTNET_ROOT:-$HOME/.dotnet}"
export VIRE_HEADLESS=1
unset VIRE_BUDGET || true
AFTER_SHA="$(git rev-parse HEAD)"
echo "pass_after_sha $AFTER_SHA"
FAIL_BEFORE="e236272cbf2355dbe79b13bc71d18f481da2e5b5"
echo "fail_before_sha $FAIL_BEFORE"
dotnet build vire.csproj -c Release --nologo
mkdir -p data

rm -f /tmp/vire-elf-dns.port
python3 - <<'PY' &
import socket, os
s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
s.bind(("127.0.0.1", 0))
port = s.getsockname()[1]
open("/tmp/vire-elf-dns.port", "w").write(str(port))
print("dns_listen 127.0.0.1:%s" % port, flush=True)
while True:
    data, addr = s.recvfrom(512)
    if len(data) < 12:
        continue
    qid = data[:2]
    # QR=1, RA=1, 1 answer, pointer to QNAME at 12
    ans = bytearray(data)
    ans[2] = 0x81
    ans[3] = 0x80
    ans[6] = 0
    ans[7] = 1
    i = 12
    while i < len(data) and data[i] != 0:
        i += 1 + data[i]
    i += 1
    qname = data[12:i]
    ans += qname + bytes([0, 1, 0, 1, 0, 0, 0, 0, 0, 4, 127, 0, 0, 1])
    s.sendto(ans, addr)
PY
DNSPID=$!
trap 'kill "$DNSPID" 2>/dev/null || true' EXIT
for i in $(seq 1 50); do
  if [[ -f /tmp/vire-elf-dns.port ]]; then break; fi
  sleep 0.05
done
PORT="$(cat /tmp/vire-elf-dns.port)"
echo "dns_port $PORT"
printf '127.0.0.1 %s\n' "$PORT" > data/vire-dns

rm -f data/dns-resolve.hex data/dns-resolve.elf
cp tests/native/dns-resolve.vire data/dns-resolve.vire
dotnet exec bin/Release/net10.0/vire.dll --compiler compile-native.vire data/dns-resolve.vire data/dns-resolve.hex
python3 - <<'PY'
from pathlib import Path
Path("data/dns-resolve.elf").write_bytes(bytes.fromhex(Path("data/dns-resolve.hex").read_text().strip()))
PY
chmod +x data/dns-resolve.elf
export VIRE_DNS="127.0.0.1:${PORT}"
HOST_OUT="$(dotnet exec bin/Release/net10.0/vire.dll data/dns-resolve.vire || true)"
ELF_OUT="$(./data/dns-resolve.elf || true)"
echo "host_out $HOST_OUT"
echo "elf_out $ELF_OUT"
echo "$HOST_OUT" | grep -q "that name is not valid"
echo "$ELF_OUT" | grep -q "that name is not valid"
echo "$HOST_OUT" | grep -q "127.0.0.1"
echo "$ELF_OUT" | grep -q "127.0.0.1"
if [[ "$HOST_OUT" != "$ELF_OUT" ]]; then
  echo "HOST_ELF_MISMATCH"
  kill "$DNSPID" 2>/dev/null || true
  exit 1
fi
echo "HOST_ELF_MATCH"
echo "native_elf_dns ok"
kill "$DNSPID" 2>/dev/null || true
