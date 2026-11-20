#!/usr/bin/env python3
"""Patch src/rt-net-blob.txt (+ pins/fixes) for bounded request bodies and token gate."""
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


def load_names():
    text = (SRC / "rt-net.vire").read_text()
    start = text.find("return [")
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
            if isinstance(x, (bytes, bytearray, list, tuple)):
                self.buf.extend(x)
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


def main():
    names = load_names()
    name_id = {n: i for i, n in enumerate(names)}
    blob = bytearray(bytes.fromhex((SRC / "rt-net-blob.txt").read_text().strip()))
    pins_raw = (SRC / "rt-net-pins.txt").read_text().strip()
    fixes_raw = (SRC / "rt-net-fixes.txt").read_text().strip()
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

    def retarget(at, to_name):
        nid = name_id[to_name]
        for i, (off, idn) in enumerate(fixes):
            if off == at:
                fixes[i] = (off, nid)
                return
        raise SystemExit("missing fix at 0x%x" % at)

    # Default [ctx+0x40] still stores rax (last helper return). GET /health does
    # not read body. POST with Content-Length overwrites this via cl_gotbody
    # mktext (now a leaf heap text). Do not store txt_empty (.data): parking a
    # non-heap pointer as tag 2 makes GC walk .data as objects and OOM.

    # Recv remain = headerEnd+4+contentLength-got without treating headerEnd as a pointer.
    old = bytes.fromhex("488b45f8488b08488b500848035010488b40184883c00448034048482b40104989c04531c9")
    new = bytes.fromhex("488b45f8488b08488b5008480350104c8b40184983c0044c0340484c2b40104531c9909090")
    assert blob[0x9F6:0x9F6 + len(old)] == old
    blob[0x9F6:0x9F6 + len(new)] = new

    # Keep the existing per-connection buffer (0x14080). Host MaxRequestBody is
    # still enforced on Content-Length (0xF4240). Growing this to 1MB+headers
    # is unnecessary for the recorded POST /block goldens and blew the arena
    # when combined with a non-leaf text.

    # Content-Length cap 1000000 (host HttpWire.MaxRequestBody).
    assert blob[0x969:0x96F] == bytes([0x48, 0x3D, 0x00, 0x00, 0x01, 0x00])
    blob[0x969:0x96F] = bytes([0x48, 0x3D, 0x40, 0x42, 0x0F, 0x00])

    # Do not trampoline rt_net_mktext: method/path also use it, and an extra
    # alloc in a trampoline double-allocates (rcx becomes a pointer-as-size → OOM).
    # POST body is marked leaf after mktext at cl_bodyleaf.

    # Missing Content-Length on POST/PUT -> 411, not a stale body handle.
    retarget(0x9BC, "cl_needcl")

    # Header scan used `jae hddone` when scan == headerEnd. headerEnd is the CR
    # of the terminating \r\n\r\n, which is also the last header's line CR, so
    # the last header was never parsed. Connection (or anything) before
    # Content-Length therefore missed CL and returned 411. Jump to cl_hline
    # instead: empty line still hits length==0 -> hddone; a last header is
    # parsed. Duplicate CL is already 400 via cl_notecl.
    retarget(0x874, "cl_hline")

    # After mktext of the body, mark leaf and store; nobody/GET jumps tokengate.
    # Overwrite only the store (8 bytes) with jmp cl_bodyleaf; leave call
    # rt_save_frame at 0xa73 intact so GET / nobody still works.
    assert blob[0xA6B:0xA73] == bytes.fromhex("488b4df848894140")
    blob[0xA6B:0xA73] = bytes.fromhex("e900000000909090")
    fixes.append((0xA6C, name_id["cl_bodyleaf"]))
    assert blob[0xA73] == 0xE8
    blob[0xA73] = 0xE9
    retarget(0xA74, "cl_tokengate")

    a = Asm(len(blob))

    a.pin("mktext_cap")
    a.emit(0xC3)  # unused (name kept so netNames stay aligned)

    a.pin("cl_needcl")
    a.emit(0x48, 0x8B, 0x4D, 0xF8)  # mov rcx, ctx
    a.emit(0x48, 0x8B, 0x49, 0x28)  # method
    a.lea_rdx("txt_POST")
    a.call("rt_texteq")
    a.emit(0x48, 0x85, 0xC0)
    a.jcc(0x85, "cl_411")
    a.emit(0x48, 0x8B, 0x4D, 0xF8)
    a.emit(0x48, 0x8B, 0x49, 0x28)
    a.lea_rdx("txt_PUT")
    a.call("rt_texteq")
    a.emit(0x48, 0x85, 0xC0)
    a.jcc(0x85, "cl_411")
    a.jmp("cl_nobody")

    a.pin("cl_411")
    a.lea_rdx("txt_err411")
    a.emit(0x49, 0x89, 0xD0)  # mov r8, rdx
    a.emit(0x48, 0x8B, 0x4D, 0xF8)
    a.emit(0x48, 0x8B, 0x09)
    a.emit(0xBA, 0x9B, 0x01, 0x00, 0x00)  # 411
    a.call("rt_net_sendhttp")
    a.emit(0xC9, 0xC3)

    a.pin("cl_401")
    a.lea_rdx("txt_err401")
    a.emit(0x49, 0x89, 0xD0)
    a.emit(0x48, 0x8B, 0x4D, 0xF8)
    a.emit(0x48, 0x8B, 0x09)
    a.emit(0xBA, 0x91, 0x01, 0x00, 0x00)  # 401
    a.call("rt_net_sendhttp")
    a.emit(0xC9, 0xC3)

    a.pin("cl_bodyleaf")
    a.emit(0x83, 0x48, 0xF8, 0x01)  # emitLeaf on body text
    a.emit(0x48, 0x8B, 0x4D, 0xF8)
    a.emit(0x48, 0x89, 0x41, 0x40)
    a.jmp("cl_nobody")

    a.pin("cl_tokengate")
    a.lea_rcx("txt_fcgenv")
    a.emit(0x48, 0x83, 0xC1, 0x08)  # +8 C string
    a.lea_rdx("token_env")
    a.emit(0x41, 0xB8, 0x00, 0x01, 0x00, 0x00)  # r8d = 256
    a.iat("iat_ev")
    a.emit(0x89, 0x45, 0xB0)  # token len at rbp-0x50
    a.emit(0x83, 0xF8, 0x10)
    a.jcc(0x82, "tg_route")  # jb <16 token off
    # health GET/HEAD /health
    a.emit(0x48, 0x8B, 0x4D, 0xF8)
    a.emit(0x48, 0x8B, 0x49, 0x30)
    a.lea_rdx("txt_healthp")
    a.call("rt_texteq")
    a.emit(0x48, 0x85, 0xC0)
    a.jcc(0x84, "tg_need")  # path != /health
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
    a.pin("tg_need")
    # hits=0, i=0, valptr=0, vallen=0 at rbp-0x70..
    a.emit(0x48, 0xC7, 0x45, 0x90, 0, 0, 0, 0)  # hits rbp-0x70
    a.emit(0x48, 0xC7, 0x45, 0x98, 0, 0, 0, 0)  # valptr
    a.emit(0x48, 0xC7, 0x45, 0xA0, 0, 0, 0, 0)  # vallen
    a.emit(0x48, 0xC7, 0x45, 0xA8, 0, 0, 0, 0)  # i
    a.pin("tg_scan")
    a.emit(0x48, 0x8B, 0x4D, 0xF8)
    a.emit(0x48, 0x8B, 0x45, 0xA8)  # i
    a.emit(0x48, 0x3B, 0x41, 0x18)  # cmp i, headerEnd
    a.jcc(0x83, "tg_scandone")  # jae
    # line start? i==0 or buf[i-2]==13 && buf[i-1]==10
    a.emit(0x48, 0x85, 0xC0)
    a.jcc(0x84, "tg_line")
    a.emit(0x48, 0x83, 0xF8, 0x02)
    a.jcc(0x82, "tg_nexti")  # i < 2
    a.emit(0x48, 0x8B, 0x51, 0x08)  # buf
    a.emit(0x80, 0x7C, 0x02, 0xFE, 0x0D)  # [buf+i-2] == CR
    a.jcc(0x85, "tg_nexti")
    a.emit(0x80, 0x7C, 0x02, 0xFF, 0x0A)
    a.jcc(0x85, "tg_nexti")
    a.pin("tg_line")
    a.emit(0x48, 0x8B, 0x4D, 0xF8)
    a.emit(0x48, 0x8B, 0x49, 0x08)
    a.emit(0x48, 0x03, 0x4D, 0xA8)  # rcx = buf+i
    a.lea_rdx("txt_xfctoken")
    a.call("rt_net_prefixci")
    a.emit(0x48, 0x85, 0xC0)
    a.jcc(0x84, "tg_nexti")
    a.emit(0x48, 0xFF, 0x45, 0x90)  # hits++
    a.emit(0x48, 0x8B, 0x4D, 0xF8)
    a.emit(0x48, 0x8B, 0x41, 0x08)
    a.emit(0x48, 0x03, 0x45, 0xA8)
    a.emit(0x48, 0x83, 0xC0, 0x0C)  # +12 (name 11 + colon)
    a.pin("tg_sp")
    a.emit(0x48, 0x8B, 0x4D, 0xF8)
    a.emit(0x4C, 0x8B, 0x41, 0x08)
    a.emit(0x4C, 0x03, 0x41, 0x18)  # r8 = buf+headerEnd
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
    a.pin("tg_nexti")
    a.emit(0x48, 0xFF, 0x45, 0xA8)
    a.jmp("tg_scan")
    a.pin("tg_scandone")
    a.emit(0x48, 0x83, 0x7D, 0x90, 0x01)
    a.jcc(0x85, "cl_401")
    a.lea_r9("token_left")
    a.emit(0x41, 0xB8, 0x00, 0x01, 0x00, 0x00)
    a.pin("zleft")
    a.emit(0x41, 0xC6, 0x01, 0x00)
    a.emit(0x49, 0xFF, 0xC1)
    a.emit(0x49, 0xFF, 0xC8)
    a.jcc(0x85, "zleft")
    a.lea_r9("token_right")
    a.emit(0x41, 0xB8, 0x00, 0x01, 0x00, 0x00)
    a.pin("zright")
    a.emit(0x41, 0xC6, 0x01, 0x00)
    a.emit(0x49, 0xFF, 0xC1)
    a.emit(0x49, 0xFF, 0xC8)
    a.jcc(0x85, "zright")
    a.emit(0x4C, 0x8B, 0x45, 0xA0)
    a.emit(0x49, 0x81, 0xF8, 0x00, 0x01, 0x00, 0x00)
    a.jcc(0x86, "cp_g")
    a.emit(0x41, 0xB8, 0x00, 0x01, 0x00, 0x00)
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
    a.emit(0x49, 0x81, 0xF8, 0x00, 0x01, 0x00, 0x00)
    a.jcc(0x86, "cp_w2")
    a.emit(0x41, 0xB8, 0x00, 0x01, 0x00, 0x00)
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
    a.emit(0x41, 0xB8, 0x00, 0x01, 0x00, 0x00)
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

    # cl_route_push is 0xa78

    blob.extend(a.buf)

    # extra names not in list yet — caller updates rt-net.vire first.
    extra_pins = {
        "mktext_cap": a.labels["mktext_cap"],
        "cl_needcl": a.labels["cl_needcl"],
        "cl_411": a.labels["cl_411"],
        "cl_401": a.labels["cl_401"],
        "cl_tokengate": a.labels["cl_tokengate"],
        "cl_bodyleaf": a.labels["cl_bodyleaf"],
    }
    for n, off in extra_pins.items():
        if n not in name_id:
            raise SystemExit("name missing in netNames: " + n)
        pins.append((off, name_id[n]))

    # local labels that are also jump targets inside append use packed fixes
    local = dict(a.labels)
    local["mktext_oom"] = None
    local["mktext_after_alloc"] = 0x7B
    local["cl_nobody"] = 0xA73
    local["cl_route_push"] = 0xA78

    for at, nm in a.fixups:
        if nm == "mktext_after_alloc":
            rel = 0x7B - (at + 4)
            blob[at : at + 4] = pack_u32(rel & 0xFFFFFFFF)
            continue
        if nm == "cl_route_push":
            rel = 0xA78 - (at + 4)
            blob[at : at + 4] = pack_u32(rel & 0xFFFFFFFF)
            continue
        if nm in local and nm not in name_id:
            # internal relative jumps encoded now
            tgt = local[nm]
            rel = tgt - (at + 4)
            blob[at : at + 4] = pack_u32(rel & 0xFFFFFFFF)
            continue
        if nm not in name_id:
            raise SystemExit("unknown fix " + nm)
        fixes.append((at, name_id[nm]))

    (SRC / "rt-net-blob.txt").write_text(blob.hex() + "\n")
    pin_hex = b"".join(pack_rec(o, i) for o, i in pins).hex()
    fix_hex = b"".join(pack_rec(o, i) for o, i in fixes).hex()
    (SRC / "rt-net-pins.txt").write_text(pin_hex + "\n")
    (SRC / "rt-net-fixes.txt").write_text(fix_hex + "\n")
    print("blob", len(blob), "pins", len(pins), "fixes", len(fixes))
    for n, off in extra_pins.items():
        print("pin", n, hex(off))


if __name__ == "__main__":
    main()
