#!/usr/bin/env python3
from __future__ import annotations

import re
import sys

STEP_RE = re.compile(r"still running steps=(\d+)")
TOTAL_RE = re.compile(r"total_steps=(\d+)\s+total_pending=(\d+)\s+step_batch=(\d+)")
SEC_RE = re.compile(r"step_(\w+)_sec\s+([0-9.]+)")
SHA_RE = re.compile(r"gen1_sha256\s+([0-9a-f]+)")
HOST_RE = re.compile(r"^(os |framework |cores |cpu |dotnet_sdk |DOTNET_)")


def main(path: str) -> int:
    steps = []
    totals = []
    secs = {}
    sha = None
    host = []
    with open(path, encoding="utf-8", errors="replace") as f:
        for line in f:
            text = line.rstrip("\n")
            if "os " in text or "cores " in text or "cpu " in text or "dotnet_sdk" in text or "DOTNET_" in text:
                if "vire:" not in text:
                    host.append(text.split("Z ", 1)[-1] if "Z " in text else text)
            m = STEP_RE.search(text)
            if m:
                steps.append(int(m.group(1)))
            m = TOTAL_RE.search(text)
            if m:
                totals.append((int(m.group(1)), int(m.group(2)), int(m.group(3))))
            m = SEC_RE.search(text)
            if m:
                secs[m.group(1)] = float(m.group(2))
            m = SHA_RE.search(text)
            if m:
                sha = m.group(1)

    gen1_beats = steps
    print("file", path)
    print("host_lines", len(host))
    for h in host[:12]:
        print("host", h.strip())
    print("step_sec", secs)
    print("gen1_sha256", sha)
    print("totals", totals)
    print("heartbeat_count", len(gen1_beats))
    if not gen1_beats:
        return 1
    runs = []
    cur = [gen1_beats[0]]
    for s in gen1_beats[1:]:
        if s >= cur[-1]:
            cur.append(s)
        else:
            runs.append(cur)
            cur = [s]
    runs.append(cur)
    run = max(runs, key=len)
    print("longest_run_beats", len(run), "first", run[0], "last", run[-1])
    deltas = [run[i] - run[i - 1] for i in range(1, len(run))]
    if not deltas:
        return 0
    heartbeat_ms = 2000
    heartbeat_s = heartbeat_ms / 1000.0
    rates = [d / heartbeat_s for d in deltas]
    rates.sort()
    print("heartbeat_ms", heartbeat_ms)
    print("bin_s", heartbeat_s)
    print("delta_min", min(deltas), "delta_median", rates[len(rates) // 2] * heartbeat_s, "delta_max", max(deltas))
    print("rate_min_steps_s", min(rates), "rate_median_steps_s", rates[len(rates) // 2], "rate_max_steps_s", max(rates))
    if "gen1_host" in secs and totals:
        wall = secs["gen1_host"]
        charged = totals[-1][0]
        print("gen1_host_wall_s", wall)
        print("gen1_host_total_steps", charged)
        print("gen1_host_mean_steps_s", charged / wall if wall else None)
    if len(sys.argv) >= 4:
        local_steps = int(sys.argv[2])
        local_sec = float(sys.argv[3])
        print("local_timeout_steps", local_steps, "local_timeout_s", local_sec)
        print("local_mean_steps_s", local_steps / local_sec)
        if "gen1_host" in secs and totals:
            print("implied_local_finish_s", totals[-1][0] / (local_steps / local_sec))
    slow = sorted(enumerate(deltas), key=lambda x: x[1])[:8]
    print("slowest_2s_bins index,delta,from_step")
    for i, d in slow:
        print(i, d, run[i])
    return 0


if __name__ == "__main__":
    if len(sys.argv) not in (2, 4):
        print("usage: perf-parse-heartbeats.py LOG [LOCAL_STEPS LOCAL_SEC]", file=sys.stderr)
        sys.exit(2)
    sys.exit(main(sys.argv[1]))
