# L3 RCA: host gen1 timeout vs CI (3d9fc58 / 7c7c8ea)

## Why this file exists

Canna's Grok Build run of `tools/native-selfhost-handoff.ps1` on immutable `7c7c8ea` hit `gen1_host` TIMEOUT 420s at charged `steps=25363`. Hello PE compiled and ran. No gen1/gen2 hashes. CI on the same SHA and on PR42 `3d9fc58` finishes `gen1_host` with about 164k–171k charged steps in 253–362s. Ordinary programs keep 32MB / list 100000 / `VIRE_BUDGET` at most 5e6. `compile-native.vire` is an `IsCompilerProgram` entry. It uses `CompilerStepCap` 50e6 and list cap 1e6, and it ignores `VIRE_BUDGET`. The 420s wall on `gen1_host` is PowerShell, not that step cap. This note is diagnosis and probes. It is not a timeout bump and not an L2 runtime edit.

## Verdict

Measured. The compile is the same job CI finishes. Local died at about 15% of charged steps (`25363 / 170656`). Mean local rate is `25363 / 420 = 60.4` charged steps/s. CI `7c7c8ea` job `129546287069` is `164117 / 252.666 = 649.5` steps/s. CI `3d9fc58` job `129677996797` is `170656 / 361.930 = 471.5` steps/s. This Linux cloud agent (Release, `VIRE_BUDGET=5000000`) compiled the same guest to `data/gen1.hex` SHA-256 `48f12268ace6f0e5ebb58f07bff090ec91bc78058342515cf56368e2e768f815` in **81.543s** with `total_steps=170059` (**2085** steps/s). That SHA matches the Windows PR42 proof hash. The limiter on a healthy host is interpreter CPU (user time), not the builtin `hex` write and not a stuck phase that CI skips. Local 60 steps/s is slower than this SHA's **slowest** CI 2s bin (144.5 steps/s on `3d9fc58`, 308 on `7c7c8ea`). That is a host-rate gap of about **8–11× vs CI mean**, not a missing compiler step budget (50e6).

At 60.4 steps/s the remaining ~145k steps would need about **38 more minutes** (`170656 / 60.4 ≈ 2826s` total). Raising 420s would wait, not fix. Do not raise it.

## What the numbers count

`vire: still running steps=N` is `budget.Steps`. Each increment is 64 interpreter `Step` calls (`Budget.StepBatch`). `total_steps` is the final N. Heartbeats fire every 2s of `TickCount64` while `compilerProgress` is on (`Vire.cs` `Step`). `tools/native-selfhost-handoff.ps1` redirects stdout/stderr until exit, so **GitHub log timestamps on heartbeats are flush time, not phase time**. Consecutive heartbeats are still 2s bins. Parser: `python3 tools/perf-parse-heartbeats.py LOG` or `python3 tools/perf-parse-heartbeats.py LOG 25363 420`. A 420s kill in `native-selfhost-handoff.ps1` throws before it prints `data/handoff-gen1_host.err.txt`, so a local timeout log on CI would lose heartbeats. `tools/perf-handoff-windows.ps1` prints that stderr on timeout.

`gen1_host` is `dotnet exec vire.dll compile-native.vire data/compile-native.vire data/gen1.hex`. `compile-native.vire` writes with builtin `hex`, not Vire `hexOf`. Optimizing `hexOf` does not move this job. Linux probe: `probe-hex-builtin.vire` 0.085s vs `probe-hexof.vire` 1.42s for 18944 bytes.

## Authoritative CI (not user PC)

| Host | Job | `gen1_host` wall | `total_steps` | mean steps/s | hello wall / steps | SHA-256 of gen1.hex |
| --- | --- | --- | --- | --- | --- | --- |
| windows-latest Intel Xeon Platinum 8573C, 4 cores, SDK 10.0.403 | `7c7c8ea` `129546287069` | 252.666s | 164117 | 649.5 | 5.619s / 3117 | `e5d05d00073800b2…` |
| windows-latest AMD EPYC 7763, 4 cores, SDK 10.0.403 | `3d9fc58` `129677996797` | 361.930s | 170656 | 471.5 | 7.072s / 3122 | `48f12268ace6f0e5…` |
| this Linux cloud, 4 cores, SDK 10.0.403 Release | local `tools/perf-linux-phase.sh` `PERF_GEN1=1` | 81.543s | 170059 | 2085 | 2.089s / 3122 | `48f12268ace6f0e5…` (equal to PR42 Windows) |
| Grok Build (operator report only) | `7c7c8ea` | timeout 420s | last beat 25363 | 60.4 | hello passed, wall unknown | none |

CI DOTNET_TieredCompilation default on. PGO/ReadyToRun unset. Reconstructed 2s rates: `7c7c8ea` min/median/max 308 / 673 / 936 steps/s. `3d9fc58` 145 / 507 / 729. Linux cloud 1124 / 2256 / 3165. Slow CI bins sit near charged step ~106k–117k, after the local timeout point. Local 25363 is still in the **early/mid emit** region CI does at 400–800 steps/s.

PR42 adds about 6.5k charged steps vs `7c7c8ea` (~4%) and ran on a slower CI SKU. That does not explain a 420s stop at 25k steps on `7c7c8ea`.

## Linux phase walls (one run each, load ~0.2, 4 cores)

`tools/perf-linux-phase.sh`. Release `dotnet exec`. External `date` timer.

| Probe | wall | role |
| --- | --- | --- |
| `probe-load-pe.vire` | 0.068s | parse pe/asm/rt |
| `probe-open-image.vire` | 0.819s | parse plus `emitRuntime` |
| `probe-hexof.vire` | 1.420s | Vire `hexOf` + `hexIndex` |
| `probe-hex-builtin.vire` | 0.085s | C# `HexBytes` (gen1 write path) |
| `probe-emitu8.vire` | 1.446s | 21000 in-range `emitU8` |
| `probe-emitlist.vire` | 0.115s | same size `extend` |
| hello guest | 2.089s | `total_steps=3122` |
| gen1 guest | 81.543s | `total_steps=170059` |

`probe-build-exe.vire` exits 1 on this SHA (`map has no key frame_base` after `openImage` only). `frame_base` is pinned late in `src/rt.vire`. L2 owns that file. The probe is not this RCA's limiter.

Child CPU on the three hex/emit microprobes was mostly user time (`ru_utime` 2.67s vs `ru_stime` 0.81s). No `strace`/`/usr/bin/time` on this image. Limiter for emitU8 is interpreter CPU, not disk.

## Why not double (healthy host)

Charged-step rate tracks one core of the C# interpreter. `emitU8` is still a per-byte Vire call plus `push`. `emitList`/`extend` is ~12× faster for the same 21000 bytes on this VM. `openImage`/`emitRuntime` is ~0.8s here, a few percent of gen1. Builtin `hex` is ~0.09s. Guest parse of `compile-native.vire` is inside gen1's 170k steps, not the hello-sized 3k. Cutting `hexOf` cannot double gen1. Replacing leftover `emitU8` sites with `emitList` can move a slice of the 81s Linux job. It cannot close an 8× host gap to 60 steps/s.

## Ruled out

- **Need a higher step cap.** CI finishes at 164k–171k charged steps. `compile-native.vire` already has a 50e6 compiler cap. Probes still use `VIRE_BUDGET` 5e6 and list 100000, so they cannot emit a gen1-sized list.
- **Need a longer 420s on CI-class hardware.** CI wall 253–362s.
- **Hung in hexOf.** gen1 calls `hex with exe`.
- **PR42 runtime/IAT as the local timeout.** Same timeout reported on `7c7c8ea`. Linux `3d9fc58` hex equals Windows proof hash.
- **Different work on local vs CI.** Same `compile-native.vire` guest. Local last beat 25363 matches CI's early heartbeats (`24696` / `25279` region), then CI keeps going.
- **IO-bound gen1 on this cloud VM.** User-time dominated microprobes; gen1 writes one hex file at the end.

## Unknown (no user-PC probe)

This agent did not run on Grok Build. Operator facts only: hello passed, 420s, 25363 steps, no hashes. Missing and required for an environmental close:

- `hello_host` wall (`step_hello_host_sec`) on that box
- Debug vs Release dll
- Defender/realtime scan of `bin/Release` and `data/`
- `DOTNET_TieredCompilation=0` or debugger attached
- core parking, VM oversubscribe, thermal throttle
- last 20 `still running` lines with real wall times (stderr file, not a redirected flush)

If local hello is ~30s (older CouchStation note in `LOCAL-CLI-HANDOFF.md`) vs CI 6s, the same 5–10× factor predicts gen1 timeout. If local hello is CI-like (~6s) and gen1 still crawls, that would be a new, compile-size-only bug. We do not have that hello wall.

## Safe Windows handoff (parent posts, this agent does not)

Isolated checkout of `3d9fc58c80629f1fd6ac11b3576831f5c869087d`. Release build. Do not run `native-selfhost-proof.ps1`. Do not raise caps.

```text
set VIRE_BUDGET=5000000
set VIRE_HEADLESS=1
dotnet build vire.csproj -c Release
pwsh -File tools/perf-handoff-windows.ps1
```

Keep `data/perf-hello.err.txt` heartbeats. Compare `phase_hello_sec` to CI 5.6–7.1s. If hello is already ≥8× CI, gen1 at 420s is explained without a compiler change. Optional: one `native-selfhost-handoff.ps1` only after hello rate matches CI within 2×.

## Next compiler lever (blocked on diagnosis-only + L2)

Do not edit `src/rt*.vire` / `src/pe.vire` while L2 owns path/IAT. Emit-only `compile-native.vire` / `src/asm.vire` `emitU8`→`emitList` for in-range whole bytes is independent and would need HexOf/EmitU8 tests plus Windows equal-hash re-proof. Expected healthy-host gain is a fraction of 81s Linux / 253–362s CI, not 8×. Stop here until the handoff hello wall exists or L2 freeze SHA.

## How to rerun the cloud side

```text
export DOTNET_ROOT=$HOME/.dotnet VIRE_BUDGET=5000000 VIRE_HEADLESS=1 PERF_GEN1=1
dotnet build vire.csproj -c Release
bash tools/perf-linux-phase.sh
python3 tools/perf-parse-heartbeats.py tools/perf-data/linux-cloud-gen1host.err.txt
```

HexOf/EmitU8/Extend: 13 tests passed on this SHA. Caps unchanged.
