#!/usr/bin/env python3
"""Patch packed listen blobs without growing them (list cap 100000).

#150 r4 (18855) cl_blockgate e9 landed at +0xa84 (mid cl_nobody) so 4-param
fn_route bound path to a tagged integer and SIGSEGV'd. #159 isolated r4
(18843) already e9's +0xa78 (pushroute) and serves GET /api/health and
authorized POST /block. This lane keeps that 18843 blob (same size as #159;
recv0 retargets an in-blob leave;ret, no append).

Recv==0 was a reloc to cl_408. Peer close with zero bytes must leave;ret
from rt_net_client so listen_loop can accept the next client.
"""
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SRC = ROOT / "src"
DATA = ROOT / "data" / "src"


def parse_u16(s, i):
    return int(s[i : i + 2], 16) + int(s[i + 2 : i + 4], 16) * 256


def parse_u32(s, i):
    return parse_u16(s, i) + parse_u16(s, i + 4) * 65536


def pack_u16(n):
    return bytes([n & 255, (n >> 8) & 255])


def pack_u32(n):
    return pack_u16(n & 65535) + pack_u16((n >> 16) & 65535)


def pack_rec(off, idn):
    return pack_u32(off) + pack_u16(idn)


def load_fixes(raw):
    out = []
    i = 0
    while i + 11 < len(raw):
        out.append((parse_u32(raw, i), parse_u16(raw, i + 8)))
        i += 12
    return out


def patch_recv0(blob, fixes, leave_at):
    assert blob[leave_at : leave_at + 2] == b"\xc9\xc3", blob[leave_at : leave_at + 2].hex()
    if blob[0x5DE] == 0x0F and blob[0x5DF] == 0x84:
        tgt = 0x5E4 + int.from_bytes(blob[0x5E0:0x5E4], "little", signed=True)
        if tgt == leave_at:
            return blob, [(off, idn) for off, idn in fixes if off != 0x5E0], tgt
    assert blob[0x5DB:0x5DE] == bytes.fromhex("4885c0")
    blob[0x5DE:0x5E4] = bytes([0x0F, 0x84]) + pack_u32((leave_at - 0x5E4) & 0xFFFFFFFF)
    fixes = [(off, idn) for off, idn in fixes if off != 0x5E0]
    return blob, fixes, leave_at


def patch_r4_push(blob):
    found_a84 = None
    found_a78 = None
    i = 0
    while i + 5 <= len(blob):
        if blob[i] == 0xE9:
            rel = int.from_bytes(blob[i + 1 : i + 5], "little", signed=True)
            tgt = i + 5 + rel
            if tgt == 0xA84:
                found_a84 = i
            if tgt == 0xA78 and i > 0x4000:
                found_a78 = i
        i += 1
    if found_a78 is not None:
        return found_a78, 0xA78, 0xA78
    assert found_a84 is not None, "cl_blockgate jmp 0xa84/0xa78 not found"
    blob[found_a84 + 1 : found_a84 + 5] = pack_u32((0xA78 - (found_a84 + 5)) & 0xFFFFFFFF)
    return found_a84, 0xA84, 0xA78


def write_pair(name, text):
    (SRC / name).write_text(text)
    (DATA / name).write_text(text)


def main():
    ranges = []
    r4 = bytearray(bytes.fromhex((SRC / "rt-net-r4-blob.txt").read_text().strip()))
    r4_fixes = load_fixes((SRC / "rt-net-r4-fixes.txt").read_text().strip())
    jmp_at, old_tgt, new_tgt = patch_r4_push(r4)
    ranges.append("rt-net-r4-blob.txt +0x%x jmp 0x%x -> 0x%x (len %d)" % (jmp_at, old_tgt, new_tgt, len(r4)))
    leave4 = 0x36DF if len(r4) <= 18850 else 0x36EB
    r4, r4_fixes, stub4 = patch_recv0(r4, r4_fixes, leave4)
    ranges.append("rt-net-r4-blob.txt +0x5de je recv0 -> leave;ret at +0x%x" % stub4)
    write_pair("rt-net-r4-blob.txt", r4.hex() + "\n")
    write_pair("rt-net-r4-fixes.txt", b"".join(pack_rec(o, i) for o, i in r4_fixes).hex() + "\n")
    write_pair("rt-net-r4-pins.txt", (SRC / "rt-net-r4-pins.txt").read_text())

    r3 = bytearray(bytes.fromhex((SRC / "rt-net-blob.txt").read_text().strip()))
    r3_fixes = load_fixes((SRC / "rt-net-fixes.txt").read_text().strip())
    r3, r3_fixes, stub3 = patch_recv0(r3, r3_fixes, 0x510)
    ranges.append("rt-net-blob.txt +0x5de je recv0 -> leave;ret at +0x%x" % stub3)
    write_pair("rt-net-blob.txt", r3.hex() + "\n")
    write_pair("rt-net-fixes.txt", b"".join(pack_rec(o, i) for o, i in r3_fixes).hex() + "\n")

    assert r4.find(bytes.fromhex("00100000")) >= 0
    for line in ranges:
        print(line)
    print("r4_len", len(r4), "r3_len", len(r3))
    print("ok")


if __name__ == "__main__":
    main()
