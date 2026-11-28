#!/usr/bin/env python3
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SRC = ROOT / "src"
BODY_SITE = 0xAA8
BODY_CONT = 0xAC0
CMP16 = bytes.fromhex("83f8100f82")
CMP_CAP = bytes.fromhex("4981f800100000")
JBE6 = bytes.fromhex("0f8606000000")
MOV_R8D_4096 = bytes.fromhex("41b800100000")


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


def names_of(marker):
    text = (SRC / "rt-net.vire").read_text()
    i = text.find(marker)
    start = text.find("return [", i)
    end = text.find("]", start)
    inner = text[start + 8 : end]
    return [x.strip().strip('"') for x in inner.split(",") if x.strip()]


def load_table(path):
    raw = path.read_text().strip()
    rows = []
    i = 0
    while i + 11 < len(raw):
        rows.append((parse_u32(raw, i), parse_u16(raw, i + 8)))
        i += 12
    return rows


def pin_off(rows, names, want):
    for off, idn in rows:
        if names[idn] == want:
            return off
    raise SystemExit("missing pin " + want)


def rel32(at, target):
    return pack_u32((target - (at + 4)) & 0xFFFFFFFF)


class Asm:
    def __init__(self, base):
        self.base = base
        self.buf = bytearray()
        self.labels = {}
        self.fixups = []

    def here(self):
        return self.base + len(self.buf)

    def pin(self, name):
        self.labels[name] = self.here()

    def emit(self, *xs):
        for x in xs:
            if isinstance(x, (bytes, bytearray)):
                self.buf.extend(x)
            elif isinstance(x, (list, tuple)):
                self.buf.extend(x)
            else:
                self.buf.append(x)

    def rel(self, name):
        self.fixups.append((self.here(), name))
        self.emit(0, 0, 0, 0)

    def jmp(self, name):
        self.emit(0xE9)
        self.rel(name)

    def jcc(self, cc, name):
        self.emit(0x0F, cc)
        self.rel(name)

    def lea_rdx(self, name):
        self.emit(0x48, 0x8D, 0x15)
        self.rel(name)


def emit_helpers(a):
    a.pin("cl_bodypark")
    a.emit(0x48, 0x8B, 0x4D, 0xF8)
    a.emit(0x48, 0x8B, 0x51, 0x40)
    a.emit(0x48, 0x89, 0xD0)
    a.emit(0x48, 0xC1, 0xE8, 0x0C)
    a.jcc(0x85, "bp_keep")
    a.lea_rdx("txt_empty")
    a.pin("bp_keep")
    a.emit(0x49, 0xC7, 0x45, 0x00, 0x02, 0x00, 0x00, 0x00)
    a.emit(0x49, 0x89, 0x55, 0x08)
    a.emit(0x49, 0x83, 0xC5, 0x10)
    a.emit(0xE9)
    a.rel("body_cont")

    a.pin("len_write")
    a.emit(0x83, 0xF8, 0x10)
    a.jcc(0x82, "cl_401")
    a.emit(0x3D, 0x00, 0x10, 0x00, 0x00)
    a.jcc(0x83, "cl_401")
    a.jmp("len_write_back")

    a.pin("len_other")
    a.emit(0x83, 0xF8, 0x10)
    a.jcc(0x82, "len_other_short")
    a.emit(0x3D, 0x00, 0x10, 0x00, 0x00)
    a.jcc(0x83, "cl_401")
    a.jmp("len_other_back")


def patch_three(blob_name, pins_name, fixes_name, names):
    name_id = {n: i for i, n in enumerate(names)}
    blob = bytearray(bytes.fromhex((SRC / blob_name).read_text().strip()))
    pins = load_table(SRC / pins_name)
    fixes = load_table(SRC / fixes_name)
    gate = pin_off(pins, names, "cl_blockgate")
    cl401 = pin_off(pins, names, "cl_401")
    changed = []

    if blob[BODY_SITE] != 0xE9:
        a = Asm(len(blob))
        emit_helpers(a)
        blob.extend(a.buf)
        local = dict(a.labels)
        local["cl_401"] = cl401
        local["body_cont"] = BODY_CONT
        write16 = None
        other16 = None
        i = gate
        while i + 5 <= len(blob):
            if bytes(blob[i : i + 5]) == CMP16:
                if write16 is None:
                    write16 = i
                elif other16 is None:
                    other16 = i
                    break
            i += 1
        if write16 is None or other16 is None:
            raise SystemExit("missing cmp eax,16 in " + blob_name)
        local["len_write_back"] = write16 + 9
        jb_rel = int.from_bytes(blob[other16 + 5 : other16 + 9], "little", signed=True)
        local["len_other_short"] = other16 + 9 + jb_rel
        local["len_other_back"] = other16 + 9
        extra_fixes = []
        for at, nm in a.fixups:
            if nm in local:
                blob[at : at + 4] = rel32(at, local[nm])
            elif nm in name_id:
                extra_fixes.append((at, name_id[nm]))
            else:
                raise SystemExit("unknown fix " + nm)
        fixes.extend(extra_fixes)
        blob[BODY_SITE] = 0xE9
        blob[BODY_SITE + 1 : BODY_SITE + 5] = rel32(BODY_SITE + 1, local["cl_bodypark"])
        for k in range(BODY_SITE + 5, BODY_CONT):
            blob[k] = 0x90
        fixes = [(off, idn) for off, idn in fixes if not (BODY_SITE <= off < BODY_CONT)]
        blob[write16] = 0xE9
        blob[write16 + 1 : write16 + 5] = rel32(write16 + 1, local["len_write"])
        blob[write16 + 5 : write16 + 9] = b"\x90\x90\x90\x90"
        blob[other16] = 0xE9
        blob[other16 + 1 : other16 + 5] = rel32(other16 + 1, local["len_other"])
        blob[other16 + 5 : other16 + 9] = b"\x90\x90\x90\x90"
        changed.append(("body_park", BODY_SITE, BODY_CONT))
        changed.append(("len_write", write16, write16 + 9))
        changed.append(("len_other", other16, other16 + 9))
        print(blob_name, "appended", hex(local["cl_bodypark"]))
    else:
        print(blob_name, "body park already jmp")

    i = gate
    while i + 18 <= len(blob):
        if bytes(blob[i : i + 7]) == CMP_CAP and bytes(blob[i + 7 : i + 13]) == JBE6:
            jae_at = i + 9
            blob[i + 7] = 0x0F
            blob[i + 8] = 0x83
            blob[i + 9 : i + 13] = rel32(jae_at, cl401)
            if bytes(blob[i + 13 : i + 19]) == MOV_R8D_4096:
                blob[i + 13 : i + 19] = b"\x90" * 6
                changed.append(("cap", i + 7, i + 19))
            i += 19
            continue
        i += 1

    (SRC / blob_name).write_text(blob.hex() + "\n")
    (SRC / pins_name).write_text(b"".join(pack_rec(o, i) for o, i in pins).hex() + "\n")
    (SRC / fixes_name).write_text(b"".join(pack_rec(o, i) for o, i in fixes).hex() + "\n")
    print(blob_name, "len", len(blob), "changes", [(n, hex(a), hex(b)) for n, a, b in changed])
    return changed


def patch_r4_cap():
    names = names_of("define netNamesR4")
    blob = bytearray(bytes.fromhex((SRC / "rt-net-r4-blob.txt").read_text().strip()))
    pins = load_table(SRC / "rt-net-r4-pins.txt")
    gate = pin_off(pins, names, "cl_blockgate")
    cl401 = pin_off(pins, names, "cl_401")
    changed = []
    i = gate
    while i + 18 <= len(blob):
        if bytes(blob[i : i + 7]) == CMP_CAP and bytes(blob[i + 7 : i + 13]) == JBE6:
            jae_at = i + 9
            blob[i + 7] = 0x0F
            blob[i + 8] = 0x83
            blob[i + 9 : i + 13] = rel32(jae_at, cl401)
            if bytes(blob[i + 13 : i + 19]) == MOV_R8D_4096:
                blob[i + 13 : i + 19] = b"\x90" * 6
                changed.append(("cap", i + 7, i + 19))
            i += 19
            continue
        i += 1
    (SRC / "rt-net-r4-blob.txt").write_text(blob.hex() + "\n")
    print("rt-net-r4-blob.txt changes", [(n, hex(a), hex(b)) for n, a, b in changed])


def patch_parse_endcheck():
    blob_path = SRC / "rt-net-blob.txt"
    blob = bytearray(bytes.fromhex(blob_path.read_text().strip()))
    old = bytes.fromhex("488b45f8488b08483b40080f85")
    new = bytes.fromhex("488b45f8488b08483b48080f85")
    i = blob.find(old)
    if i >= 0:
        blob[i:i + len(old)] = new
        blob_path.write_text(blob.hex() + "\n")
    print("parse_endcheck", hex(i) if i >= 0 else None)


def patch_parse_cursor():
    old = bytes.fromhex("488b0a4801c848894108")
    new = bytes.fromhex("4c8b024c01c148894808")
    old2 = bytes.fromhex("488b0a48030848894808")
    path = SRC / "rt-net-blob.txt"
    blob = bytearray(bytes.fromhex(path.read_text().strip()))
    hits = []
    i = 0
    while True:
        j = blob.find(old, i)
        if j < 0:
            break
        blob[j : j + len(old)] = new
        hits.append(j)
        i = j + len(old)
    if hits:
        path.write_text(blob.hex() + "\n")
    print("parse_cursor", [hex(x) for x in hits])


def main():
    n3 = names_of("define netNames\n")
    patch_three("rt-net-blob.txt", "rt-net-pins.txt", "rt-net-fixes.txt", n3)
    patch_r4_cap()
    patch_parse_cursor()
    patch_parse_endcheck()


if __name__ == "__main__":
    main()
