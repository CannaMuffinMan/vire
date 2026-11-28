#!/usr/bin/env python3
"""Append native POST /block deny-by-default Bearer gate onto packed listen blobs."""
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SRC = ROOT / "src"
EXTRA = [
    "txt_infop",
    "txt_chainp",
    "txt_blockp",
    "txt_blockenv",
    "txt_bearer",
    "txt_authznm",
    "cl_blockgate",
]


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
            elif isinstance(x, str):
                self.buf.extend(x.encode("ascii"))
            else:
                self.buf.append(x)

    def rel32(self, name):
        self.fixups.append((self.here(), name))
        self.emit(0, 0, 0, 0)

    def call(self, name):
        self.emit(0xE8)
        self.rel32(name)

    def jmp(self, name):
        self.emit(0xE9)
        self.rel32(name)

    def jcc(self, cc, name):
        self.emit(0x0F, cc)
        self.rel32(name)

    def lea_rdx(self, name):
        self.emit(0x48, 0x8D, 0x15)
        self.rel32(name)

    def lea_rcx(self, name):
        self.emit(0x48, 0x8D, 0x0D)
        self.rel32(name)

    def lea_r9(self, name):
        self.emit(0x4C, 0x8D, 0x0D)
        self.rel32(name)

    def lea_r10(self, name):
        self.emit(0x4C, 0x8D, 0x15)
        self.rel32(name)

    def iat(self, name):
        self.emit(0xFF, 0x15)
        self.rel32(name)

    def park(self, name, s, cstr=False):
        self.pin(name)
        n = len(s)
        self.emit(list(n.to_bytes(8, "little")))
        self.emit(s)
        if cstr:
            self.emit(0)


def emit_gate(a):
    a.park("txt_infop", "/info")
    a.park("txt_chainp", "/chain")
    a.park("txt_blockp", "/block")
    a.park("txt_blockenv", "FCG_BLOCK_TOKEN", cstr=True)
    a.park("txt_bearer", "bearer")
    a.park("txt_authznm", "authorization")

    a.pin("cl_blockgate")
    # GET/HEAD /health /info /chain stay open.
    for path, skip in (("txt_healthp", "bg_nhealth"), ("txt_infop", "bg_ninfo"), ("txt_chainp", "bg_nchain")):
        a.emit(0x48, 0x8B, 0x4D, 0xF8)
        a.emit(0x48, 0x8B, 0x49, 0x30)
        a.lea_rdx(path)
        a.call("rt_texteq")
        a.emit(0x48, 0x85, 0xC0)
        a.jcc(0x84, skip)
        a.emit(0x48, 0x8B, 0x4D, 0xF8)
        a.emit(0x48, 0x8B, 0x49, 0x28)
        a.lea_rdx("txt_GET")
        a.call("rt_texteq")
        a.emit(0x48, 0x85, 0xC0)
        a.jcc(0x85, "tg_route")
        a.emit(0x48, 0x8B, 0x4D, 0xF8)
        a.emit(0x48, 0x8B, 0x49, 0x28)
        a.lea_rdx("txt_HEAD")
        a.call("rt_texteq")
        a.emit(0x48, 0x85, 0xC0)
        a.jcc(0x85, "tg_route")
        a.pin(skip)

    # POST /block write path.
    a.emit(0x48, 0x8B, 0x4D, 0xF8)
    a.emit(0x48, 0x8B, 0x49, 0x28)
    a.lea_rdx("txt_POST")
    a.call("rt_texteq")
    a.emit(0x48, 0x85, 0xC0)
    a.jcc(0x84, "bg_other")
    a.emit(0x48, 0x8B, 0x4D, 0xF8)
    a.emit(0x48, 0x8B, 0x49, 0x30)
    a.lea_rdx("txt_blockp")
    a.call("rt_texteq")
    a.emit(0x48, 0x85, 0xC0)
    a.jcc(0x84, "bg_other")
    a.lea_rcx("txt_blockenv")
    a.emit(0x48, 0x83, 0xC1, 0x08)
    a.lea_rdx("token_env")
    a.emit(0x41, 0xB8, 0x00, 0x10, 0x00, 0x00)
    a.iat("iat_ev")
    a.emit(0x85, 0xC0)
    a.jcc(0x85, "bg_have")
    a.lea_rcx("txt_fcgenv")
    a.emit(0x48, 0x83, 0xC1, 0x08)
    a.lea_rdx("token_env")
    a.emit(0x41, 0xB8, 0x00, 0x10, 0x00, 0x00)
    a.iat("iat_ev")
    a.pin("bg_have")
    a.emit(0x89, 0x45, 0xB0)
    a.emit(0x83, 0xF8, 0x10)
    a.jcc(0x82, "cl_401")  # missing or <16: deny writes
    a.lea_rdx("txt_authznm")
    a.lea_rcx("token_right")
    a.emit(0x48, 0x89, 0x91, 0xF8, 0, 0, 0)
    a.emit(0xC6, 0x81, 0xF7, 0, 0, 0, 14)
    a.emit(0xC6, 0x81, 0xF6, 0, 0, 0, 1)
    a.jmp("bg_scan")

    a.pin("bg_other")
    a.lea_rcx("txt_fcgenv")
    a.emit(0x48, 0x83, 0xC1, 0x08)
    a.lea_rdx("token_env")
    a.emit(0x41, 0xB8, 0x00, 0x10, 0x00, 0x00)
    a.iat("iat_ev")
    a.emit(0x89, 0x45, 0xB0)
    a.emit(0x83, 0xF8, 0x10)
    a.jcc(0x82, "tg_route")  # non-write keep fail-open if API token short
    a.lea_rdx("txt_xfctoken")
    a.lea_rcx("token_right")
    a.emit(0x48, 0x89, 0x91, 0xF8, 0, 0, 0)
    a.emit(0xC6, 0x81, 0xF7, 0, 0, 0, 12)
    a.emit(0xC6, 0x81, 0xF6, 0, 0, 0, 0)

    a.pin("bg_scan")
    a.emit(0x48, 0xC7, 0x45, 0x90, 0, 0, 0, 0)
    a.emit(0x48, 0xC7, 0x45, 0x98, 0, 0, 0, 0)
    a.emit(0x48, 0xC7, 0x45, 0xA0, 0, 0, 0, 0)
    a.emit(0x48, 0xC7, 0x45, 0xA8, 0, 0, 0, 0)
    a.pin("tg_scan")
    a.emit(0x48, 0x8B, 0x4D, 0xF8)
    a.emit(0x48, 0x8B, 0x45, 0xA8)
    a.emit(0x48, 0x3D, 0x00, 0x40, 0x00, 0x00)  # i >= 16KiB
    a.jcc(0x83, "tg_scandone")
    a.emit(0x48, 0x8B, 0x4D, 0xF8)
    a.emit(0x48, 0x3B, 0x41, 0x18)
    a.jcc(0x83, "tg_scandone")
    a.emit(0x48, 0x85, 0xC0)
    a.jcc(0x84, "tg_line")
    a.emit(0x48, 0x83, 0xF8, 0x02)
    a.jcc(0x82, "tg_nexti")
    a.emit(0x48, 0x8B, 0x51, 0x08)
    a.emit(0x80, 0x7C, 0x02, 0xFE, 0x0D)
    a.jcc(0x85, "tg_nexti")
    a.emit(0x80, 0x7C, 0x02, 0xFF, 0x0A)
    a.jcc(0x85, "tg_nexti")
    a.pin("tg_line")
    a.emit(0x48, 0x8B, 0x4D, 0xF8)
    a.emit(0x48, 0x8B, 0x49, 0x08)
    a.emit(0x48, 0x85, 0xC9)
    a.jcc(0x84, "cl_401")
    a.emit(0x48, 0x03, 0x4D, 0xA8)
    a.lea_rdx("token_right")
    a.emit(0x48, 0x8B, 0x92, 0xF8, 0, 0, 0)
    a.emit(0x48, 0x85, 0xD2)
    a.jcc(0x84, "cl_401")
    a.call("rt_net_prefixci")
    a.emit(0x48, 0x85, 0xC0)
    a.jcc(0x84, "tg_nexti")
    a.emit(0x48, 0xFF, 0x45, 0x90)
    a.emit(0x48, 0x8B, 0x4D, 0xF8)
    a.emit(0x48, 0x8B, 0x41, 0x08)
    a.emit(0x48, 0x03, 0x45, 0xA8)
    a.lea_rdx("token_right")
    a.emit(0x0F, 0xB6, 0x92, 0xF7, 0, 0, 0)
    a.emit(0x48, 0x01, 0xD0)
    a.pin("tg_sp")
    a.emit(0x48, 0x8B, 0x4D, 0xF8)
    a.emit(0x4C, 0x8B, 0x41, 0x08)
    a.emit(0x4C, 0x03, 0x41, 0x18)
    a.emit(0x4C, 0x39, 0xC0)
    a.jcc(0x83, "tg_val")
    a.emit(0x8A, 0x10)
    a.emit(0x80, 0xFA, 0x20)
    a.jcc(0x84, "tg_skip1")
    a.emit(0x80, 0xFA, 0x09)
    a.jcc(0x85, "tg_val")
    a.pin("tg_skip1")
    a.emit(0x48, 0xFF, 0xC0)
    a.jmp("tg_sp")
    a.pin("tg_val")
    a.emit(0x48, 0x89, 0x45, 0x98)
    a.pin("tg_vend")
    a.emit(0x48, 0x8B, 0x4D, 0xF8)
    a.emit(0x4C, 0x8B, 0x41, 0x08)
    a.emit(0x4C, 0x03, 0x41, 0x18)
    a.emit(0x4C, 0x39, 0xC0)
    a.jcc(0x83, "tg_trim")
    a.emit(0x8A, 0x10)
    a.emit(0x80, 0xFA, 0x0D)
    a.jcc(0x84, "tg_trim")
    a.emit(0x48, 0xFF, 0xC0)
    a.jmp("tg_vend")
    a.pin("tg_trim")
    a.emit(0x48, 0x8B, 0x55, 0x98)
    a.pin("tg_tr1")
    a.emit(0x48, 0x39, 0xD0)
    a.jcc(0x86, "tg_tset")
    a.emit(0x8A, 0x48, 0xFF)
    a.emit(0x80, 0xF9, 0x20)
    a.jcc(0x84, "tg_tdec")
    a.emit(0x80, 0xF9, 0x09)
    a.jcc(0x85, "tg_tset")
    a.pin("tg_tdec")
    a.emit(0x48, 0xFF, 0xC8)
    a.jmp("tg_tr1")
    a.pin("tg_tset")
    a.emit(0x48, 0x2B, 0x45, 0x98)
    a.emit(0x48, 0x89, 0x45, 0xA0)
    a.lea_rdx("token_right")
    a.emit(0x80, 0xBA, 0xF6, 0, 0, 0, 1)
    a.jcc(0x85, "tg_nexti")
    a.emit(0x48, 0x83, 0x7D, 0xA0, 0x07)
    a.jcc(0x82, "tg_nobear")
    a.emit(0x48, 0x8B, 0x45, 0x98)
    a.emit(0x8A, 0x08)
    a.emit(0x80, 0xC9, 0x20)
    a.emit(0x80, 0xF9, 0x62)
    a.jcc(0x85, "tg_nobear")
    a.emit(0x8A, 0x48, 0x01)
    a.emit(0x80, 0xC9, 0x20)
    a.emit(0x80, 0xF9, 0x65)
    a.jcc(0x85, "tg_nobear")
    a.emit(0x8A, 0x48, 0x02)
    a.emit(0x80, 0xC9, 0x20)
    a.emit(0x80, 0xF9, 0x61)
    a.jcc(0x85, "tg_nobear")
    a.emit(0x8A, 0x48, 0x03)
    a.emit(0x80, 0xC9, 0x20)
    a.emit(0x80, 0xF9, 0x72)
    a.jcc(0x85, "tg_nobear")
    a.emit(0x8A, 0x48, 0x04)
    a.emit(0x80, 0xC9, 0x20)
    a.emit(0x80, 0xF9, 0x65)
    a.jcc(0x85, "tg_nobear")
    a.emit(0x8A, 0x48, 0x05)
    a.emit(0x80, 0xC9, 0x20)
    a.emit(0x80, 0xF9, 0x72)
    a.jcc(0x85, "tg_nobear")
    a.emit(0x8A, 0x48, 0x06)
    a.emit(0x80, 0xF9, 0x20)
    a.jcc(0x84, "tg_bskip")
    a.emit(0x80, 0xF9, 0x09)
    a.jcc(0x85, "tg_nobear")
    a.pin("tg_bskip")
    a.emit(0x48, 0x83, 0xC0, 0x07)
    a.pin("tg_bsp")
    a.emit(0x48, 0x8B, 0x4D, 0xF8)
    a.emit(0x4C, 0x8B, 0x41, 0x08)
    a.emit(0x4C, 0x03, 0x41, 0x18)
    a.emit(0x4C, 0x39, 0xC0)
    a.jcc(0x83, "tg_bset")
    a.emit(0x8A, 0x10)
    a.emit(0x80, 0xFA, 0x20)
    a.jcc(0x84, "tg_binc")
    a.emit(0x80, 0xFA, 0x09)
    a.jcc(0x85, "tg_bset")
    a.pin("tg_binc")
    a.emit(0x48, 0xFF, 0xC0)
    a.jmp("tg_bsp")
    a.pin("tg_bset")
    a.emit(0x48, 0x8B, 0x4D, 0x98)
    a.emit(0x48, 0x03, 0x4D, 0xA0)
    a.emit(0x48, 0x89, 0x45, 0x98)
    a.emit(0x48, 0x29, 0xC1)
    a.emit(0x48, 0x89, 0x4D, 0xA0)
    a.jmp("tg_nexti")
    a.pin("tg_nobear")
    a.emit(0x48, 0xC7, 0x45, 0x98, 0, 0, 0, 0)
    a.emit(0x48, 0xC7, 0x45, 0xA0, 0, 0, 0, 0)
    a.pin("tg_nexti")
    a.emit(0x48, 0xFF, 0x45, 0xA8)
    a.jmp("tg_scan")
    a.pin("tg_scandone")
    a.emit(0x48, 0x83, 0x7D, 0x90, 0x01)
    a.jcc(0x85, "cl_401")
    a.lea_r9("token_left")
    a.emit(0x41, 0xB8, 0x00, 0x10, 0x00, 0x00)
    a.pin("zleft")
    a.emit(0x41, 0xC6, 0x01, 0x00)
    a.emit(0x49, 0xFF, 0xC1)
    a.emit(0x49, 0xFF, 0xC8)
    a.jcc(0x85, "zleft")
    a.lea_r9("token_right")
    a.emit(0x41, 0xB8, 0x00, 0x10, 0x00, 0x00)
    a.pin("zright")
    a.emit(0x41, 0xC6, 0x01, 0x00)
    a.emit(0x49, 0xFF, 0xC1)
    a.emit(0x49, 0xFF, 0xC8)
    a.jcc(0x85, "zright")
    a.emit(0x4C, 0x8B, 0x45, 0xA0)
    a.emit(0x49, 0x81, 0xF8, 0x00, 0x10, 0x00, 0x00)
    a.jcc(0x83, "cl_401")
    a.pin("cp_g")
    a.lea_r9("token_left")
    a.emit(0x4C, 0x8B, 0x55, 0x98)
    a.emit(0x4D, 0x85, 0xC0)
    a.jcc(0x84, "cp_w")
    a.pin("cp_gl")
    a.emit(0x41, 0x8A, 0x02)
    a.emit(0x41, 0x88, 0x01)
    a.emit(0x49, 0xFF, 0xC1)
    a.emit(0x49, 0xFF, 0xC2)
    a.emit(0x49, 0xFF, 0xC8)
    a.jcc(0x85, "cp_gl")
    a.pin("cp_w")
    a.emit(0x44, 0x8B, 0x45, 0xB0)
    a.emit(0x49, 0x81, 0xF8, 0x00, 0x10, 0x00, 0x00)
    a.jcc(0x83, "cl_401")
    a.pin("cp_w2")
    a.lea_r9("token_right")
    a.lea_r10("token_env")
    a.emit(0x4D, 0x85, 0xC0)
    a.jcc(0x84, "ct_go")
    a.pin("cp_wl")
    a.emit(0x41, 0x8A, 0x02)
    a.emit(0x41, 0x88, 0x01)
    a.emit(0x49, 0xFF, 0xC1)
    a.emit(0x49, 0xFF, 0xC2)
    a.emit(0x49, 0xFF, 0xC8)
    a.jcc(0x85, "cp_wl")
    a.pin("ct_go")
    a.emit(0x8B, 0x45, 0xA0)
    a.emit(0x33, 0x45, 0xB0)
    a.emit(0x89, 0x45, 0x88)
    a.lea_r9("token_left")
    a.lea_r10("token_right")
    a.emit(0x41, 0xB8, 0x00, 0x10, 0x00, 0x00)
    a.pin("ct_lp")
    a.emit(0x41, 0x8A, 0x01)
    a.emit(0x41, 0x32, 0x02)
    a.emit(0x0F, 0xB6, 0xC0)
    a.emit(0x09, 0x45, 0x88)
    a.emit(0x49, 0xFF, 0xC1)
    a.emit(0x49, 0xFF, 0xC2)
    a.emit(0x49, 0xFF, 0xC8)
    a.jcc(0x85, "ct_lp")
    a.emit(0x83, 0x7D, 0x88, 0x00)
    a.jcc(0x85, "cl_401")
    a.pin("tg_route")
    a.call("rt_save_frame")
    a.jmp("cl_route_push")


def patch_one(blob_name, pins_name, fixes_name, names):
    name_id = {n: i for i, n in enumerate(names)}
    for n in EXTRA:
        if n not in name_id:
            raise SystemExit("missing name " + n + " in " + blob_name)
    blob = bytearray(bytes.fromhex((SRC / blob_name).read_text().strip()))
    pins_raw = (SRC / pins_name).read_text().strip()
    fixes_raw = (SRC / fixes_name).read_text().strip()
    pins = []
    i = 0
    while i + 11 < len(pins_raw):
        pins.append((parse_u32(pins_raw, i), parse_u16(pins_raw, i + 8)))
        i += 12
    fixes = []
    i = 0
    while i + 11 < len(fixes_raw):
        fixes.append((parse_u32(fixes_raw, i), parse_u16(fixes_raw, i + 8)))
        i += 12
    if any(idn == name_id["cl_blockgate"] for _, idn in pins):
        print(blob_name, "already patched")
        return

    tok = None
    for off, idn in pins:
        if names[idn] == "cl_tokengate":
            tok = off
            break
    if tok is None:
        raise SystemExit("no cl_tokengate pin in " + pins_name)
    # overwrite lea rcx with jmp cl_blockgate; drop relocs that sit in those 5 bytes
    blob[tok] = 0xE9
    blob[tok + 1 : tok + 5] = b"\x00\x00\x00\x00"
    fixes = [(off, idn) for off, idn in fixes if not (tok <= off < tok + 5)]
    fixes.append((tok + 1, name_id["cl_blockgate"]))

    a = Asm(len(blob))
    emit_gate(a)
    blob.extend(a.buf)
    for n in EXTRA:
        pins.append((a.labels[n], name_id[n]))

    local = dict(a.labels)
    local["cl_route_push"] = 0xA78
    for at, nm in a.fixups:
        if nm == "cl_route_push":
            rel = 0xA78 - (at + 4)
            blob[at : at + 4] = pack_u32(rel & 0xFFFFFFFF)
            continue
        if nm in local:
            rel = local[nm] - (at + 4)
            blob[at : at + 4] = pack_u32(rel & 0xFFFFFFFF)
            continue
        if nm not in name_id:
            raise SystemExit("unknown fix " + nm)
        fixes.append((at, name_id[nm]))

    (SRC / blob_name).write_text(blob.hex() + "\n")
    (SRC / pins_name).write_text(b"".join(pack_rec(o, i) for o, i in pins).hex() + "\n")
    (SRC / fixes_name).write_text(b"".join(pack_rec(o, i) for o, i in fixes).hex() + "\n")
    print(blob_name, "blob", len(blob), "pins", len(pins), "fixes", len(fixes), "gate", hex(a.labels["cl_blockgate"]))


def main():
    n3 = names_of("define netNames\n")
    n4 = names_of("define netNamesR4")
    patch_one("rt-net-blob.txt", "rt-net-pins.txt", "rt-net-fixes.txt", n3)
    patch_one("rt-net-r4-blob.txt", "rt-net-r4-pins.txt", "rt-net-r4-fixes.txt", n4)


if __name__ == "__main__":
    main()
