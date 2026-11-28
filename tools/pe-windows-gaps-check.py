#!/usr/bin/env python3
from pathlib import Path
import sys

ROOT = Path(__file__).resolve().parents[1]
R4 = (ROOT / "src" / "rt-net-r4-blob.txt").read_text().strip()
R4B = bytes.fromhex(R4)
HOSTOK = bytes.fromhex("554889e54881ec880000005348894df8")
HOSTOK_OLD = bytes.fromhex("554889e54881ec800000005348894df8")
NS_ALIGN = bytes.fromhex("554889e54881ec8800000053488b05")
NS_MISALIGN = bytes.fromhex("554889e54881ec8000000053488b05")
SHARE7 = bytes.fromhex("41b807000000")
BAD_PARSE = bytes.fromhex("4801c848894108")
GOOD_MAP = bytes.fromhex("4c8b024c01c148894808")
JSONB = bytes.fromhex((ROOT / "src" / "rt-net-json-blob.txt").read_text().strip())
RTNET = (ROOT / "src" / "rt-net.vire").read_text()
RTDNS = (ROOT / "src" / "rt-dns.vire").read_text()


def fail_before(msg):
    print("FAIL_BEFORE", msg)
    sys.exit(2)


def main():
    print("head_check pe-windows-gaps")
    print("caps arena 33554432 list 100000 steps 5000000 itemCap 1000000")
    if "33554432" not in (ROOT / "src" / "rt.vire").read_text():
        sys.exit("arena cap changed")
    packed_hostok_saves_rbx = R4B.find(HOSTOK) >= 0
    packed_hostok_misalign = R4B.find(HOSTOK_OLD) >= 0 or R4B.find(NS_MISALIGN) >= 0
    if (not packed_hostok_saves_rbx) and R4B.find(HOSTOK_OLD) < 0:
        sys.exit("r4 missing dns_hostok prologue")
    before = 0x53 if packed_hostok_saves_rbx else 0
    packed_share7 = SHARE7 in R4B
    source_saves_rbx = "Preserve rbx: octet index is ebx" in RTDNS
    source_share7 = "65, 184, 7, 0, 0, 0" in RTDNS
    uses_r4_for_resolve = "(route_nparams == 4) or (route_nparams == 0)" in RTNET
    emit_unpacked_on_zero = "emitDnsRuntime" in RTNET and "route_nparams == 0" in RTNET
    print("r4_hostok_push_rbx", packed_hostok_saves_rbx, "byte_before", hex(before))
    print("r4_hostok_win64_align", packed_hostok_saves_rbx and R4B.find(NS_ALIGN) >= 0 and not packed_hostok_misalign)
    print("r4_file_share_7", packed_share7)
    print("src_rt_dns_rbx", source_saves_rbx, "src_share7", source_share7)
    print("emit_uses_stale_r4_for_resolve", uses_r4_for_resolve)
    print("emit_unpacked_dns_on_route0", emit_unpacked_on_zero)
    print("json_bad_add_rcx", BAD_PARSE in JSONB, "json_good_map", GOOD_MAP in JSONB)

    dns_stale = (not packed_hostok_saves_rbx) or packed_hostok_misalign or (not packed_share7)
    json_bad = (not JSONB.startswith(bytes.fromhex("488b4df8"))) or BAD_PARSE in JSONB or GOOD_MAP not in JSONB
    if dns_stale or json_bad:
        fail_before(
            "packed PE DNS still r4 without rbx/share7 or json blob still the 6e969fc2 calling convention"
        )

    print("PASS_AFTER packed DNS/json shape")
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main())
    except SystemExit:
        raise
    except Exception as exc:
        print("harness", exc)
        sys.exit(1)
