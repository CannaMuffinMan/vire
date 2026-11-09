# Local Windows / Grok Build CLI handoff

Do not run this on a cloud agent. Do not touch production, OBS, Station, or secrets. Isolated scratch checkout only.

## Exact ref

- Remote: `https://github.com/CannaMuffinMan/vire`
- Branch (mutable, do not check out by name): `cursor/integrate-perf-38-0258`
- SHA (immutable pin): `6ac4452168ff83467656876469551653e36ad663`
- Depends on: PR #38 `e0d70a075147113a1d3ba569fad879f8982224ea` plus the compiler stack through PR #37 `f119db8db2e9ff2b8bad5c35761886dbf76ebf50`
- Do not check out `cursor/native-runtime-32mb-0b9c` to apply these compiler commits. That branch stays PR #38.

## Caps (unchanged)

```text
set VIRE_BUDGET=5000000
set VIRE_HEADLESS=1
```

Native arena 32MB. Host list cap 100000. Do not raise them.

## Isolated workspace

```text
git clone https://github.com/CannaMuffinMan/vire C:\scratch\vire-integrate-38
cd C:\scratch\vire-integrate-38
git fetch origin 6ac4452168ff83467656876469551653e36ad663
git checkout --detach 6ac4452168ff83467656876469551653e36ad663
set VIRE_BUDGET=5000000
set VIRE_HEADLESS=1
dotnet build vire.csproj -c Release
```

## Commands (PowerShell only)

Hello emit + host info + `total_steps` (timeout 120s):

```text
pwsh -File tools/native-hello-handoff.ps1
```

Sandbox junctions/hardlinks (must get past hello compile; was broken when `compile-native.vire` bound to `[int]$TimeoutSec`):

```text
pwsh -File tools/native-sec-windows.ps1
```

Full bounded selfhost (stage, hello PE, gen1, gen1 hello, gen2 SHA). Timeouts: hello host 120s, hello run 15s, gen1 host 420s, gen1 hello 120s, gen1 hello run 15s, gen2 native 600s. Stop at first fail. Do not run `native-selfhost-proof.ps1` overnight.

```text
pwsh -File tools/native-selfhost-handoff.ps1
```

Expect `hello from stage` from both PEs, `compiled` on emits, `gen1_sha256` == `gen2_sha256`, and stderr `vire: total_steps=N`. Heartbeats every 2s wall print `steps=` so far (N is `budget.Steps`, one count per 64 interpreter `Step` calls). More heartbeat lines means a slower machine, not extra compiler work. Compare `total_steps` across hosts.

Linux hello ~1.1s / CI windows-latest hello 3.1s / CouchStation hello 31.4s. Do not treat Linux times as Windows.

## Logs to keep

- stdout and stderr
- `hello_host_compile_sec`, `step_*_sec`, `cpu`, `cores`, `dotnet_sdk`, `total_steps`
- SHA-256 of `data\guest-hello.hex`, `data\gen1.hex`, `data\gen2.hex`

## Stop criteria

- Stop at the first missing `data/src` read, 32MB / out of memory, step-budget stop, or timeout.
- Do not merge, deploy, or change OBS.
- Unicorn on Linux is not this proof.
