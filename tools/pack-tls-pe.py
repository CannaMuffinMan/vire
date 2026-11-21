#!/usr/bin/env python3
"""Assemble src/rt-tls-pe.vire emit* into packed blob/pins/fixes (itemCap-safe)."""
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SRC = ROOT / "src" / "rt-tls-pe.vire"


def u32(n):
    n = int(n) & 0xFFFFFFFF
    return bytes((n & 255, (n >> 8) & 255, (n >> 16) & 255, (n >> 24) & 255))


class Asm:
    def __init__(self):
        self.image = bytearray()
        self.fixes = []
        self.labels = {}

    def emit_bytes(self, bs):
        self.image.extend(bs)

    def emit_u8(self, n):
        self.image.append(int(n) & 255)

    def emit_u32(self, n):
        self.image.extend(u32(n))

    def emit_rel(self, name):
        self.fixes.append((len(self.image), name))
        self.image.extend(b"\x00\x00\x00\x00")

    def pin(self, name):
        self.labels[name] = len(self.image)

    def emit_pro(self):
        self.emit_bytes(bytes([85, 72, 137, 229, 72, 129, 236, 128, 0, 0, 0]))

    def emit_epi(self):
        self.emit_bytes(bytes([201, 195]))

    def emit_call_to(self, name):
        self.emit_bytes(bytes([232]))
        self.emit_rel(name)

    def emit_jmp_to(self, name):
        self.emit_bytes(bytes([233]))
        self.emit_rel(name)

    def emit_fail(self, name):
        self.emit_bytes(bytes([72, 141, 13]))
        self.emit_rel(name)
        self.emit_call_to("rt_fail")

    def emit_pop2(self):
        self.emit_bytes(bytes([73, 131, 237, 16, 77, 139, 69, 0, 77, 139, 77, 8, 73, 131, 237, 16, 73, 139, 69, 0, 73, 139, 85, 8]))

    def emit_pop1(self):
        self.emit_bytes(bytes([73, 131, 237, 16, 73, 139, 69, 0, 73, 139, 85, 8]))

    def emit_push_tag(self, tag):
        self.emit_bytes(bytes([73, 199, 69, 0]))
        self.emit_u32(tag)
        self.emit_bytes(bytes([73, 137, 85, 8, 73, 131, 197, 16]))

    def emit_iat(self, name):
        self.emit_bytes(bytes([255, 21]))
        self.emit_rel(name)


def parse_args(s):
    s = s.strip()
    out = []
    i = 0
    while i < len(s):
        if s[i] in " \t\n,":
            i += 1
            continue
        if s[i] == '"':
            j = i + 1
            buf = []
            while j < len(s) and s[j] != '"':
                buf.append(s[j])
                j += 1
            out.append(("str", "".join(buf)))
            i = j + 1
            continue
        if s[i].isdigit() or (s[i] == "-" and i + 1 < len(s) and s[i + 1].isdigit()):
            j = i + 1
            while j < len(s) and s[j].isdigit():
                j += 1
            out.append(("num", int(s[i:j])))
            i = j
            continue
        j = i
        while j < len(s) and s[j] not in ", \t\n":
            j += 1
        out.append(("id", s[i:j]))
        i = j
    return out


def run():
    text = SRC.read_text()
    a = Asm()
    # Execute statements inside define bodies in file order, but only when
    # emitTlsPeGuest is invoked (it calls the helpers). We interpret calls.
    funcs = {}
    cur = None
    body = []
    for line in text.splitlines():
        raw = line.strip()
        if raw.startswith("define "):
            if cur:
                funcs[cur] = body
            cur = raw.split()[1]
            body = []
            continue
        if raw == "end":
            if cur:
                funcs[cur] = body
                cur = None
                body = []
            continue
        if cur:
            if raw.startswith("~") or raw == "":
                continue
            body.append(raw)
    if cur:
        funcs[cur] = body

    def exec_fn(name):
        for stmt in funcs[name]:
            exec_stmt(stmt)

    def exec_stmt(stmt):
        if stmt == "return image":
            return
        if stmt.startswith("let image be "):
            stmt = stmt[len("let image be ") :]
        if stmt.startswith("emitHex with image, "):
            hx = stmt.split('"', 1)[1].rsplit('"', 1)[0]
            a.emit_bytes(bytes.fromhex(hx))
            return
        if stmt.startswith("emitList with image, ["):
            inner = stmt[stmt.index("[") + 1 : stmt.rindex("]")]
            nums = [int(x.strip()) for x in inner.split(",") if x.strip()]
            a.emit_bytes(bytes(n & 255 for n in nums))
            return
        if stmt.startswith("emitU32 with image, "):
            a.emit_u32(int(stmt.split(",")[-1].strip()))
            return
        if stmt.startswith("emitU8 with image, "):
            a.emit_u8(int(stmt.split(",")[-1].strip()))
            return
        if stmt.startswith("emitRel with image, fixes, "):
            name = stmt.split(",", 2)[2].strip().strip('"')
            a.emit_rel(name)
            return
        if stmt.startswith("pin with labels, "):
            # pin with labels, "name", image
            name = stmt.split(",", 1)[1].split(",")[0].strip().strip('"')
            a.pin(name)
            return
        if stmt.startswith("emitLeaf with image"):
            a.emit_bytes(bytes([131, 72, 248, 1]))
            return
        if stmt.startswith("emitPro with image"):
            a.emit_pro()
            return
        if stmt.startswith("emitEpi with image"):
            a.emit_epi()
            return
        if stmt.startswith("emitCallTo with image, fixes, "):
            name = stmt.split(",", 2)[2].strip().strip('"')
            a.emit_call_to(name)
            return
        if stmt.startswith("emitJcc with image, fixes, "):
            rest = stmt.split(",", 2)[2].strip()  # '134, "tls_recv_cap"'
            op_s, name_s = rest.split(",", 1)
            a.emit_u8(15)
            a.emit_u8(int(op_s.strip()))
            a.emit_rel(name_s.strip().strip('"'))
            return
        if stmt.startswith("emitJmpTo with image, fixes, "):
            name = stmt.split(",", 2)[2].strip().strip('"')
            a.emit_jmp_to(name)
            return
        if stmt.startswith("emitFail with image, fixes, "):
            name = stmt.split(",", 2)[2].strip().strip('"')
            a.emit_fail(name)
            return
        if stmt.startswith("emitPop2 with image"):
            a.emit_pop2()
            return
        if stmt.startswith("emitPop1 with image"):
            a.emit_pop1()
            return
        if stmt.startswith("emitPushTag with image, "):
            a.emit_push_tag(int(stmt.split(",")[-1].strip()))
            return
        if stmt.startswith("let image be emitIat with image, fixes, ") or stmt.startswith(
            "emitIat with image, fixes, "
        ):
            name = stmt.split(",", 2)[2].strip().strip('"')
            a.emit_iat(name)
            return
        if stmt.startswith("let image be emitTls") or stmt.startswith("emitTls"):
            fn = stmt.split()[0]
            if fn == "let":
                fn = stmt.split()[3]
            if fn.endswith("with"):
                fn = fn[: -len("with")].strip() if False else stmt.split()[3 if stmt.startswith("let") else 0]
            # "let image be emitTlsCopyFns with image, fixes, labels"
            parts = stmt.split()
            if parts[0] == "let":
                fname = parts[3]
            else:
                fname = parts[0]
            exec_fn(fname)
            return
        raise SystemExit("unhandled: " + stmt)

    exec_fn("emitTlsPeGuest")
    blob = bytes(a.image).hex()
    names = []
    for _, n in a.fixes:
        if n not in names:
            names.append(n)
    for n in a.labels:
        if n not in names:
            names.append(n)
    idx = {n: i for i, n in enumerate(names)}
    pins = []
    for n, off in a.labels.items():
        pins.append(u32(off) + bytes(4) + bytes((idx[n] & 255, (idx[n] >> 8) & 255)))
        # 12-byte records like net: off u32, pad 4, id u16
    # parseU32 + parseU16 at +8; 12 bytes. pad 4 zeros.
    pin_raw = b"".join(
        u32(off) + b"\x00\x00\x00\x00" + bytes((idx[n] & 255, idx[n] >> 8 & 255))
        for n, off in a.labels.items()
    )
    fix_raw = b"".join(
        u32(at) + b"\x00\x00\x00\x00" + bytes((idx[n] & 255, idx[n] >> 8 & 255))
        for at, n in a.fixes
    )
    (ROOT / "src" / "rt-tls-pe-blob.txt").write_text(blob)
    (ROOT / "src" / "rt-tls-pe-pins.txt").write_text(pin_raw.hex())
    (ROOT / "src" / "rt-tls-pe-fixes.txt").write_text(fix_raw.hex())
    (ROOT / "src" / "rt-tls-pe-names.txt").write_text("\n".join(names) + "\n")
    print("blob_bytes", len(a.image), "pins", len(a.labels), "fixes", len(a.fixes), "names", len(names))


if __name__ == "__main__":
    run()
