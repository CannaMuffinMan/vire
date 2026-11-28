#!/usr/bin/env python3
"""Patch packed r4 DNS so PE resolve matches src/rt-dns.vire rbx/share-mode.

Inserting unpacked emitDnsRuntime into compile-native blows the 100000 list cap
on gen1. Same-length share7 and +1 push/pop rbx keep the packed shape.

Naive insert of the 12 rbx bytes shifts later code. Compile-time pins/fixes
slots move with the table, but baked e8/e9/jcc/rel8 that cross an insert keep
the old displacement (cl_blockgate e9 then lands at 0xa84 instead of 0xa78;
recv0 je misses leave;ret). This script rewrites every crossing baked reloc
and asserts the targets.
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


def nins(off, sites):
    return sum(1 for s in sites if s <= off)


def looks_like_disp8(blob, i):
    """e8/e9/0f often sit in a prior insn's ModRM+disp8 (e.g. 89 55 e8)."""
    if i < 2:
        return False
    modrm = blob[i - 1]
    op = blob[i - 2]
    if (modrm >> 6) != 1:
        return False
    return op in (0x01, 0x03, 0x29, 0x2B, 0x31, 0x33, 0x39, 0x3B, 0x81, 0x83, 0x88, 0x89, 0x8A, 0x8B, 0x8D)


def collect_baked(blob, fix_off):
    out = []
    i = 0
    n = len(blob)
    while i + 2 <= n:
        if looks_like_disp8(blob, i):
            i += 1
            continue
        if blob[i] in (0xE8, 0xE9) and i + 5 <= n and (i + 1) not in fix_off:
            rel = int.from_bytes(blob[i + 1 : i + 5], "little", signed=True)
            tgt = i + 5 + rel
            if 0 <= tgt <= n:
                out.append((i, i + 1, 4, 5, tgt))
        elif blob[i] == 0x0F and i + 6 <= n and 0x80 <= blob[i + 1] <= 0x8F and (i + 2) not in fix_off:
            if looks_like_disp8(blob, i):
                i += 1
                continue
            rel = int.from_bytes(blob[i + 2 : i + 6], "little", signed=True)
            tgt = i + 6 + rel
            if 0 <= tgt <= n:
                out.append((i, i + 2, 4, 6, tgt))
        i += 1
    return out


def rewrite_crossing(blob, relocs, sites):
    changed = 0
    for site, disp_at, width, sz, tgt in relocs:
        between = [s for s in sites if min(site + sz, tgt) < s <= max(site + sz, tgt)]
        if not between:
            continue
        new_site = site + nins(site, sites)
        new_tgt = tgt + nins(tgt, sites)
        new_rel = new_tgt - (new_site + sz)
        if width == 1:
            if new_rel < -128 or new_rel > 127:
                raise SystemExit("rel8 overflow at 0x%x -> 0x%x" % (site, tgt))
            blob[new_site + 1] = new_rel & 255
        else:
            blob[new_site + (disp_at - site) : new_site + (disp_at - site) + 4] = pack_u32(new_rel & 0xFFFFFFFF)
        print(
            "reloc 0x%x -> 0x%x (%+d) now 0x%x -> 0x%x (%+d)"
            % (site, tgt, tgt - (site + sz), new_site, new_tgt, new_rel)
        )
        changed += 1
    return changed


def write_pair(name, text):
    (SRC / name).write_text(text)
    (DATA / name).write_text(text)


def assert_listen(blob):
    if blob[0xA78] != 0xE9:
        raise SystemExit("rt_net_pushroute at 0xa78 is not e9")
    saw = False
    hit = -1
    i = 0
    while i + 5 <= len(blob):
        if blob[i] == 0xE9:
            rel = int.from_bytes(blob[i + 1 : i + 5], "little", signed=True)
            if i + 5 + rel == 0xA78 and i > 0x4000:
                saw = True
                hit = i
                break
        i += 1
    if not saw:
        raise SystemExit("no baked e9 after 0x4000 targets 0xa78")
    if blob[0x5DE] != 0x0F or blob[0x5DF] != 0x84:
        raise SystemExit("recv0 je missing at 0x5de")
    tgt = 0x5E4 + int.from_bytes(blob[0x5E0:0x5E4], "little", signed=True)
    if blob[tgt : tgt + 2] != b"\xc9\xc3":
        raise SystemExit("recv0 je target 0x%x is %s not leave;ret" % (tgt, blob[tgt : tgt + 2].hex()))
    print("assert recv0 -> 0x%x leave;ret" % tgt)
    print("assert e9 -> 0xa78 at 0x%x" % hit)


def main():
    names = names_r4()
    blob = bytearray(bytes.fromhex((SRC / "rt-net-r4-blob.txt").read_text().strip()))
    pins = load_recs(SRC / "rt-net-r4-pins.txt")
    fixes = load_recs(SRC / "rt-net-r4-fixes.txt")
    fix_off = set(o for o, _ in fixes)

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
        print("share7 at", hex(at))

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
    todo = []
    for off in sorted(set(inserts)):
        already = blob[off] == (0x53 if off in push_sites else 0x5B)
        if already:
            print("already", hex(off))
            continue
        todo.append(off)

    if not todo:
        print("rbx inserts already present")
    else:
        relocs = collect_baked(blob, fix_off)
        for off in sorted(todo, reverse=True):
            b = bytes([0x53]) if off in push_sites else bytes([0x5B])
            blob, pins, fixes = insert(blob, pins, fixes, off, b)
            print("insert", b.hex(), "at", hex(off))
        n = rewrite_crossing(blob, relocs, todo)
        print("rewrote", n, "crossing relocs")

    hostok = bytes.fromhex("554889e54881ec800000005348894df8")
    if blob.find(hostok) < 0:
        raise SystemExit("dns_hostok missing push rbx")
    if blob.find(want) < 0:
        raise SystemExit("FILE_SHARE 7 missing")
    assert_listen(blob)
    if len(blob) != 18855:
        raise SystemExit("expected r4 len 18855, got %d" % len(blob))

    write_pair("rt-net-r4-blob.txt", bytes(blob).hex() + "\n")
    write_pair("rt-net-r4-pins.txt", "".join(pack_rec(o, i).hex() for o, i in pins) + "\n")
    write_pair("rt-net-r4-fixes.txt", "".join(pack_rec(o, i).hex() for o, i in fixes) + "\n")
    print("blob", len(blob), "pins", len(pins), "fixes", len(fixes))
    print("ok")


if __name__ == "__main__":
    main()
