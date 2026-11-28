#!/usr/bin/env python3
"""Patch packed r4 DNS so PE resolve matches src/rt-dns.vire rbx/share-mode.

Inserting unpacked emitDnsRuntime into compile-native blows the 100000 list cap
on gen1. Same-length share7 and +1 push/pop rbx keep the packed shape.
"""
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SRC = ROOT / "src"


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


def names_r4():
    text = (SRC / "rt-net.vire").read_text()
    i = text.find("define netNamesR4")
    start = text.find("return [", i)
    end = text.find("]", start)
    inner = text[start + 8 : end]
    return [x.strip().strip('"') for x in inner.split(",") if x.strip()]


def load_recs(path):
    raw = path.read_text().strip()
    out = []
    i = 0
    while i + 11 < len(raw):
        out.append((parse_u32(raw, i), parse_u16(raw, i + 8)))
        i += 12
    return out


def save_recs(path, recs):
    path.write_text("".join(pack_rec(o, i).hex() for o, i in recs) + "\n")


def pin_off(pins, names, nm):
    idx = names.index(nm)
    for off, idn in pins:
        if idn == idx:
            return off
    raise SystemExit("missing pin " + nm)


def insert(blob, pins, fixes, off, data):
    blob = blob[:off] + data + blob[off:]
    pins = [(o + len(data) if o >= off else o, i) for o, i in pins]
    fixes = [(o + len(data) if o >= off else o, i) for o, i in fixes]
    return blob, pins, fixes


def main():
    names = names_r4()
    blob = bytearray(bytes.fromhex((SRC / "rt-net-r4-blob.txt").read_text().strip()))
    pins = load_recs(SRC / "rt-net-r4-pins.txt")
    fixes = load_recs(SRC / "rt-net-r4-fixes.txt")

    cf = pin_off(pins, names, "dns_ns_cf")
    share = bytes([0x41, 0xB8, 1, 0, 0, 0])
    want = bytes([0x41, 0xB8, 7, 0, 0, 0])
    at = blob.find(share, cf, cf + 40)
    if at < 0:
        if blob.find(want, cf, cf + 40) < 0:
            raise SystemExit("CreateFile share immediate not found")
        print("share7 already patched")
    else:
        blob[at : at + 6] = want
        print("share7 at", at)

    def pro_after(nm):
        return pin_off(pins, names, nm) + 11

    inserts = []

    def before_leave(nm, prefix):
        o = pin_off(pins, names, nm)
        i = blob.find(prefix + bytes([0xC9, 0xC3]), o, o + 160)
        if i < 0:
            if blob.find(prefix + bytes([0x5B, 0xC9, 0xC3]), o, o + 160) >= 0:
                return
            raise SystemExit("missing epilogue at " + nm)
        inserts.append(i + len(prefix))

    inserts.append(pro_after("dns_hostok"))
    before_leave("dns_hk_end", bytes([0xB8, 1, 0, 0, 0]))
    before_leave("dns_hk_no", bytes([0x31, 0xC0]))
    inserts.append(pro_after("dns_fmta"))
    before_leave("dns_fa_done", bytes([0x48, 0x89, 0xC2]))
    inserts.append(pro_after("dns_parse"))
    before_leave("dns_p_yes", bytes([0xB8, 1, 0, 0, 0]))
    before_leave("dns_p_no", bytes([0x31, 0xC0]))
    inserts.append(pro_after("dns_ns"))
    before_leave("dns_ns_have", bytes([0xB8, 0x7F, 0, 0, 1, 0x89, 0xCA]))
    before_leave("dns_ns_etc", bytes([0xB8, 0x7F, 0, 0, 1, 0xBA, 0x35, 0, 0, 0]))
    before_leave("dns_ns_win", bytes([0xB8, 0x7F, 0, 0, 1, 0xBA, 0x35, 0, 0, 0]))

    push_sites = {pro_after("dns_hostok"), pro_after("dns_fmta"), pro_after("dns_parse"), pro_after("dns_ns")}
    # Recompute after share7 (no length change). Apply inserts high to low.
    for off in sorted(set(inserts), reverse=True):
        b = bytes([0x53]) if off in push_sites else bytes([0x5B])
        if off in push_sites:
            if blob[off] == 0x53:
                print("push already", off)
                continue
        else:
            if blob[off] == 0x5B:
                print("pop already", off)
                continue
        blob, pins, fixes = insert(blob, pins, fixes, off, b)
        print("insert", b.hex(), "at", off)

    (SRC / "rt-net-r4-blob.txt").write_text(bytes(blob).hex() + "\n")
    save_recs(SRC / "rt-net-r4-pins.txt", pins)
    save_recs(SRC / "rt-net-r4-fixes.txt", fixes)
    print("blob", len(blob), "pins", len(pins), "fixes", len(fixes))


if __name__ == "__main__":
    main()
