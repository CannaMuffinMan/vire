#!/usr/bin/env python3
"""Remainder chain cases vs recorded api/fcgcpa.vire contracts (not prod)."""
import hashlib
import json
import os
import shutil
import socket
import sys
import threading
from pathlib import Path

KEYS = ["content-type", "connection", "x-content-type-options", "cache-control"]
HDR = {
    "content-type": "application/json",
    "connection": "close",
    "x-content-type-options": "nosniff",
    "cache-control": "no-store",
}


def proof_of(index, previous, text):
    row = "[" + str(index) + "," + json.dumps(previous, ensure_ascii=False) + "," + json.dumps(text, ensure_ascii=False) + "]"
    return hashlib.sha256(row.encode("utf-8")).hexdigest()


def http_req(port, method, path, body_send, timeout=30):
    # Split header/body writes: packed 3-param listen WS peeks the first recv
    # into ws_hbuf. A single sendall of POST headers+body leaves the body in
    # that peek, so rt_net_client then 408s waiting on the socket. Host
    # VireListen does not peek. Do not change /ws/refuse.
    payload = body_send.encode("utf-8") if body_send is not None else b""
    lines = ["%s %s HTTP/1.1" % (method, path), "Host: 127.0.0.1", "Connection: close"]
    if method == "POST":
        lines.append("Content-Type: application/json")
        lines.append("Content-Length: %d" % len(payload))
    head = ("\r\n".join(lines) + "\r\n\r\n").encode("ascii")
    s = socket.create_connection(("127.0.0.1", port), timeout)
    s.setsockopt(socket.IPPROTO_TCP, socket.TCP_NODELAY, 1)
    s.sendall(head)
    if payload:
        s.sendall(payload)
    s.settimeout(timeout)
    chunks = []
    raw = b""
    try:
        while True:
            data = s.recv(65536)
            if not data:
                break
            chunks.append(data)
            raw = b"".join(chunks)
            split = raw.find(b"\r\n\r\n")
            if split >= 0:
                headers_blob = raw[:split]
                body = raw[split + 4 :]
                clen = None
                for line in headers_blob.split(b"\r\n")[1:]:
                    if line.lower().startswith(b"content-length:"):
                        clen = int(line.split(b":", 1)[1].strip())
                        break
                if clen is not None and len(body) >= clen:
                    break
    except socket.timeout:
        raw = b"".join(chunks)
    s.close()
    split = raw.find(b"\r\n\r\n")
    if split < 0:
        raise OSError("missing header terminator")
    head = raw[:split].decode("ascii", "replace")
    body = raw[split + 4 :].decode("utf-8")
    lines = head.split("\r\n")
    status = int(lines[0].split(" ")[1])
    headers = {}
    for line in lines[1:]:
        if ":" not in line:
            continue
        k, v = line.split(":", 1)
        headers[k.strip().lower()] = v.strip()
    if "content-length" in headers:
        n = int(headers["content-length"])
        body = body.encode("utf-8")[:n].decode("utf-8")
    return status, headers, body


def restore_genesis(fix_src, fix_dst):
    if fix_dst.exists():
        shutil.rmtree(fix_dst)
    fix_dst.mkdir(parents=True)
    for name in ("head.json", "000001.json", "blocks.json"):
        src = fix_src / name
        if src.exists():
            shutil.copyfile(src, fix_dst / name)
    old = Path("data/chain.json")
    if old.exists():
        old.unlink()


def write_seg(dir_path, n, link, blocks):
    path = dir_path / ("%06d.json" % n)
    path.write_text(json.dumps({"link": link, "blocks": blocks}, separators=(",", ":"), ensure_ascii=False), encoding="utf-8")
    return path


def write_head(dir_path, segment, index, proof):
    (dir_path / "head.json").write_text(
        json.dumps({"segment": segment, "index": index, "proof": proof}, separators=(",", ":"), ensure_ascii=False),
        encoding="utf-8",
    )


def block_obj(index, previous, text):
    return {"index": index, "previous": previous, "proof": proof_of(index, previous, text), "text": text}


def extra_len(index, previous, text):
    return len(json.dumps(block_obj(index, previous, text), separators=(",", ":"), ensure_ascii=False))


def build_near_rotate(dir_path):
    """Fill segment 1 until one 4000-char post would rotate (host +2 rule)."""
    genesis = block_obj(0, "0", "")
    blocks = [genesis]
    previous = genesis["proof"]
    index = 1
    chunk = "a" * 4000
    link = "0"
    while True:
        extra = extra_len(index, previous, chunk)
        raw = json.dumps({"link": link, "blocks": blocks}, separators=(",", ":"), ensure_ascii=False)
        if len(raw) + extra + 2 > 524288:
            break
        b = block_obj(index, previous, chunk)
        blocks.append(b)
        previous = b["proof"]
        index += 1
    write_seg(dir_path, 1, link, blocks)
    write_head(dir_path, 1, blocks[-1]["index"], blocks[-1]["proof"])
    return blocks[-1], chunk


def build_full_64(dir_path):
    previous = "0"
    index = 0
    for seg in range(1, 65):
        link = previous
        blocks = []
        if seg < 64:
            b = block_obj(index, previous, "s" + str(seg))
            blocks.append(b)
            previous = b["proof"]
            index += 1
        else:
            while True:
                text = "z" * 4000
                extra = extra_len(index, previous, text)
                raw = json.dumps({"link": link, "blocks": blocks}, separators=(",", ":"), ensure_ascii=False)
                if blocks and len(raw) + extra + 2 > 524288:
                    break
                b = block_obj(index, previous, text)
                blocks.append(b)
                previous = b["proof"]
                index += 1
                raw2 = json.dumps({"link": link, "blocks": blocks}, separators=(",", ":"), ensure_ascii=False)
                if len(raw2) >= 524288:
                    break
        write_seg(dir_path, seg, link, blocks)
    write_head(dir_path, 64, index - 1, previous)


def check_headers(headers, name, mismatches):
    for k, v in HDR.items():
        g = headers.get(k, "")
        if g.lower() != v.lower():
            mismatches.append("%s header %s got %s want %s" % (name, k, g, v))


def run_remainder(port, fix_src, fix_dst, mode):
    mismatches = []
    port = int(port)

    # tamper 503
    restore_genesis(fix_src, fix_dst)
    st, hd, body = http_req(port, "POST", "/block", "{\"text\":\"keep\"}")
    seg = fix_dst / "000001.json"
    raw = seg.read_text(encoding="utf-8") if seg.exists() else ""
    if mode != "fail-before":
        if st != 200:
            mismatches.append("tamper setup post got %s %s" % (st, body))
        if "keep" not in raw:
            mismatches.append("tamper setup missing keep in segment")
        else:
            seg.write_text(raw.replace("keep", "tamper"), encoding="utf-8")
    elif "keep" in raw:
        seg.write_text(raw.replace("keep", "tamper"), encoding="utf-8")
    else:
        if seg.exists():
            seg.write_text(raw.replace("\"text\":\"\"", "\"text\":\"tamper\"", 1), encoding="utf-8")
    st, hd, body = http_req(port, "POST", "/block", "{\"text\":\"more\"}")
    want = "{\"ok\":false,\"status\":503,\"error\":\"chain invalid\"}"
    if mode == "fail-before":
        if st == 503 and body == want:
            mismatches.append("FAIL_BEFORE tamper unexpectedly matched 503")
    else:
        if st != 503 or body != want:
            mismatches.append("post_block_tamper_503 got %s %s" % (st, body))
        check_headers(hd, "post_block_tamper_503", mismatches)
        st2, hd2, body2 = http_req(port, "GET", "/chain", None)
        if st2 != 503 or body2 != want:
            mismatches.append("get_chain_tamper_503 got %s %s" % (st2, body2))
        check_headers(hd2, "get_chain_tamper_503", mismatches)
    print("case tamper POST status %s body %s" % (st, body))

    # previousHash / hash aliases (recorded in fcg-chain.json; beyond previous/proof).
    restore_genesis(fix_src, fix_dst)
    genesis = "a9df21e6e7672bdb9cea28047aa39ba0fa96d54ae0791a9bab30078f5a2d4fad"
    st, hd, body = http_req(port, "POST", "/block", '{"text":"x","previousHash":"not-the-tip"}')
    want_prev = '{"ok":false,"status":400,"error":"previous does not match"}'
    if mode == "fail-before":
        if st == 400 and body == want_prev:
            mismatches.append("FAIL_BEFORE previousHash mismatch unexpectedly 400")
    else:
        if st != 400 or body != want_prev:
            mismatches.append("post_block_previousHash_mismatch got %s %s" % (st, body))
        check_headers(hd, "post_block_previousHash_mismatch", mismatches)
    print("case previousHash mismatch status %s body %s" % (st, body))
    restore_genesis(fix_src, fix_dst)
    st, hd, body = http_req(port, "POST", "/block", '{"text":"x","hash":"deadbeef"}')
    want_hash = '{"ok":false,"status":400,"error":"proof does not match"}'
    if mode == "fail-before":
        if st == 400 and body == want_hash:
            mismatches.append("FAIL_BEFORE hash alias mismatch unexpectedly 400")
    else:
        if st != 400 or body != want_hash:
            mismatches.append("post_block_hash_alias_mismatch got %s %s" % (st, body))
        check_headers(hd, "post_block_hash_alias_mismatch", mismatches)
    print("case hash alias mismatch status %s body %s" % (st, body))
    restore_genesis(fix_src, fix_dst)
    st, hd, body = http_req(
        port,
        "POST",
        "/block",
        '{"text":"fixture-one","previousHash":"%s"}' % genesis,
    )
    want_ok = '{"ok":true,"accepted":true,"index":1,"proof":"52d7f3a9d3dfa0458a20ff820cab94c1df2acea128dacd450a6e45456c27f561"}'
    if mode != "fail-before":
        if st != 200 or body != want_ok:
            mismatches.append("post_block_previousHash_ok got %s %s" % (st, body))
        check_headers(hd, "post_block_previousHash_ok", mismatches)
    print("case previousHash ok status %s body %s" % (st, body))

    # 507 before rotate so native arena is not still holding a 512 KB segment.
    if mode != "fail-before":
        restore_genesis(fix_src, fix_dst)
        build_full_64(fix_dst)
        overflow = "z" * 4000
        st, hd, body = http_req(port, "POST", "/block", json.dumps({"text": overflow}, separators=(",", ":")))
        want507 = "{\"ok\":false,\"status\":507,\"error\":\"chain full\"}"
        if st != 507 or body != want507:
            mismatches.append("post_block_full_507 got %s %s" % (st, body))
        check_headers(hd, "post_block_full_507", mismatches)
        print("case 507 status %s body %s" % (st, body))

    # previousHash already in static contract; rotate
    restore_genesis(fix_src, fix_dst)
    last, chunk = build_near_rotate(fix_dst)
    st, hd, body = http_req(port, "POST", "/block", json.dumps({"text": chunk}, separators=(",", ":")))
    if mode == "fail-before":
        if (fix_dst / "000002.json").exists() and st == 200:
            mismatches.append("FAIL_BEFORE rotate unexpectedly created 000002.json")
    else:
        if st != 200:
            mismatches.append("post_block_rotate_512k status %s %s" % (st, body))
        if not (fix_dst / "000002.json").exists():
            mismatches.append("post_block_rotate_512k missing 000002.json")
        for p in fix_dst.glob("*.json"):
            if p.name == "head.json" or p.name == "blocks.json":
                continue
            n = p.stat().st_size
            if n > 524288:
                mismatches.append("%s is %s" % (p.name, n))
        want_index = last["index"] + 1
        want_proof = proof_of(want_index, last["proof"], chunk)
        want_body = "{\"ok\":true,\"accepted\":true,\"index\":%d,\"proof\":%s}" % (
            want_index,
            json.dumps(want_proof),
        )
        if body != want_body:
            mismatches.append("post_block_rotate_512k body got %s want %s" % (body, want_body))
        check_headers(hd, "post_block_rotate_512k", mismatches)
    print("case rotate status %s body %s" % (st, body[:120]))

    if mode == "fail-before":
        if mismatches:
            print("REMAINDER_FAIL_BEFORE_UNEXPECTED")
            for m in mismatches:
                print(m)
            return 4
        print("REMAINDER_FAIL_BEFORE_MISMATCH")
        return 2

    # migrate
    if fix_dst.exists():
        shutil.rmtree(fix_dst)
    fix_dst.mkdir(parents=True)
    old = [
        {"index": 0, "previousHash": "0", "text": ""},
        {"index": 1, "previousHash": proof_of(0, "0", ""), "text": "migrated"},
    ]
    Path("data").mkdir(exist_ok=True)
    Path("data/chain.json").write_text(json.dumps(old, separators=(",", ":")), encoding="utf-8")
    st, hd, body = http_req(port, "GET", "/chain", None)
    b0 = block_obj(0, "0", "")
    b1 = block_obj(1, b0["proof"], "migrated")
    want_mig = json.dumps([b0, b1], separators=(",", ":"), ensure_ascii=False)
    if mode == "fail-before":
        if st == 200 and body == want_mig:
            mismatches.append("FAIL_BEFORE migrate unexpectedly matched")
    else:
        if st != 200 or body != want_mig:
            mismatches.append("get_chain_migrate_old got %s %s want %s" % (st, body, want_mig))
        check_headers(hd, "get_chain_migrate_old", mismatches)
        if not (fix_dst / "000001.json").exists():
            mismatches.append("migrate missing 000001.json")
        if not (fix_dst / "head.json").exists():
            mismatches.append("migrate missing head.json")
    print("case migrate status %s body %s" % (st, body[:160]))

    # concurrent
    restore_genesis(fix_src, fix_dst)
    npost = 8
    results = [None] * npost

    def one(i):
        try:
            results[i] = http_req(port, "POST", "/block", "{\"text\":\"c%d\"}" % i, timeout=60)
        except Exception as ex:
            results[i] = ex

    threads = [threading.Thread(target=one, args=(i,)) for i in range(npost)]
    for t in threads:
        t.start()
    for t in threads:
        t.join(60)
    indexes = []
    ok = True
    for i, r in enumerate(results):
        if r is None or isinstance(r, Exception):
            ok = False
            mismatches.append("concurrent post %s failed %s" % (i, r))
            continue
        st, hd, body = r
        if st != 200:
            ok = False
            mismatches.append("concurrent post %s status %s %s" % (i, st, body))
            continue
        at = body.find("\"index\":")
        end = at + 8
        while end < len(body) and body[end].isdigit():
            end += 1
        indexes.append(int(body[at + 8 : end]))
    if mode == "fail-before":
        if ok and sorted(indexes) == list(range(1, npost + 1)):
            mismatches.append("FAIL_BEFORE concurrent unexpectedly consecutive")
    else:
        if sorted(indexes) != list(range(1, npost + 1)):
            mismatches.append("concurrent indexes %s" % indexes)
        st, hd, body = http_req(port, "GET", "/chain", None)
        if st != 200:
            mismatches.append("concurrent GET /chain %s %s" % (st, body))
        else:
            parsed = json.loads(body)
            if len(parsed) != npost + 1:
                mismatches.append("concurrent chain len %s" % len(parsed))
    print("case concurrent indexes %s" % indexes)

    if mode == "fail-before":
        if mismatches:
            print("REMAINDER_FAIL_BEFORE_UNEXPECTED")
            for m in mismatches:
                print(m)
            return 4
        print("REMAINDER_FAIL_BEFORE_MISMATCH")
        return 2
    if mismatches:
        print("REMAINDER_MISMATCH")
        for m in mismatches:
            print(m)
        return 2
    print("REMAINDER_MATCH")
    return 0


def pair_remainder(host_port, native_port, fix_src, fix_dst):
    mismatches = []
    host_port = int(host_port)
    native_port = int(native_port)

    def pair(name, setup):
        setup()
        hs, hh, hb = http_req(host_port, *name[1])
        setup()
        ns, nh, nb = http_req(native_port, *name[1])
        if hs != ns or hb != nb:
            mismatches.append("%s host %s %s native %s %s" % (name[0], hs, hb[:80], ns, nb[:80]))
            return
        for k in KEYS:
            if hh.get(k, "").lower() != nh.get(k, "").lower():
                mismatches.append("%s header %s host %s native %s" % (name[0], k, hh.get(k), nh.get(k)))
        print("pair remainder %s host %s native %s" % (name[0], hs, ns))

    def tamper_setup():
        restore_genesis(fix_src, fix_dst)
        http_req(host_port, "POST", "/block", "{\"text\":\"keep\"}")
        # both servers share data/chain; one post is enough then tamper
        raw = (fix_dst / "000001.json").read_text(encoding="utf-8")
        (fix_dst / "000001.json").write_text(raw.replace("keep", "tamper"), encoding="utf-8")

    # Host and native share the same data/chain directory. Pair write tests
    # must restore between sides. Tamper/rotate/507/migrate run sequentially
    # per side with restore.

    restore_genesis(fix_src, fix_dst)
    build_full_64(fix_dst)
    overflow = "z" * 4000
    hs, hh, hb = http_req(host_port, "POST", "/block", json.dumps({"text": overflow}, separators=(",", ":")))
    restore_genesis(fix_src, fix_dst)
    build_full_64(fix_dst)
    ns, nh, nb = http_req(native_port, "POST", "/block", json.dumps({"text": overflow}, separators=(",", ":")))
    if hs != ns or hb != nb:
        mismatches.append("507 host %s %s native %s %s" % (hs, hb, ns, nb))
    else:
        print("pair remainder 507 host %s native %s" % (hs, ns))

    restore_genesis(fix_src, fix_dst)
    last, chunk = build_near_rotate(fix_dst)
    hs, hh, hb = http_req(host_port, "POST", "/block", json.dumps({"text": chunk}, separators=(",", ":")))
    restore_genesis(fix_src, fix_dst)
    build_near_rotate(fix_dst)
    ns, nh, nb = http_req(native_port, "POST", "/block", json.dumps({"text": chunk}, separators=(",", ":")))
    if hs != ns or hb != nb:
        mismatches.append("rotate host %s %s native %s %s" % (hs, hb, ns, nb))
    else:
        print("pair remainder rotate host %s native %s" % (hs, ns))

    def mig():
        if fix_dst.exists():
            shutil.rmtree(fix_dst)
        fix_dst.mkdir(parents=True)
        old = [
            {"index": 0, "previousHash": "0", "text": ""},
            {"index": 1, "previousHash": proof_of(0, "0", ""), "text": "migrated"},
        ]
        Path("data/chain.json").write_text(json.dumps(old, separators=(",", ":")), encoding="utf-8")

    mig()
    hs, hh, hb = http_req(host_port, "GET", "/chain", None)
    mig()
    ns, nh, nb = http_req(native_port, "GET", "/chain", None)
    if hs != ns or hb != nb:
        mismatches.append("migrate host %s %s native %s %s" % (hs, hb, ns, nb))
    else:
        print("pair remainder migrate host %s native %s" % (hs, ns))

    restore_genesis(fix_src, fix_dst)
    http_req(host_port, "POST", "/block", "{\"text\":\"keep\"}")
    raw = (fix_dst / "000001.json").read_text(encoding="utf-8")
    (fix_dst / "000001.json").write_text(raw.replace("keep", "tamper"), encoding="utf-8")
    hs, hh, hb = http_req(host_port, "POST", "/block", "{\"text\":\"more\"}")
    restore_genesis(fix_src, fix_dst)
    http_req(native_port, "POST", "/block", "{\"text\":\"keep\"}")
    raw = (fix_dst / "000001.json").read_text(encoding="utf-8")
    (fix_dst / "000001.json").write_text(raw.replace("keep", "tamper"), encoding="utf-8")
    ns, nh, nb = http_req(native_port, "POST", "/block", "{\"text\":\"more\"}")
    if hs != ns or hb != nb:
        mismatches.append("tamper host %s %s native %s %s" % (hs, hb, ns, nb))
    else:
        print("pair remainder tamper host %s native %s" % (hs, ns))

    if mismatches:
        print("HOST_NATIVE_REMAINDER_MISMATCH")
        for m in mismatches:
            print(m)
        return 3
    print("HOST_NATIVE_REMAINDER_MATCH")
    return 0


def main():
    cmd = sys.argv[1]
    if cmd == "run":
        raise SystemExit(run_remainder(sys.argv[2], Path(sys.argv[3]), Path(sys.argv[4]), sys.argv[5]))
    if cmd == "pair":
        raise SystemExit(pair_remainder(sys.argv[2], sys.argv[3], Path(sys.argv[4]), Path(sys.argv[5])))
    raise SystemExit("usage")


if __name__ == "__main__":
    main()
