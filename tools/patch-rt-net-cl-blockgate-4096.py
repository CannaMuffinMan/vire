#!/usr/bin/env python3
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SRC = ROOT / "src"
OLD = bytes.fromhex("00010000")
NEW = bytes.fromhex("00100000")
MOV_R8D = bytes.fromhex("41b8")
CMP_R8 = bytes.fromhex("4981f8")


def parse_u16(s, i):
    return int(s[i : i + 2], 16) + int(s[i + 2 : i + 4], 16) * 256


def parse_u32(s, i):
    return parse_u16(s, i) + parse_u16(s, i + 4) * 65536


def names_of(marker):
    text = (SRC / "rt-net.vire").read_text()
    i = text.find(marker)
    start = text.find("return [", i)
    end = text.find("]", start)
    inner = text[start + 8 : end]
    return [x.strip().strip('"') for x in inner.split(",") if x.strip()]


def pin_off(pins_raw, names, want):
    i = 0
    while i + 11 < len(pins_raw):
        off = parse_u32(pins_raw, i)
        idn = parse_u16(pins_raw, i + 8)
        if names[idn] == want:
            return off
        i += 12
    raise SystemExit("missing pin " + want)


def patch_blob(blob_name, pins_name, names):
    blob = bytearray(bytes.fromhex((SRC / blob_name).read_text().strip()))
    pins_raw = (SRC / pins_name).read_text().strip()
    gate = pin_off(pins_raw, names, "cl_blockgate")
    hits = []
    i = gate
    while i + 7 <= len(blob):
        if blob[i : i + 2] == MOV_R8D and blob[i + 2 : i + 6] == OLD:
            blob[i + 2 : i + 6] = NEW
            hits.append((i, "mov r8d"))
            i += 6
            continue
        if blob[i : i + 3] == CMP_R8 and blob[i + 3 : i + 7] == OLD:
            blob[i + 3 : i + 7] = NEW
            hits.append((i, "cmp r8"))
            i += 7
            continue
        i += 1
    (SRC / blob_name).write_text(blob.hex() + "\n")
    mov_n = blob[gate:].count(MOV_R8D + NEW)
    cmp_n = blob[gate:].count(CMP_R8 + NEW)
    old_n = blob[gate:].count(MOV_R8D + OLD) + blob[gate:].count(CMP_R8 + OLD)
    print(blob_name, "gate", hex(gate), "rewrites", len(hits), "mov4096", mov_n, "cmp4096", cmp_n)
    for off, kind in hits:
        print(" ", kind, hex(off))
    if mov_n != 8 or cmp_n != 2 or old_n != 0:
        raise SystemExit("gate cap rewrite incomplete")
    return hits


def main():
    n3 = names_of("define netNames\n")
    n4 = names_of("define netNamesR4")
    patch_blob("rt-net-blob.txt", "rt-net-pins.txt", n3)
    patch_blob("rt-net-r4-blob.txt", "rt-net-r4-pins.txt", n4)


if __name__ == "__main__":
    main()
