#!/usr/bin/env python3
import os
import struct
import sys
from unicorn import Uc, UC_ARCH_X86, UC_MODE_64, UC_HOOK_CODE, UC_HOOK_MEM_UNMAPPED
from unicorn.x86_const import (
    UC_X86_REG_RAX,
    UC_X86_REG_RCX,
    UC_X86_REG_RDX,
    UC_X86_REG_R8,
    UC_X86_REG_R9,
    UC_X86_REG_RIP,
    UC_X86_REG_RSP,
)

STUB_BASE = 0x700000000
STACK_BASE = 0x600000000
STACK_SIZE = 0x200000
HEAP_BASE = 0x200000000
NAMES = [
    "GetStdHandle",
    "WriteFile",
    "ExitProcess",
    "VirtualAlloc",
    "CreateFileA",
    "ReadFile",
    "GetFileSize",
    "CloseHandle",
    "GetCommandLineA",
    "GetFileAttributesA",
    "GetFileInformationByHandle",
    "SetUnhandledExceptionFilter",
    "AddVectoredExceptionHandler",
    "SetFilePointerEx",
    "SetEndOfFile",
]


def load_pe(path):
    raw = open(path, "rb").read()
    if path.endswith(".hex") or raw[:2] != b"MZ":
        raw = bytes.fromhex(raw.decode().strip())
    e = struct.unpack_from("<I", raw, 0x3C)[0]
    oh = e + 24
    entry = struct.unpack_from("<I", raw, oh + 16)[0]
    image = struct.unpack_from("<Q", raw, oh + 24)[0]
    size = struct.unpack_from("<I", raw, oh + 56)[0]
    headers = struct.unpack_from("<I", raw, oh + 60)[0]
    nsec = struct.unpack_from("<H", raw, e + 6)[0]
    soh = struct.unpack_from("<H", raw, e + 20)[0]
    sections = []
    for i in range(nsec):
        off = oh + soh + i * 40
        va, rs, rp = struct.unpack_from("<III", raw, off + 12)
        sections.append((va, rs, rp))
    return raw, image, size, entry, headers, sections


class Emu:
    def __init__(self, pe_path, cwd, reparse_names=None, force_nlink=None):
        self.raw, self.image, self.image_size, self.entry, self.headers, self.sections = load_pe(pe_path)
        self.cwd = cwd
        self.reparse_names = set(reparse_names or [])
        self.force_nlink = force_nlink
        self.mu = Uc(UC_ARCH_X86, UC_MODE_64)
        self.out = bytearray()
        self.exit_code = None
        self.heap_size = None
        self.faults = []
        self.files = {}
        self.next_handle = 3
        self.gfa = []
        self.creates = []
        self._map(self.image, max(self.image_size, 0x1000))
        self.mu.mem_write(self.image, self.raw[: self.headers])
        for va, rs, rp in self.sections:
            self.mu.mem_write(self.image + va, self.raw[rp : rp + rs])
        self._map(STACK_BASE, STACK_SIZE)
        self._map(STUB_BASE, 0x1000)
        self.stubs = {}
        for i, name in enumerate(NAMES):
            addr = STUB_BASE + i * 16
            self.mu.mem_write(addr, b"\xc3")
            self.stubs[addr] = getattr(self, "api_" + name)
        self._patch_iat()
        self._map(0x500000000, 0x1000)
        self.mu.mem_write(0x500000000, b"\0")
        rsp = STACK_BASE + STACK_SIZE - 0x1000
        rsp -= rsp % 16
        rsp -= 8
        self.mu.reg_write(UC_X86_REG_RSP, rsp)
        self.mu.hook_add(UC_HOOK_CODE, self.on_code)
        self.mu.hook_add(UC_HOOK_MEM_UNMAPPED, self.on_unmapped)

    def _map(self, addr, size):
        size = (size + 0xFFF) & ~0xFFF
        try:
            self.mu.mem_map(addr, size)
        except Exception:
            pass

    def _patch_iat(self):
        base = self.image + 0x1000
        blob = self.mu.mem_read(base, 0x400)
        cur = []
        runs = []
        for i in range(0, 0x400, 8):
            q = struct.unpack_from("<Q", blob, i)[0]
            if q and q < 0x100000:
                cur.append(i)
            else:
                if len(cur) >= 9:
                    runs.append(cur)
                cur = []
        if len(cur) >= 9:
            runs.append(cur)
        if not runs:
            raise SystemExit("IAT not found")
        iat = runs[-1]
        if len(iat) < len(NAMES):
            raise SystemExit("IAT has %d slots, need %d" % (len(iat), len(NAMES)))
        for slot, name in zip(iat, NAMES):
            self.mu.mem_write(base + slot, struct.pack("<Q", STUB_BASE + NAMES.index(name) * 16))

    def rd(self, reg):
        return self.mu.reg_read(reg) & 0xFFFFFFFFFFFFFFFF

    def wr(self, reg, val):
        self.mu.reg_write(reg, val & 0xFFFFFFFFFFFFFFFF)

    def cstr(self, addr):
        buf = bytearray()
        for _ in range(4096):
            b = self.mu.mem_read(addr, 1)[0]
            if b == 0:
                break
            buf.append(b)
            addr += 1
        return bytes(buf)

    def on_code(self, uc, address, size, user):
        fn = self.stubs.get(address)
        if fn:
            fn()

    def on_unmapped(self, uc, access, address, size, value, user):
        self.faults.append((access, address, size, self.rd(UC_X86_REG_RIP)))
        uc.emu_stop()
        return False

    def api_GetStdHandle(self):
        n = self.rd(UC_X86_REG_RCX) & 0xFFFFFFFF
        if n == 0xFFFFFFF4:
            self.wr(UC_X86_REG_RAX, 2)
        else:
            self.wr(UC_X86_REG_RAX, 1)

    def api_GetCommandLineA(self):
        self.wr(UC_X86_REG_RAX, 0x500000000)

    def api_VirtualAlloc(self):
        size = self.rd(UC_X86_REG_RDX)
        self.heap_size = size
        self._map(HEAP_BASE, size)
        self.wr(UC_X86_REG_RAX, HEAP_BASE)

    def api_ExitProcess(self):
        self.exit_code = self.rd(UC_X86_REG_RCX) & 0xFFFFFFFF
        self.mu.emu_stop()

    def api_WriteFile(self):
        buf = self.rd(UC_X86_REG_RDX)
        n = self.rd(UC_X86_REG_R8) & 0xFFFFFFFF
        data = bytes(self.mu.mem_read(buf, n)) if n else b""
        handle = self.rd(UC_X86_REG_RCX)
        rec = self.files.get(handle)
        if rec is not None:
            rec[b"data"] = data
            path = rec[b"path"]
            if path:
                full = os.path.join(self.cwd, path.decode("latin1"))
                os.makedirs(os.path.dirname(full), exist_ok=True)
                with open(full, "wb") as f:
                    f.write(data)
        elif handle != 2:
            self.out += data
        written = self.rd(UC_X86_REG_R9)
        if written:
            self.mu.mem_write(written, struct.pack("<I", n))
        self.wr(UC_X86_REG_RAX, 1)

    def api_CreateFileA(self):
        path = self.cstr(self.rd(UC_X86_REG_RCX))
        access = self.rd(UC_X86_REG_RDX) & 0xFFFFFFFF
        disp = struct.unpack_from("<I", self.mu.mem_read(self.rd(UC_X86_REG_RSP) + 0x28, 4))[0]
        flags = struct.unpack_from("<I", self.mu.mem_read(self.rd(UC_X86_REG_RSP) + 0x30, 4))[0]
        rel = path.decode("latin1")
        full = os.path.join(self.cwd, rel)
        self.creates.append((rel, access, disp, flags))
        exists = os.path.exists(full)
        if disp == 3 and not exists:
            self.wr(UC_X86_REG_RAX, 0xFFFFFFFFFFFFFFFF)
            return
        if disp == 1 and exists:
            self.wr(UC_X86_REG_RAX, 0xFFFFFFFFFFFFFFFF)
            return
        if disp == 2:
            os.makedirs(os.path.dirname(full), exist_ok=True)
            open(full, "wb").close()
        handle = self.next_handle
        self.next_handle += 1
        nlink = os.stat(full).st_nlink if exists or os.path.exists(full) else 1
        if self.force_nlink is not None and os.path.exists(full):
            nlink = self.force_nlink
        data = b""
        if os.path.exists(full):
            with open(full, "rb") as f:
                data = f.read()
        self.files[handle] = {b"path": path, b"data": data, b"nlink": nlink}
        self.wr(UC_X86_REG_RAX, handle)

    def api_ReadFile(self):
        handle = self.rd(UC_X86_REG_RCX)
        buf = self.rd(UC_X86_REG_RDX)
        n = self.rd(UC_X86_REG_R8) & 0xFFFFFFFF
        rec = self.files.get(handle)
        data = rec[b"data"][:n] if rec else b""
        if data:
            self.mu.mem_write(buf, data)
        written = self.rd(UC_X86_REG_R9)
        if written:
            self.mu.mem_write(written, struct.pack("<I", len(data)))
        self.wr(UC_X86_REG_RAX, 1)

    def api_GetFileSize(self):
        rec = self.files.get(self.rd(UC_X86_REG_RCX))
        self.wr(UC_X86_REG_RAX, len(rec[b"data"]) if rec else 0xFFFFFFFF)

    def api_CloseHandle(self):
        self.wr(UC_X86_REG_RAX, 1)

    def api_GetFileAttributesA(self):
        path = self.cstr(self.rd(UC_X86_REG_RCX)).decode("latin1")
        full = os.path.join(self.cwd, path)
        if path in self.reparse_names or path.rstrip("/") in self.reparse_names:
            self.gfa.append((path, 0x420))
            self.wr(UC_X86_REG_RAX, 0x420)
            return
        if os.path.lexists(full) and os.path.islink(full):
            attr = 0x400
            if os.path.isdir(full):
                attr |= 0x10
            else:
                attr |= 0x20
            self.gfa.append((path, attr))
            self.wr(UC_X86_REG_RAX, attr)
            return
        if not os.path.exists(full):
            self.gfa.append((path, 0xFFFFFFFF))
            self.wr(UC_X86_REG_RAX, 0xFFFFFFFF)
            return
        attr = 0x20
        if os.path.isdir(full):
            attr = 0x10
        self.gfa.append((path, attr))
        self.wr(UC_X86_REG_RAX, attr)

    def api_GetFileInformationByHandle(self):
        rec = self.files.get(self.rd(UC_X86_REG_RCX))
        info = self.rd(UC_X86_REG_RDX)
        buf = bytearray(52)
        nlink = rec[b"nlink"] if rec else 1
        struct.pack_into("<I", buf, 0, 0x20)
        struct.pack_into("<I", buf, 40, nlink)
        self.mu.mem_write(info, bytes(buf))
        self.wr(UC_X86_REG_RAX, 1)

    def api_SetUnhandledExceptionFilter(self):
        self.wr(UC_X86_REG_RAX, 0)

    def api_AddVectoredExceptionHandler(self):
        self.wr(UC_X86_REG_RAX, 1)

    def api_SetFilePointerEx(self):
        self.wr(UC_X86_REG_RAX, 1)

    def api_SetEndOfFile(self):
        rec = self.files.get(self.rd(UC_X86_REG_RCX))
        if rec is not None:
            rec[b"data"] = b""
            path = rec[b"path"]
            if path:
                full = os.path.join(self.cwd, path.decode("latin1"))
                if os.path.exists(full):
                    open(full, "wb").close()
        self.wr(UC_X86_REG_RAX, 1)

    def run(self):
        self.mu.emu_start(self.image + self.entry, 0, timeout=8_000_000, count=5_000_000)
        return self.exit_code, bytes(self.out), self.gfa, self.creates, self.faults, self.heap_size


def main():
    pe, cwd = sys.argv[1], sys.argv[2]
    mode = sys.argv[3] if len(sys.argv) > 3 else "plain"
    reparse = ["data"] if mode == "reparse-parent" else []
    nlink = 2 if mode == "nlink2" else None
    emu = Emu(pe, cwd, reparse_names=reparse, force_nlink=nlink)
    code, out, gfa, creates, faults, heap = emu.run()
    print("EXIT", code)
    print("STDOUT", out)
    print("HEAP_SIZE", hex(heap or 0))
    print("GFA", gfa)
    print("CREATE", creates)
    print("FAULTS", faults)
    if faults:
        sys.exit(2)


if __name__ == "__main__":
    main()
