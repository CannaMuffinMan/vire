#!/usr/bin/env python3
"""Patch packed listen blobs: 4-param route push + quiet close on recv 0.

r4 cl_blockgate ended with a hardcoded jmp to blob+0xa84, which is the middle of
cl_nobody after the tokengate/pushroute trampolines. 4-param guests then called
fn_route with three VM args, so `path` bound to 0x4f and SIGSEGV'd in texteq.

Recv==0 was a reloc to cl_408. Peer close with no bytes must return from
rt_net_client so listen_loop can close the fd and accept the next client.
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


def patch_recv0(blob, fixes):
    if blob[0x5DE] == 0x0F and blob[0x5DF] == 0x84:
        tgt = 0x5E4 + int.from_bytes(blob[0x5E0:0x5E4], "little", signed=True)
        if 0 <= tgt < len(blob) - 1 and blob[tgt : tgt + 2] == b"\xc9\xc3":
            return blob, [(off, idn) for off, idn in fixes if off != 0x5E0], tgt
    assert blob[0x5DB:0x5E4] == bytes.fromhex("4885c00f8400000000"), blob[0x5DB:0x5E4].hex()
    stub = len(blob)
    blob.extend(b"\xc9\xc3")
    rel = (stub - 0x5E4) & 0xFFFFFFFF
    blob[0x5DE:0x5E4] = bytes([0x0F, 0x84]) + pack_u32(rel)
    fixes = [(off, idn) for off, idn in fixes if off != 0x5E0]
    return blob, fixes, stub


def patch_r4_push(blob):
    # cl_blockgate's e9 originally landed at 0xa84 (mid cl_nobody). Retarget
    # 0xa78 (jmp rt_net_pushroute). Ignore later stub e9s.
    found_a84 = None
    found_a78 = None
    i = 0
    while i + 5 <= len(blob):
        if blob[i] == 0xE9:
            rel = int.from_bytes(blob[i + 1 : i + 5], "little", signed=True)
            tgt = i + 5 + rel
            if tgt == 0xA84:
                found_a84 = i
            if tgt == 0xA78:
                found_a78 = i
        i += 1
    if found_a78 is not None:
        return found_a78, 0xA78, 0xA78
    assert found_a84 is not None, "cl_blockgate jmp 0xa84/0xa78 not found"
    rel = (0xA78 - (found_a84 + 5)) & 0xFFFFFFFF
    blob[found_a84 + 1 : found_a84 + 5] = pack_u32(rel)
    return found_a84, 0xA84, 0xA78


def patch_r4_save_frame(blob, fixes):
    # pr_back at +0xac0 is `call fn_route; call rt_restore_frame` with no
    # matching save_frame. Guest route's rt_begin/rt_return already pops the
    # trap qword, so the extra restore SIGSEGVs at rt_restore_frame
    # (`mov r14, [r15]`). Compiler calls are save, route, restore.
    if blob[0xAC0] == 0xE9:
        # prior run used unpacked save_frame id 168; r4 table is 390
        fixes = [(off, 390 if idn == 168 else idn) for off, idn in fixes]
        return blob, fixes, "already"
    assert blob[0xAC0] == 0xE8 and blob[0xAC5] == 0xE8, blob[0xAC0:0xACA].hex()
    id_route = id_rest = None
    out = []
    for off, idn in fixes:
        if off == 0xAC1:
            id_route = idn
        elif off == 0xAC6:
            id_rest = idn
        else:
            out.append((off, idn))
    assert id_route is not None and id_rest is not None
    stub = len(blob)
    blob.extend(bytes.fromhex("e800000000e800000000e800000000e900000000"))
    back = 0xACA
    blob[stub + 16 : stub + 20] = pack_u32((back - (stub + 20)) & 0xFFFFFFFF)
    blob[0xAC0:0xACA] = bytes([0xE9]) + pack_u32((stub - 0xAC5) & 0xFFFFFFFF) + bytes([0x90, 0x90, 0x90, 0x90, 0x90])
    out.append((stub + 1, 390))  # netNamesR4 rt_save_frame
    out.append((stub + 6, id_route))
    out.append((stub + 11, id_rest))
    return blob, out, stub


def patch_r4_afterroute_string(blob):
    # ar_fail (guestextra=0) is the JSON-string return path. It used to pop three
    # VM slots (often 0 after 4-param restore) and send 500. Use the saved return
    # text in [rbp-0x50] with status 200.
    if blob[0x3762:0x3766] == bytes.fromhex("488b4db0"):
        return False
    stub = bytearray(bytes.fromhex(
        "488b4db0"          # mov rcx, [rbp-0x50]
        "4885c9"            # test rcx, rcx
        "0f845c000000"      # jz 0x37cb (client leave;ret)
        "4c8d4108"          # lea r8, [rcx+8]
        "488b09"            # mov rcx, [rcx]
        "bac8000000"        # mov edx, 200
        "e922000000"        # jmp ar_send 0x37a2
    ))
    assert len(stub) <= (0x37A2 - 0x3762)
    blob[0x3762:0x3762 + len(stub)] = stub
    for i in range(0x3762 + len(stub), 0x37A2):
        blob[i] = 0x90
    return True


def write_pair(name, text):
    (SRC / name).write_text(text)
    (DATA / name).write_text(text)


def main():
    ranges = []

    r4 = bytearray(bytes.fromhex((SRC / "rt-net-r4-blob.txt").read_text().strip()))
    r4_fixes = load_fixes((SRC / "rt-net-r4-fixes.txt").read_text().strip())
    jmp_at, old_tgt, new_tgt = patch_r4_push(r4)
    ranges.append("rt-net-r4-blob.txt +0x%x jmp 0x%x -> 0x%x" % (jmp_at, old_tgt, new_tgt))
    if patch_r4_afterroute_string(r4):
        ranges.append("rt-net-r4-blob.txt +0x3762 ar_fail JSON string -> 200 sendhttp")
    # guestextra is a false positive on a JSON string (rax != 0) and the
    # success pops then SIGSEGV. JSON-string replies take ar_fail.
    if r4[0x371D:0x3722] != bytes.fromhex("e940000000"):
        r4[0x371D:0x3727] = bytes.fromhex("e9400000009090909090")
        ranges.append("rt-net-r4-blob.txt +0x371d jmp ar_fail (JSON string)")
    r4, r4_fixes, stub4 = patch_recv0(r4, r4_fixes)
    ranges.append("rt-net-r4-blob.txt +0x5de je recv0 -> leave;ret at +0x%x" % stub4)
    r4, r4_fixes, sf = patch_r4_save_frame(r4, r4_fixes)
    ranges.append("rt-net-r4-blob.txt +0xac0 jmp save+route+restore stub +0x%x" % (sf if isinstance(sf, int) else 0))
    write_pair("rt-net-r4-blob.txt", r4.hex() + "\n")
    write_pair("rt-net-r4-fixes.txt", b"".join(pack_rec(o, i) for o, i in r4_fixes).hex() + "\n")

    r3 = bytearray(bytes.fromhex((SRC / "rt-net-blob.txt").read_text().strip()))
    r3_fixes = load_fixes((SRC / "rt-net-fixes.txt").read_text().strip())
    r3, r3_fixes, stub3 = patch_recv0(r3, r3_fixes)
    ranges.append("rt-net-blob.txt +0x5de je recv0 -> leave;ret at +0x%x" % stub3)
    write_pair("rt-net-blob.txt", r3.hex() + "\n")
    write_pair("rt-net-fixes.txt", b"".join(pack_rec(o, i) for o, i in r3_fixes).hex() + "\n")

    for line in ranges:
        print(line)
    print("ok")


if __name__ == "__main__":
    main()
