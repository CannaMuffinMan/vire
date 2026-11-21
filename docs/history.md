# Historical notes (archived)

This file keeps closed-out handoff, phase, performance, and audit notes so they are not lost when the root copies were removed. Live status lives in `CHANGELOG.md`, `NATIVE-COMPILER.md`, `FUZZ-CAMPAIGN.md`, `SECURITY.md`, and `FINDINGS-LEDGER.md`. Caps in these logs (arena 33554432, list 100000, steps 5000000) were never raised.


---

## Archive: NATIVE-COMPILER.md (Nov 5 work log; status kept in NATIVE-COMPILER.md)

# Native compiler notes

## Status (Nov 17, 2026): self-host proof closed

The gen1 = gen2 identical-binary self-host proof described under "Next change" below is done. The native compiler compiles itself and the second generation is byte-identical to the first, on both targets:

- Windows (PE): first proven in CI at PR #40 (merged 7c7c8ea), re-proven on every security lane since. At the current tip (PR #78 merge 6e969fc2) gen1 = gen2 hash 4478d315 across 5 repeated Windows runs.
- Linux (ELF): gen1 = gen2 hash faf29c8c at PR #78 merge 6e969fc2.

The rule stays the same: no merge without proof on real machines. The rest of this file is the original Nov 5 work log, kept for history.


This file records the native self-host work from the chat that ended when the budget ran out. It is a work log, not a claim that Vire is finished.

Active tree: `D:\_scratch\worktrees\vire-e-len`.

The host compiler is the C# runner. From that folder:

```text
dotnet exec .\bin\Release\net10.0\vire.dll compile-native.vire data/compile-native.vire data/compile-self.hex
```

The working directory must be the worktree. Paths in Vire use forward slashes. Root `compile-native.vire` uses `src/`. The input `data/compile-native.vire` uses `data/src/`. A host rebuild executes `src/`. The image it writes contains the compiled functions from `data/src/`. Both copies have to stay in sync or the entry stub and the next generation disagree.

Hex to exe: trim the file, turn each pair into a byte, `WriteAllBytes`. Do not commit or push from this log. Git on `D:` has dubious ownership. Do not change global git config.

## What stands

`data/compile-self.exe` compiles `data/hello-stage.vire`. The emitted program prints `hello from stage` and exits 0. Confirmed again after the intern experiment was reverted, using `data/compile-round.exe` from the worktree. That exe was then copied back over `data/compile-self.exe`, and `data/compile-self-2.hex` was copied back over `data/compile-self.hex`.

Those restored files:

- `data/compile-self.exe`, 376832 bytes, 11/5/2026 10:01:54 AM
- `data/compile-self.hex`, 753664 bytes, 11/5/2026 10:01:10 AM

## What does not stand

The same exe cannot compile itself inside the 32MB heap. A self-compile succeeds when the Windows mapping is 96MB or 128MB. At 32MB, 48MB, and 64MB the process access-violates (`0xC0000005`, exit `-1073741819`). The allocator limit was still 256MB, so it wrote past the smaller mapping.

Until one exe compiles `data/compile-native.vire` and the second hex matches the first, Vire does not stand on its own. Do not claim it can do what any other language can do.

## Constraints that still bind

- Do not raise `ProgramStepCap` (5,000,000), the 32MB native arena, or the 2,000,000 list-item cap as the fix.
- Do not load a driver. Do not deploy. Payments stay off. Testnet stays out of the public Vire repo.
- Local listeners are `127.0.0.1` only. Never ports 7099, 8778, 7071, 7072, 17841, 7093, 17843.
- Never print secrets. Never the word "unhackable".
- Do not delete the C# runner before a second native rebuild is proven.
- GPU cannot run the compiler. One interpreter rebuild at a time. A host rebuild of `compile-native.vire` takes about 60 minutes.
- Windows Defender blocked some freshly written exes in `data/`. An exclusion was added for `D:\_scratch\worktrees\vire-e-len\data`. A blocked exe is not proof the program is bad.

## Bugs fixed on the way to hello

The native compiler already compiled `data/hello-stage.vire` and `data/min.vire`, printed `compiled`, and exited 0. The emitted 18944-byte programs access-violated. A C# compile of empty `main` exited 0. The byte compare had 715 zeros where the C# image had relocation and import bytes. The first difference was file offset 431.

A debug compiler printed fixes length 698, image length 18287, code label 352, first fix at image index 363 to `iat_gs`. File offset of an image index is the index plus 68. The relative value was `352 - (363 + 4) = -15`, which should be the bytes `F1 FF FF FF`.

These guesses were tested and were wrong:

- The fixes list was not empty.
- List slot writes work. `put 65 into xs at 1` printed 65.
- Signed subtraction works. `0 - 15` printed `-15`.

The real miss was the 32-bit wrap. `x + 4294967296` does not change a native value. `4294967296` does not fit a 32-bit immediate and is a no-op. `2147483647` does fit. `-15 + 2147483647 + 2147483647 + 2` prints `4294967281` (`2^32 - 15`).

`poke32` in `src/pe.vire` and `data/src/pe.vire` was changed to that three-add sequence. That was not enough. The zero call relocations are written earlier by `patchRel` in `src/asm.vire`. `emitU32` had the same no-op add. Both were changed in `src/asm.vire` and `data/src/asm.vire`. `poke16` still adds 65536, which fits.

`rt_idiv` is unsigned `div` and returns 0 when the dividend is negative (`test rdx; js`). Leaving the relative value negative therefore writes four zero bytes even if the add had worked. The three-add sequence makes the value positive, so `div` by 256 yields the little-endian bytes.

`data/compile-native.vire` was missing `idiv` and `join` in `builtinArity`. Those names were added so a later self-compile can resolve `floorDiv` and `hexOf`.

The host rebuild of that relocation fix printed `compiled` and exited 0. Hex length 753664, written 11/5/2026 8:51 AM. The native exe compiled hello. The program printed `hello from stage` and exited 0. The byte at file offset 431 in that hello exe was `E0 00 00 00`, not `F1 FF FF FF`. The program still ran, so the first fixup was no longer the crashing zero slot.

## Why self-compile crashed

The hello compiler access-violated when asked to compile `data/compile-native.vire`. Windows Error Reporting named fault offset `0x2603` in `compile-self.exe`. That address is `rt_memeq` (`mov al, [rcx]`), a string compare with a bad pointer.

Bisect:

- Two functions in one file compiled.
- `read` of a missing file printed `missed`.
- `lower` printed the lowercased path.
- `ends` access-violated.
- `use "data/no-such-file.vire"` access-violated. It should have stopped in `checkUse`.
- `use "src/asm.vire"` access-violated. `asm.vire` alone only reported a missing `main`.

`rt_ends` computed the suffix start with `sub rax, rcx` (`48 29 C8`). After `mov rdx, [rcx]` loaded the haystack length, `rcx` was still the string pointer, so the length minus the pointer was a wild address. The source bytes were `72, 41, 200`, which is `48 29 C8`, not a subtract of the length register.

The compare length was also wrong. `emitPop2` leaves the needle tag in `r8` (the integer 2). The call site did `mov rax, r8` (`4C 89 C0`) and `rt_memeq` counts with `r8`, so a surviving compare would have checked 2 bytes. `begins` had the same backwards move.

The running exe was patched in place, and the source was updated in `src/rt-more.vire` and `data/src/rt-more.vire`:

- `ends`: save the needle length with `mov r8, rax` (`49 89 C0`), then `sub rdx, rax`, add that to the haystack bytes, and compare that many bytes.
- `begins`: `mov r8, rax` instead of `mov rax, r8`.

After the patch, `use "data/no-such-file.vire"` printed `use stays out of data and site` and exited 1. `use "src/asm.vire"` compiled, and the program printed `used asm`.

Guest programs emitted by that patched exe still had the old `ends` bytes. The patch changed the runner's machine code, not the `emitList` constants it copies into the next image. A source rebuild is required for the next image to contain the fix.

## Self-compile result

The patched exe compiled `data/compile-native.vire` in under a second and wrote `data/compile-self-native.hex` (753664 bytes). It did not match the previous host hex. Twenty-one bytes differed. Most of those were the new `ends` and `begins` immediates. One was the arena size.

A later host rebuild included the `ends` fix and printed `compiled`, exit 0, hex 753664, written 11/5/2026 9:59 AM. That exe compiled the compiler again. The second hex differed by one byte, file offset 888:

- Host image: `BA 00 00 00 10`, which is `mov edx, 0x10000000` (256MB).
- Native output: `BA 00 00 00 02`, which is `mov edx, 0x02000000` (32MB).

`src/rt.vire` still asked for `268435456` when that host rebuild started. `data/src/rt.vire` already asked for `33554432`. The host executes `src/` while emitting the entry stub, and compiles `data/src/` into the output's functions. The stub and the function that emits the next stub disagreed. `src/rt.vire` was then set to `33554432` so the copies match. That edit was after the host rebuild, so the 9:59 image still has the 256MB stub.

The image produced by the native self-compile allocates 32MB. It compiled hello. It access-violated when compiling the compiler. Patching only the mapping size in the known-good 256MB exe showed the real need:

| Mapping | Self-compile |
|---|---|
| 32MB | access violation, no hex |
| 48MB | access violation, no hex |
| 64MB | access violation, no hex |
| 96MB | exit 0, hex 753664 |
| 128MB | exit 0, hex 753664 |

`rt_alloc` compared the bump pointer with `heap + 268435456` (`src/rt-more.vire` and `data/src/rt-more.vire`, the `emitU32` after `73, 129, 194`). The mapping was 32MB, so the check never fired and the write left the reserved pages. Both files now pass `33554432` to that `emitU32`. A host rebuild of that limit change has not been proven. Do not treat the source edit as a finished image.

## Intern experiment, reverted

Every `source at i` allocated a new 16-byte string in `rt_at`. That looked like a large part of the 64MB to 96MB use. `at_text` was changed to reuse 128 one-character strings at `r15 + 4096`.

The host rebuild of that change printed `compiled`, exit 0, hex 755712, written 11/5/2026 11:09 AM. The exe was 377856 bytes. It exited 1 and printed nothing for `data/hello-stage.vire`. A 96MB mapping of that same image also exited 1 with no output. The machine code at the intern site looked well formed (`lea rcx, [r15+4096]`, `movzx ebx`, compare with 128). The failure was not diagnosed further.

`at_text` was restored to the allocating sequence in both `rt-more.vire` files. The 32MB allocator limit edit was left in place. `data/compile-self.exe` and `data/compile-self.hex` were restored from the hello-capable image, not left as the silent intern build.

## Earlier fixes this chat depended on

These were already in the tree before the relocation and `ends` work. They are why the compiler could get as far as emitting a PE:

- In-place map header. A 24-byte header, capacity at +8, slots pointer at +16, tag 5. `rt_grow_map` allocates new slots only and writes the new capacity and pointer into the same header. `pin` of `iat_gs` then survives a function boundary. A probe printed 1.
- List headers were already stable. `put 65 into xs at 1` printed 65.
- `rt_keys` loop limit stored `rcx` (`48 89 4D E8`).
- Map compare uses `cmp rcx, [rdx+8]`.
- `set_slot` saves the slot address on the stack before a call, because `r14` is the VM frame and a helper can clobber it.
- Emit helpers return the image. The C# host failed with `push needs a list` when they returned `true`.
- `hexOf` uses `join`. `idiv` exists in the runtime. Do not emit `idiv` or `join` calls unless those runtime symbols exist.
- Native step budget is not the same knob as the C# `VIRE_BUDGET`. Do not raise the caps.

`4294967296` remains in `emitU64` as a comparison for the high half. Pool lengths used there are small. It was not the hello crash.

## Do not resume

- BlueStacks and the APK path. That was a sidetrack. The installed APK at `D:\_scratch\vire-apk-install\app.apk` is not a Vire product.
- Loading a driver.
- Company site, package index, debugger, and foreign-text work. Those were not this session's deliverable.
- A second full host rebuild while one is running.
- Raising the 32MB arena, the step cap, or the list cap to make self-compile pass.

## Next change, when there is budget (done, see Status at top)

Make `rt_alloc` stop at the same 32MB the mapping reserves, and cut the compiler's allocations until a self-compile fits. Then:

1. Host-compile `data/compile-native.vire` with `src/` and `data/src/` identical, including the 32MB size in both `rt.vire` and both `rt-more.vire` limit checks.
2. Turn that hex into an exe.
3. Compile `data/hello-stage.vire` and require the text `hello from stage` and exit 0.
4. Have that exe compile `data/compile-native.vire` to a second hex.
5. Compare SHA-256. A match is the self-host proof. Anything short of that is not done.



---

## Archive: SELFHOST.md (obsolete: treated gen1=gen2 as still open)

# Native selfhost checklist

Standing on its own means gen1 (native PE of `compile-native.vire`) compiles `compile-native.vire` plus a guest to gen2, and gen1.hex == gen2.hex. Hello hex equality is not that proof.

This file is the compiler/performance lane. Native path/frame/intern stay PR #35 / PR #31.

## Proof steps

1. Host interprets `compile-native.vire` and emits a PE that includes `rt_extend` (this PR). `compile-native` must accept `extend` as a 2-arg builtin. **Host emit of an `extend` guest: required. Running that PE: Windows-only.**
2. Copy compiler sources under `data/` (or `data/src/`) so native `read` can load them. **Host staging is in this integrate branch** (`tools/stage-compiler-src.sh`). Native gen1 using those copies is still Windows-only.
3. Windows: host-compile `compile-native.vire` itself (timeout, do not run overnight). **Open. Linux cannot run the PE.**
4. Windows: gen1.exe compiles hello. stdout `hello from stage`, exit 0. **Open.**
5. Windows: gen1.exe compiles `compile-native.vire` to gen2. hex SHA match. **Open. 32MB / intern (PR #31) is the likely arena blocker.**
6. Caps stay 5e6 steps, list 100000 on the host, 32MB native arena. Do not raise them.

## This PR

`extend` was host C# + CompiledMachine only. `compile-native.vire` printed `there is no definition named extend` (measured). That would make gen1 unable to compile `emitList`. Frontend `builtinArity` and native `rt_extend` close that hole. `rt_extend` lives at the end of `emitMore` in `src/rt-more.vire`, after `rt_join`. PR #35 edits earlier `path_ok` / IAT hunks in the same file. Do not copy those.

## Windows recipe

```text
set VIRE_BUDGET=5000000
dotnet exec bin\Release\net10.0\vire.dll compile-native.vire data\extend-guest.vire data\extend-guest.hex
dotnet exec bin\Release\net10.0\vire.dll compile-native.vire data\guest-hello.vire data\guest-hello.hex
```

To run the PE, use a Windows box. Do not run `native-selfhost-proof.ps1` for hours. Stop at the first missing `data/src` read or 32MB fail.

---

## Archive: PHASE0-DONE.md

# Phase 0 done-criteria: proof map

Base: `phase0/c8-c9`. Close-out on `phase0/closeout`. Each line is a Phase 0 done-criterion from `VIRE-ROADMAP.md` and the check that proves it.

Sealed `.vc` envelopes use a random AES-256-GCM nonce, so two seals of the same payload are not identical files. The compiler artifact that must match is the **unsealed payload**. CI dumps that payload and compares it byte-for-byte.

| Criterion | Proof |
|---|---|
| CI green on `net10.0` | `vire.csproj`, `tests/Vire.Tests/Vire.Tests.csproj` target `net10.0`; `windows/vire.windows.csproj` targets `net10.0-windows`. `global.json` pins SDK `10.0.403`. Workflow `.github/workflows/check.yml` sets `dotnet-version: 10.0.x` on build, test, selfhost, selfhost-windows, native-windows, and publish. Tests: `HarnessTests.ProjectsTargetNet10AndWarningsAreErrors`, `HarnessTests.SdkAndProjectsAreNet10`, `HarnessTests.WorkflowPinsActionsToFullShas`. |
| Stage-1 `.vc` == stage-2 `.vc` byte-for-byte | `tools/selfhost-check.sh` and `tools/selfhost-check.ps1` compile stage 1, 2, and 3, compare `payload-sha256`, then `payload-write` each `.vc` and `cmp -s` / `Compare-Object` the unsealed bytes. Mismatch exits 1. CI jobs `selfhost` and `selfhost-windows` run those scripts. Tests: `HarnessTests.SelfhostChecksCompareUnsealedPayloadBytes`, `SealTests.PayloadWriteDumpsUnsealedBytes`. |
| No binaries in git | `.gitignore` excludes `bin/`, `obj/`, `dist/`, `publish/`, `*.exe`, `*.dll`, `*.pdb`, `*.hex`. CI job `tracked-binaries` runs `tools/check-tracked-binaries.sh`, which fails on tracked `exe`/`dll`/`pdb`/`hex`, on `.vc` outside `tests/fixtures/`, and on `bin/` `obj/` `dist/` `publish/` paths. Tests: `HarnessTests.GitTracksNoBinaries`, `HarnessTests.GitIndexHasNoBuildBinaries`. Allowed fixture: `tests/fixtures/old-xor.vc` (refused at open by `SealTests.OldXorSealIsRefused`). |
| Docker images pinned by digest; Actions pinned by full commit SHA | `Dockerfile` `FROM` lines use `@sha256:` 64-hex digests. Every `uses:` in `check.yml` is `owner/action@` plus a 40-hex SHA. Tests: `HarnessTests.DockerfileBasesArePinnedByDigest`, `HarnessTests.WorkflowPinsActionsToFullShas`. |
| Crash suite never kills the process | `CrashTests.CrashCorpusRunsInOneProcess` runs every `tests/crash/*.vire` plus generated depth/width/huge/while fixtures through `Program.Execute` in the test process (not `Process.Start`). Exit code must be 0–2, never 3 (`internal error`). `Environment.ProcessId` is unchanged. `CrashTests.CrashFixturesStayAlive` uses the same in-process `Run`. `JsonAndShowRefuseAdversarialValuesInProcess` covers JSON/`say` without leaving the process. Track D: `FuzzTests` plus `FuzzRegressionTests` (see `PHASE0-FUZZ.md`). |
| Every Phase 0 item has a passing test | C1–C9 coverage remains in `HarnessTests`, `CrashTests`, `ExprDepthTests`, `PathSsrfTests`, `SealTests`, `ListenTests`, `ChainTests`, `ServeTests`, `SuiteTests`. This file maps the Phase 0 **done-line** (roadmap §5) to the checks above. |

## What this close-out does not claim

- Stage-1 and stage-2 **sealed files** on disk are not byte-identical: GCM nonces are random by design (`SealTests.RoundTripAndNonceDiffer`). The **payload** is identical.
- Authorization for `POST /block` is still open (C7 carry-forward).
- No FCGBC/testnet code was added here.

---

## Archive: PHASE0-FUZZ.md

# Phase 0 Track D: security fuzz harness

Base: `phase0/closeout`. Branch: `phase0/fuzz`.

Deterministic seeded fuzz runs inside ordinary `dotnet test` (`FuzzTests`, 400 iterations, seed `20261030`). A longer job is `workflow_dispatch` / nightly (`fuzz.yml`, `tools/fuzz-long.sh`, `VIRE_FUZZ_ITERS`). Corpus is text only under `tests/fuzz/corpus/`.

## Findings

| Finding | Before | Fix | Regression |
|---|---|---|---|
| Deep `if`/`while`/`try` blocks recursed in the parser with no cap; enough nesting could overflow the stack. | Stack overflow / process death | Parser `blockNest` cap 256 → `block is nested too deeply` | `FuzzRegressionTests.NestedBlocksHitAVireErrorNotAStackOverflow` |
| `.vc` loader decrypted then `Json.Read` + unchecked casts. Sealed JSON that was not a funcs table threw `InvalidCastException` (exit 3) instead of a Vire error. | Internal error / could look like a crash | `CompiledProgram.LoadFuncs` validates shape; JSON errors become `compiled file is damaged` | `FuzzRegressionTests.SealedGarbageJsonDoesNotRunAndDoesNotCrash` |
| `Json.Read` had a depth cap but no input size cap. | Unbounded allocation on a huge string | Refuse inputs longer than 1,000,000 characters | `FuzzRegressionTests.JsonOverSizeLimitIsRefused` |

Campaign expansion (grammar-aware frontend, builtins, GC pressure, path bind, native PE, nightly+Windows) is documented in `FUZZ-CAMPAIGN.md` and does not replace this Track D log.

Listen request parsing is now `HttpWire` (header block 16 KB, request line 8 KB, body 1 MB, no chunked). Fuzz covers truncated, oversized, and malformed request lines/headers/bodies. AES-256-GCM still fail-closes on truncate/flip/forge (`SealTests` plus `FuzzTests.SealLoaderSeededFuzzRejectsAndFailsClosed`).

---

## Archive: LOCAL-CLI-HANDOFF.md

# Local Windows / Grok Build CLI handoff

Do not run this on a cloud agent. Do not touch production, OBS, Station, or secrets. Isolated scratch checkout only.

## Exact ref

- Remote: `https://github.com/CannaMuffinMan/vire`
- Branch (mutable, do not check out by name): `cursor/integrate-perf-38-0258`
- SHA (immutable pin): `d5da2a36e6bda857b4ecf2c184093676b4a7f357`
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
git fetch origin d5da2a36e6bda857b4ecf2c184093676b4a7f357
git checkout --detach d5da2a36e6bda857b4ecf2c184093676b4a7f357
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

---

## Archive: INTEGRATE-38.md

# Integration of compiler speed onto PR #38

PR #38 (`e0d70a0`, `cursor/native-runtime-32mb-0b9c`) is unchanged. This branch is `cursor/integrate-perf-38-0258`.

Security hunks kept: `GetFileAttributesA` / `GetFileInformationByHandle`, `frame_base`, `heap_cell`, `intern_tab`, Linux `lstat` hardlinks.

Compiler hunks kept: `emitList` -> `extend`, `hexOf` in-range, `buildExe` list concat, `rt_extend`, host `extend`.

## Source staging

Native `read` still only opens `data/` and `site/`. `tools/stage-compiler-src.sh` copies `compile-native.vire` and `src/*.vire` into `data/` / `data/src/` without widening that policy. Hashes must match.

## Measured on this Linux VM (Release, `VIRE_BUDGET` unset)

| Job | Wall | Notes |
|---|---|---|
| host compile hello | 1.125–1.276s | not a PR #36 microprobe claim |
| host compile `data/staged-use.vire` (`use src/asm.vire` under `data/`) | 2.994s | staging works |
| host compile `data/compile-native.vire` as guest | 66.002s | compiler-as-guest hex emitted |
| Unicorn `data/p-hello.hex` | EXIT 0, `hello from stage` | not Win32, not gen1/gen2 |

Hello hex SHA `747f6e1d…` (44032 chars). Different from pre-intern trees because PR #38 runtime is in the image.

## Tests

42 passed: CompilerStage, NativeExtend, NativePath, NativeArena, NativePe, Extend, PathSsrf, EmitU8, HexOf, BudgetCap.

## Unproven

Real Win32 PE. gen1.hex == gen2.hex. Hours-long proof script. See `LOCAL-CLI-HANDOFF.md`.

---

## Archive: COMPILE-EXTEND.md

# Bulk emitList and PE concat after PR #34

Depends on PR #34 (`7cbc63c`) / PR #33 (`3f9e0cd`). Not PR #31, #32, or #35.

## Profile on PR #34 (Linux, uninstrumented, this VM, 60s cap)

`probe-build-exe` 0.521s vs `probe-open-image` 0.516s on an earlier sample, then 0.533s vs 0.516s. The extra was a 14336-iteration `push` in `buildExe`. `emitList` still ran 846 times in `src/rt.vire` plus `src/rt-more.vire` (counted). Guest empty/hello/strings/expr compiles stayed near 1.15–1.20s. Linux hello did not hide an 8s `emitU8`-style cost. Windows call density from Build still says those 846 Vire loops can matter there. Linux walls are not Windows walls.

## Change

- Host builtin `extend` mutates a list by appending another, wrapping each extra item like `emitU8`, refusing past the list cap.
- `emitList` is `extend`. Interpreter and `CompiledMachine` both have it.
- `buildExe` concatenates the 512-byte header and the image with list `+` instead of per-byte `push`.

## After (same VM)

| Probe | PR #34 | This |
|---|---|---|
| `probe-emitlist.vire` 21000 | 0.190s | 0.110–0.120s |
| `probe-open-image.vire` | 0.516s | 0.368s |
| `probe-build-exe.vire` | 0.533s | 0.390s |
| compile empty | 1.130s | 1.055s |
| compile hello | 1.167s | 1.162s |
| compile strings | 1.166s | 1.165s |
| compile expr | 1.269s | 1.167s |

Hello `.hex` SHA-256 `c82fcb56dab3407745e40510e230eae29fbf5c1770fdd90124ad9985ed8a3173` unchanged. PE execute unproven.

Linux hello was already parse + `openImage` + `hexOf`. The isolated probes moved. Windows must be timed on Windows.

## Overlap with PR #35

PR #35 (`cursor/security-audit-fix-0b9c`) also edits `src/pe.vire` (GetFileAttributesA IAT) and `src/rt.vire` (frame_base). This PR edits `buildExe` at the end of `pe.vire` and `emitList` at the top of `rt.vire`. Different hunks. Do not merge by copying PR #35 sandbox code into this lane. Rebase/merge later by hand.

## Windows recipe

```text
set VIRE_BUDGET=5000000
dotnet exec bin\Release\net10.0\vire.dll probe-emitlist.vire
dotnet exec bin\Release\net10.0\vire.dll probe-open-image.vire
dotnet exec bin\Release\net10.0\vire.dll probe-build-exe.vire
dotnet exec bin\Release\net10.0\vire.dll compile-native.vire data\guest-hello.vire data\guest-hello.hex
```

Copy `guest-hello.vire` into `data\` first (`read` only opens `data/` and `site/`). Compare hello hex SHA to `c82fcb56…`. Do not run `native-selfhost-proof.ps1`.

---

## Archive: COMPILE-PERF.md

# Remaining host compile time after PR #33

Base is PR #33 (`3f9e0cdd13b4fad66f4c3fcc11b7d5290ecb73e9`), itself on `native-compiler` `0f758e702771ed3276ee553a76c7a86cc83846dd`. Not PR #31 or PR #32.

Windows numbers below are from local Grok Build, not rerun here. Linux numbers were measured on this VM.

## Uninstrumented profile (Linux x86_64, PR #33, Release, `VIRE_BUDGET=5000000`, 60s cap)

| Probe | Wall | Role |
|---|---|---|
| `probe-load-pe.vire` | 0.060s | parse `pe`/`asm`/`rt`/`rt-more` |
| `probe-open-image.vire` | 0.385s | parse plus `emitRuntime` |
| `probe-hexof.vire` 18944 bytes | 1.313s | `hexOf` plus building the list |
| `probe-emitlist.vire` 21000 | 0.191s | already fixed in PR #33 |
| `probe-emitu8.vire` 21000 | 1.555s | leftover per-call `emitU8` |
| compile empty guest | 2.003s | |
| compile hello guest | 2.031s | |
| compile strings guest | 2.071s | |
| compile expr guest | 2.228s | |

Guest size and strings were not the remaining Linux cost. `hexOf` was. It called `hexIndex` (text, find, number, maybe `floorDiv`) once per output byte. Same shape as the old `emitU8` loop.

## After `hexOf` in-range lookup (same VM, uninstrumented)

| Probe | Wall |
|---|---|
| `probe-hexof.vire` | 0.178s |
| compile empty | 1.130s |
| compile hello | 1.167s |
| compile strings | 1.166s |
| compile expr | 1.269s |

Hello `.hex` SHA-256 `c82fcb56dab3407745e40510e230eae29fbf5c1770fdd90124ad9985ed8a3173`, 37888 chars, same as PR #33 and the Windows report. PE execute still unproven here.

In-range whole bytes index `hexPairs` directly. Out of range and non-whole numbers still use `hexIndex` (including `72.5` -> `48`). Caps unchanged.

## Windows recipe for local Build (do not treat Linux walls as Windows)

From an isolated checkout of this branch, Release `dotnet` 10:

```text
set VIRE_BUDGET=5000000
dotnet exec bin\Release\net10.0\vire.dll probe-hexof.vire
dotnet exec bin\Release\net10.0\vire.dll compile-native.vire guest-hello.vire data\guest-hello.hex
dotnet exec bin\Release\net10.0\vire.dll compile-native.vire guest-strings.vire data\guest-strings.hex
dotnet exec bin\Release\net10.0\vire.dll compile-native.vire guest-expr.vire data\guest-expr.hex
dotnet test tests\Vire.Tests\Vire.Tests.csproj -c Release --filter "FullyQualifiedName~HexOf|FullyQualifiedName~EmitU8"
```

Time each `dotnet exec` with an external timer. Compare hello `.hex` SHA to `c82fcb56…`. Do not run `native-selfhost-proof.ps1`.

## Remaining

`openImage` / runtime emit, `buildExe` byte copy, leftover `emitU8` call sites, lexer on huge guests. Host bulk-append builtin is still later. Native PE run and gen1/gen2 fixed-point unproven. Native sandbox parent-symlink and frame overlap stay merge blockers on other PRs.

## Host `VireDebug.Break` skip unless `VIRE_DEBUGGER=1`

Each user-function `Call` used to run `VireDebug.Break`, which created `data/`, walked reparse points, and called `File.Exists` on `data/break.txt`. CI job `129755174034` on SHA `2304852` charged `total_steps=164117` with `break_probes=1619992` and `phase_gen1host_sec 304.117`. After the skip, job `129759130623` on SHA `b1de7a3` kept the same step count and printed `break_probes=0` with `phase_gen1host_sec 8.426`. Caps and Defender are unchanged. Named-function stops still run when `VIRE_DEBUGGER=1`.

---

## Archive: EMIT-PERF.md

# Emit fast path

Host byte emission for the native compiler. Caps unchanged. Native PE execute and gen1/gen2 fixed-point stay unproven on this Linux host.

## Hypothesis

Tree-walk `emitList` -> `emitU8` (normalize, `floorDiv`) dominates host compile of small programs. Secondary guesses (lexer, maps, rebuild runtime, native arena) were not the first patch.

## Before (this Linux x86_64 VM, 2026-11-06, Release `vire.dll`)

`dotnet exec bin/Release/net10.0/vire.dll`, `VIRE_BUDGET` unset.

| Probe | Wall |
|---|---|
| `probe-push.vire` 21000 push | 0.085s |
| `probe-emitu8.vire` 21000 `emitU8` of 72 | 1.442s |
| `probe-emitlist.vire` 21000 in-range `emitList` | 1.591s |
| `emit-range.vire` | 0.066s, stdout locked |

Windows report at `18c2623` (user-supplied, not rerun here). Host compile hello-stage ~31-36s. 21000 `emitU8` ~34s vs push ~0.13-0.18s. Same shape, larger absolute times. Linux hello 2.604s on a different branch/host is not the same probe.

## After (same VM, same `dotnet exec` Release dll)

| Probe | Wall |
|---|---|
| `probe-push.vire` 21000 push | 0.089s |
| `probe-emitu8.vire` 21000 `emitU8` of 72 | 1.389s (still a call per byte) |
| `probe-emitlist.vire` 21000 in-range `emitList` | 0.185s |
| `compile-native.vire` `data/hello-emit.vire` | 2.523s before stash, 2.147s after |
| hello `.hex` | 37888 bytes, SHA-256 `bac704b422ffafe53dc867cd16debc37277f25cd4aea8f06c67602e885e040ce` identical |

`emitU8` body fast-path did not move the 21000-call probe. Skipping the `emitU8` call in `emitList` did. Hello host emit dropped about 0.38s on this machine. Not Windows 31s and not a millisecond claim.

## Tests (same VM, after the patch)

Related filter (EmitU8, Conformance, BudgetCap, SuiteTests, BuiltinParity, UseNeed). 29 passed, 0 failed, 20 s.

Full `dotnet test tests/Vire.Tests/Vire.Tests.csproj -c Release --nologo` with `VIRE_BUDGET` unset. 117 passed, 8 failed, 3 m 2 s. The eight failures are this base's Linux Windows-only tests (`Foreign*`, driver, Android, APK, toolchain, headless ASCII vs em dash). They match `native-compiler` without PR #32. They are not emit-path regressions. This PR does not take those Linux contracts.

## Semantics

`emitU8` still wraps. In-range 0..255 is `push`. Out of range still uses `floorDiv` and the negative clamp. `emitList` `push`es in-range bytes and calls `emitU8` otherwise.

`data/src/` is not in this tree. Only `src/asm.vire` and `src/rt.vire` changed.

## Later (aspirations, not measurements)

0. This patch. Per-byte call density.
1. Host bulk-append builtin shared with `CompiledMachine`.
2. Lexer range checks, char interning, nonquadratic strings. Same semantics.
3. `.vc` host compiler artifact with parity.
4. Native intern/32MB/fixed-point. PR #31. Separate.
5. Runtime template and image buffer after earlier gates.

Seconds-to-milliseconds in older notes are hopes, not gates.

## Unproven

Windows PE run. gen1.hex == gen2.hex. Hours-long self-compile. Native parent-symlink and hardlink sandbox. Native frame vs value stack.

---

## Archive: SECURITY-AUDIT.md

# Security audit

Dedicated security lane. Base `native-compiler` `0f758e7`. Head of this branch is the git commit that ships with this file. Not a CVE filing. No live targets.

## Tracks

**Dependency CVEs** are only those verified against resolved versions and an advisory database.

**First-party issues** do not get invented CVE IDs.

## Dependency inventory

Runtime product (`vire.csproj`) has no PackageReference. SDK pin `10.0.403` in `global.json`.

Test-only: `Microsoft.NET.Test.Sdk` 17.14.1, `xunit` 2.9.3, `xunit.runner.visualstudio` 3.1.4.

`dotnet list package --vulnerable --include-transitive` (SDK 10.0.403, nuget.org) reported no vulnerable packages for `vire` or `Vire.Tests` including transitives (`Newtonsoft.Json` 13.0.3 and the xunit/test-platform closures listed in the 2026-11-06 scan). That is the NuGet feed for restored packages, not a runtime-wide clean bill. No package bump.

## First-party findings

### F1. Linux host hardlink bypass

Host `VirePaths.LinkCount` returned 1 on Linux. `write` through `data/` onto `deps.lock` could rewrite the lock. **Fixed** with `lstat` `st_nlink`. `PathSsrfTests.HardLinkCannotRewriteDepsLock` uses `ln` and passed on this VM. Overlaps PR 32's host `lstat` only. This branch does not take PR 32's gap plan or Linux foreign-test contracts.

### F2. Native parent/leaf reparse

Native `CreateFileA` followed reparse points. **Fixed in emit** with prefix `GetFileAttributesA` (lstat-style last component in the Unicorn stub) and `FILE_FLAG_OPEN_REPARSE_POINT`. Unicorn: parent name `data` returns 0x420, `CREATE []`, message `files stay inside the program folder`. Linux Unicorn is not Windows `CreateFileA`. Windows recipe `tools/native-sec-windows.ps1` is **blocked** on this VM.

### F3. Native frame chain vs heap+64KB

Unbounded `rt_save_frame`. **Fixed** at 64 frames (512 bytes from `frame_base`). Unicorn `boom with 65` printed `definitions called too deeply` and not `survived`. Independent of PR 31 intern/`heap_cell`. Hot file `src/rt.vire`.

### F4. Interned path walk / double-read

Vuln `7c7c8ea` interned path literals in RX `.text`; in-place NUL during the walk AVs (Windows `f4_double_read vuln NOTE x0`). **Fixed** with `rt_alloc`+`rt_memcpy` scratch copy. Exact-head Windows `5b39c9a` job `129796755075`: `fixed NOTE x2 code=0`.

### F5. Reopen-after-nlink and walk-then-open

Write inspects nlink then truncates with `SetFilePointerEx`+`SetEndOfFile` on that handle. There is no `CREATE_ALWAYS` after the nlink check. Walk-then-open (GFA then `CreateFileA`) is closed by `rt_bind_path` / `GetFinalPathNameByHandleA`. Windows proof uses a **test-only** `Sleep` widener on isolated worktrees (not product IAT). Job `129796755075`: F5 vuln `victim_hits=1` outside=`HACKED`; fixed `victim_hits=0` `write_code=1`. Walk vuln `outside_hits=1`; fixed `0`.

### F6. Crash filter `CREATE_ALWAYS` on `crash-rip.txt`

Vuln hello PE patched after VEH smashed a `crash-rip.txt` hardlink onto KEEP. **Fixed**: RIP only on stdout; no `iat_cf` in `crash_filter`. Job `129796755075`: vuln smashed KEEP; fixed `KEEP=KEEP` and `crash rip=`.

## Overlap (do not concatenate drafts)

| PR | Head (as of 2026-11-07 fetch) | Hot files vs this branch | Resolution |
|---|---|---|---|
| 31 intern | `18c2623` | `src/rt.vire`, `src/rt-more.vire` | Ported intern/`heap_cell` onto this integration draft. PR31 branch left at `18c2623`. |
| 32 gap/lstat | `3550d5c` | `VirePaths.cs`, `src/pe.vire`, `src/rt-more.vire` | Same Linux `lstat` idea. This walk covers **parents** and `rt_read`. Do not import GAP-CLOSURE.md. |
| 33 emitList | `3f9e0cd` | `src/rt.vire` `emitList` | Untouched here. Performance agent owns 33/34. |
| 34 hexOf | `7cbc63c` (base 33) | none expected | Do not pull. |

Host check-then-open: `RefuseReparse` then `File.*` by path lost a `renameat2` swap. **Fixed** by opening a handle and matching Linux `lstat`/`fstat` identity (Windows `GetFinalPathNameByHandleW`). Test `HostCheckThenOpenToctouFailBeforePassAfter` (env `VIRE_TEST_TOCTOU_MS` is test-only). Linux writable zones use `StringComparison.Ordinal`. Native trailing `data/payload.bat.` is refused in `path_space`. F8 host `EmitU8Byte` `(long)x & 255` agrees with native `mov rcx,imm64`. F13 `native-arena-check.sh` forbids 32MB at PE offsets 224 **and** 240; planted 240 write fails; `check.yml` selfhost runs the script. ARM job filter includes `HardLinkCannotRewriteDepsLock`.

## Verification

- Windows `native-windows` job `129796755075` (`5b39c9a`) and `129811692427` (`607624e`): F4/F5/F6/walk recipe ok; host TOCTOU + trailing-dot on the same job. `native-selfhost-windows` job `129796754998`: gen1=gen2 `7fad880322a59feaa9542f51557939bdd5eb7b65070ea8f1c37e50f6509be9cb`.
- `tools/native-sec-emu-check.sh` is on the Linux `selfhost` job (pip unicorn + `fetch-depth: 0`): wrap `[0, 0, 1]`, trailing-dot refuse, walk-open-race fail-before `7c7c8ea` / pass-after HEAD.
- Caps 32MB / list 100000 / 5M, sandbox, and Defender are unchanged. PR 42 stays draft.

## Gates

- `/poteto-mode`: smallest fail-closed emit fixes after proven probes.
- `/setup-pstack`: **blocked** (interactive).
- `/interrogate`: two Grok adversaries, not four (Opus weekly cap). Findings F5 and F6 survived reruns and were fixed. Remaining "emu follows leaf symlink" was an emu `stat` vs `lstat` bug and was fixed in the stub.
- `/blast-radius`: host hardlink test; Unicorn nlink2 does not `CREATE_ALWAYS`; write uses SetEndOfFile; hello still prints.

### F-Linux. ELF `open(2)` followed parent/leaf symlinks

Linux `CreateFileA` shim was `syscall 2` without `O_NOFOLLOW`. **Fixed** with component `openat` + `O_NOFOLLOW|O_CLOEXEC` and host `LinuxOpenAtWalk`. Proof: `tools/native-elf-nofollow.sh` (Ubuntu). Residual: TOCTOU between directory `openat` and leaf `openat` if `data` is swapped for a symlink in that window; leaf still cannot follow. F6 remains stdout RIP; no `data/crash.log` create.

## Caps

32MB arena, `ProgramStepCap` 5_000_000, list 100_000: unchanged.

## Integration (PR31 intern + PR35 path/frame)

Branch `cursor/native-runtime-32mb-0b9c` stacks on PR35 `f292325` and ports intern/`heap_cell` from PR31 `18c2623` by hand. Original branches are unchanged.

Included:

- PR35 `6a43ec2`, `f292325` (host lstat, path walk, frame 64, Unicorn sec tests)
- PR31 intern table + `heap_cell` alloc ceiling (source port, not a merge commit)
- PR31 tests `NativeArenaTests`, `NativePeEmitTests`, `tests/native/*`, `tools/native-pe-emu.py` (IAT extended to 11 imports)

Not included: PR33/34/36 emitList/hexOf/bulk extend. PR32 gap doc. PR31 `check.yml` unicorn CI step.

Conflict reasoning: `src/rt.vire` entry stub needed both `mov [heap_cell], rax` (rax still the mapping) and `frame_base = r15`. `rt_alloc` must not add 32MB to live `r15`. Intern lives in the image, not at heap+4096 (that overlapped the frame chain).

