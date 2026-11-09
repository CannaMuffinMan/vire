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
    UC_X86_REG_R12,
)

STUB_BASE = 0x700000000
STACK_BASE = 0x600000000
STACK_SIZE = 0x200000
HEAP_BASE = 0x200000000
ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))


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
    def __init__(self, pe_path, cwd=None):
        self.raw, self.image, self.image_size, self.entry, self.headers, self.sections = load_pe(pe_path)
        self.cwd = cwd or ROOT
        self.mu = Uc(UC_ARCH_X86, UC_MODE_64)
        self.out = bytearray()
        self.exit_code = None
        self.heap = None
        self.heap_size = None
        self.faults = []
        self.files = {}
        self.next_handle = 3
        self.insns = 0
        self._map(self.image, max(self.image_size, 0x1000))
        self.mu.mem_write(self.image, self.raw[: self.headers])
        for va, rs, rp in self.sections:
            self.mu.mem_write(self.image + va, self.raw[rp : rp + rs])
        self._map(STACK_BASE, STACK_SIZE)
        self._map(STUB_BASE, 0x1000)
        names = [
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
        ]
        self.stubs = {}
        for i, name in enumerate(names):
            addr = STUB_BASE + i * 16
            self.mu.mem_write(addr, b"\xc3")
            self.stubs[addr] = getattr(self, "api_" + name)
        self._patch_iat()
        cmdline = (sys.argv[2] + "\0").encode("ascii") if len(sys.argv) > 2 else b"\0"
        self._map(0x500000000, 0x1000)
        self.mu.mem_write(0x500000000, cmdline)
        rsp = STACK_BASE + STACK_SIZE - 0x1000
        rsp -= rsp % 16
        rsp -= 8
        self.mu.reg_write(UC_X86_REG_RSP, rsp)
        self.mu.hook_add(UC_HOOK_CODE, self.on_code)
        self.mu.hook_add(UC_HOOK_MEM_UNMAPPED, self.on_unmapped)

    def _map(self, addr, size):
        size = (size + 0xFFF) & ~0xFFF
        self.mu.mem_map(addr, size)

    def _patch_iat(self):
        base = self.image + 0x1000
        blob = self.mu.mem_read(base, 0x400)
        qwords = []
        for i in range(0, 0x400, 8):
            q = struct.unpack_from("<Q", blob, i)[0]
            qwords.append((i, q))
        runs = []
        cur = []
        for i, q in qwords:
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
        names = [
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
        ]
        iat = runs[-1]
        if len(iat) < len(names):
            raise SystemExit("IAT has %d slots, need %d" % (len(iat), len(names)))
        iat = iat[: len(names)]
        for slot, name in zip(iat, names):
            addr = STUB_BASE + names.index(name) * 16
            self.mu.mem_write(base + slot, struct.pack("<Q", addr))

    def rd(self, reg):
        return self.mu.reg_read(reg)

    def wr(self, reg, val):
        self.mu.reg_write(reg, val & 0xFFFFFFFFFFFFFFFF)

    def cstr(self, addr):
        buf = bytearray()
        while True:
            b = self.mu.mem_read(addr, 1)[0]
            if b == 0:
                break
            buf.append(b)
            addr += 1
            if len(buf) > 1000000:
                break
        return bytes(buf)

    def on_code(self, uc, address, size, user):
        self.insns += 1
        fn = self.stubs.get(address)
        if fn:
            fn()

    def on_unmapped(self, uc, access, address, size, value, user):
        self.faults.append((access, address, size, self.rd(UC_X86_REG_RIP)))
        uc.emu_stop()
        return False

    def api_GetStdHandle(self):
        self.wr(UC_X86_REG_RAX, 1)

    def api_GetCommandLineA(self):
        self.wr(UC_X86_REG_RAX, 0x500000000)

    def api_VirtualAlloc(self):
        size = self.rd(UC_X86_REG_RDX)
        self.heap_size = size
        self.heap = HEAP_BASE
        self._map(HEAP_BASE, size)
        self.wr(UC_X86_REG_RAX, HEAP_BASE)

    def api_ExitProcess(self):
        self.exit_code = self.rd(UC_X86_REG_RCX) & 0xFFFFFFFF
        self.mu.emu_stop()

    def api_WriteFile(self):
        buf = self.rd(UC_X86_REG_RDX)
        n = self.rd(UC_X86_REG_R8) & 0xFFFFFFFF
        written = self.rd(UC_X86_REG_R9)
        data = bytes(self.mu.mem_read(buf, n)) if n else b""
        self.out += data
        if written:
            self.mu.mem_write(written, struct.pack("<I", n))
        self.wr(UC_X86_REG_RAX, 1)

    def api_CreateFileA(self):
        name = self.cstr(self.rd(UC_X86_REG_RCX)).decode("latin1")
        path = os.path.normpath(os.path.join(self.cwd, name))
        try:
            fh = open(path, "rb")
        except OSError:
            self.wr(UC_X86_REG_RAX, 0xFFFFFFFFFFFFFFFF)
            return
        handle = self.next_handle
        self.next_handle += 1
        self.files[handle] = fh
        self.wr(UC_X86_REG_RAX, handle)

    def api_GetFileSize(self):
        handle = self.rd(UC_X86_REG_RCX)
        fh = self.files.get(handle)
        if fh is None:
            self.wr(UC_X86_REG_RAX, 0xFFFFFFFF)
            return
        fh.seek(0, os.SEEK_END)
        n = fh.tell()
        fh.seek(0)
        self.wr(UC_X86_REG_RAX, n & 0xFFFFFFFF)

    def api_ReadFile(self):
        handle = self.rd(UC_X86_REG_RCX)
        buf = self.rd(UC_X86_REG_RDX)
        n = self.rd(UC_X86_REG_R8) & 0xFFFFFFFF
        got_ptr = self.rd(UC_X86_REG_R9)
        fh = self.files.get(handle)
        if fh is None:
            self.wr(UC_X86_REG_RAX, 0)
            return
        data = fh.read(n)
        if data:
            off = 0
            while off < len(data):
                chunk = data[off : off + 4096]
                try:
                    self.mu.mem_write(buf + off, chunk)
                except Exception as exc:
                    self.faults.append(("write", buf + off, len(chunk), str(exc)))
                    self.mu.emu_stop()
                    return
                off += 4096
        if got_ptr:
            self.mu.mem_write(got_ptr, struct.pack("<I", len(data)))
        self.wr(UC_X86_REG_RAX, 1)

    def api_CloseHandle(self):
        handle = self.rd(UC_X86_REG_RCX)
        fh = self.files.pop(handle, None)
        if fh:
            fh.close()
        self.wr(UC_X86_REG_RAX, 1)

    def api_GetFileAttributesA(self):
        self.wr(UC_X86_REG_RAX, 0xFFFFFFFF)

    def api_GetFileInformationByHandle(self):
        self.wr(UC_X86_REG_RAX, 0)

    def api_SetUnhandledExceptionFilter(self):
        self.wr(UC_X86_REG_RAX, 0)

    def run(self, count=200000000):
        start = self.image + self.entry
        try:
            self.mu.emu_start(start, 0, timeout=0, count=count)
        except Exception as exc:
            self.faults.append(("exc", str(exc), self.rd(UC_X86_REG_RIP)))
        return self


def main():
    emu = Emu(sys.argv[1])
    emu.run()
    bump = emu.rd(UC_X86_REG_R12)
    used = (bump - HEAP_BASE) if emu.heap else 0
    sys.stdout.buffer.write(b"EXIT " + str(emu.exit_code).encode() + b"\n")
    sys.stdout.buffer.write(b"HEAP_SIZE " + hex(emu.heap_size or 0).encode() + b"\n")
    sys.stdout.buffer.write(b"HEAP_BUMP " + hex(used).encode() + b"\n")
    sys.stdout.buffer.write(b"FAULTS " + repr(emu.faults).encode() + b"\n")
    sys.stdout.buffer.write(b"STDOUT_BEGIN\n")
    sys.stdout.buffer.write(bytes(emu.out))
    sys.stdout.buffer.write(b"STDOUT_END\n")
    if emu.exit_code != 0 or emu.faults:
        sys.exit(1)


if __name__ == "__main__":
    main()
