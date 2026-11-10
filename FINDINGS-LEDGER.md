# Vulnerability / finding evidence ledger

Vulnerable SHA (immutable): `7c7c8ea3dcc4030ba8714fc2330d30b67f8d6867`
Fixed SHA (this branch): `0d1a32071b247f267b299d40f9ff353f951362cc`
PR: https://github.com/CannaMuffinMan/vire/pull/42
No CVE IDs assigned. Implemented ≠ OS-verified.

## Implemented vs verified

| ID | Implemented on 0d1a320 | Verified how | Not verified |
|---|---|---|---|
| F1 | yes | fail-before 7c7c8ea TIMEOUT 3s; after `[1, 2, 1, 2]` exit 0 | — |
| F2 | yes (x64+arm64 structs) | linux-x64 ordinary file loads | **linux-arm64 CI does not exist** |
| F3 | yes | before `that expression is not ready` exit 1; after Unicorn stdout `3` | — |
| F4 | yes | Unicorn hello/read FAULTS []; copy in emit | real Windows RX `.text` fault vs copy |
| F5 | yes (SetEndOfFile, no CREATE_ALWAYS) | Unicorn nlink2 disp=3 only; nlink1 write file=`ok` | **two-process Windows replace race** |
| F6 | yes | crash_filter has no iat_cf | crash PE on Windows not separately logged |
| F7 | yes (require sandbox text) | recipe on 7c7c8ea CI `native sec windows recipe ok` without logging the message | **PR42 Windows log pending; 7c7c8ea did not prove message** |
| F8 | yes | before `[4294967296]`; after `[0]` | — |
| F9 | yes | PackZipSigned gone | — |
| F10 | yes | host clang fallback gone | — |
| F11 | yes | emit snapshot | native `extend a,a` PE not emu-run |
| F12 | yes | Unicorn EXIT 1 numbers message | — |
| F13 | yes | 7c7c8ea arena-check exit 1; 0d1a320 ok | — |

## Fail-before / fail-after (linux-x64 this VM, SDK 10.0.403)

Worktree `/tmp/vire-7c7c8ea` at 7c7c8ea vs `/agent/repos/vire` at 0d1a320.

F1 guest `let a be [1, 2]` / `extend with a, a`:
- before: `TIMEOUT` (3s, never printed the list)
- after: exit 0 `[1, 2, 1, 2]`

F8 guest `extend with [], [2147483648]`:
- before: exit 0 `[4294967296]`
- after: exit 0 `[0]`

F3 `compile-native.vire data/list-expr.vire` with `[1 + 2]`:
- before: exit 1 `that expression is not ready`
- after: compile exit 0; Unicorn STDOUT `3`

F13 `bash tools/native-arena-check.sh`:
- before: exit 1
- after: `native arena check ok`

F12 Unicorn `extend with [], ["x"]` on 0d1a320: EXIT 1 `extend needs numbers in the extra list`

## Selfhost distinction (not a PR42 regression)

PR38 CI used `run data/stage1.vc compiler.vire` (no `data/` prefix) → `files stay in data or site`.
Merged 7c7c8ea `tools/selfhost-check.sh` uses `run data/stage1.vc data/compiler.vire data/stage2.vc`.
This VM on 0d1a320: `bash tools/selfhost-check.sh` → stage1=stage2=stage3 `cfb30cad2cf27b2fd543add142be0bf9a5baea0d8b6824cde218f67f228350e4` `selfhost ok`.
GitHub 7c7c8ea and PR42 `selfhost` / `selfhost-windows` **pass**. Sandbox not weakened.

## Windows CI (GitHub windows-latest, not Unicorn)

7c7c8ea run `42730292404`:
- native-windows: hello compile exit 0; `native sec windows recipe ok`; smoke `PASS hello`
- native-selfhost-windows (continue-on-error:true): gen1 hello exit 0 `hello from stage`; gen2 exit 0; **gen1_sha256=gen2_sha256=`e5d05d00073800b2fc7710f8538925de086ad6f92c5ba7b363a82f4d7a01e728`**
PR42 `0d1a320` native-windows **pass** (59s); native-selfhost-windows **still pending** at ledger write. Final SHA gen1/gen2 hashes **not yet captured** for 0d1a320 (IAT/crash/path/write emit will change the PE hash vs e5d05d00; equality gen1==gen2 is the gate).

## pstack

Skills live on unmerged `origin/tooling/pstack-skills` (PR28 draft), path `.cursor/skills/{poteto-mode,interrogate,blast-radius}/SKILL.md`. **Not present on native-compiler / this PR.** Full 4-adversary interrogate arena not executed. Blast-radius local runs: nlink1 write still truncates to `ok`; nlink2 still refuses.

## F1 interpreter self-extend (DoS / cap bypass)

- Status: **fixed**
- Exposure: `extend with a, a` grew `extra.Count` each append, skipped step budget inside the loop, could exceed list cap intent.
- Fix: snapshot `extra.Count` before the loop (`Vire.cs`).
- Proof: `CopilotFindingsTests.F1_SelfExtendSnapshotsOriginalCount` — `[1,2]` becomes `[1,2,1,2]`.
- Residual: native PE still needs F11.
- Platforms: host interpreter and compiled VM sharing `Program.ExtendList`.

## F2 Linux ARM64 `lstat` layout

- Status: **fixed** (ARM64 unexecuted here)
- Exposure: x86-64 `st_nlink` at offset 16 as `ulong`; aarch64 `st_mode`+`st_nlink` overlap, ordinary files look like >Int32.MaxValue links.
- Fix: `LinuxStatX64` vs `LinuxStatArm64` selected by `ProcessArchitecture`.
- Proof: `F2_LinuxOrdinaryFileLinkCountIsOne` on linux-x64 (this VM). linux-arm64 **not run**.
- Residual: needs a linux-arm64 job; no such runner in this environment.

## F3 numeric-list fast path

- Status: **fixed**
- Exposure: `[1 + 2]`, `[1, "x"]`, `[-value]` failed `that expression is not ready`.
- Fix: always `parseExpr` for list elements in `compile-native.vire`.
- Proof: `F3_CompileNativeKeepsListExpressions` plus compile-native guest `[1 + 2]` (see PR commands).
- Residual: none for parsing.

## F4 path walk writes RX strings

- Status: **fixed**
- Exposure: `mov [rcx+rax], 0` mutated interned/pool path bytes in `.text`.
- Fix: `rt_alloc`+`rt_memcpy` scratch copy, then walk.
- Proof: Unicorn `native-sec-emu-check.sh` hello/read; `F4_PathWalkCopiesBeforeNul`.
- Residual: Unicorn is stubbed kernel32, not Windows OS proof.

## F5 reopen-after-nlink TOCTOU

- Status: **fixed** (logic; OS race not live-tested)
- Exposure: CloseHandle then CREATE_ALWAYS on the path after nlink==1.
- Fix: `SetFilePointerEx`+`SetEndOfFile` on the validated handle; no second open.
- Proof: source no longer emits CREATE_ALWAYS (2) on `write_have`; emu nlink2 still refuses without CREATE_ALWAYS.
- Residual: real Windows replacement race not executed (no user PC).

## F6 crash log hardlink truncate

- Status: **fixed**
- Exposure: `crash-rip.txt` CREATE_ALWAYS in cwd, no sandbox.
- Fix: crash RIP only to stdout via `GetStdHandle`/`WriteFile`.
- Proof: `F6_CrashFilterDoesNotCreateCrashRipFile`.
- Residual: stdout still receives crash hex (intended).

## F7 junction test accepts any nonzero exit

- Status: **fixed** (recipe; Windows execute still blocked here)
- Exposure: crash exit 1 without sandbox text counted as pass.
- Fix: require `files stay inside the program folder`.
- Proof: `F7_WindowsJunctionRecipeRequiresSandboxText`.
- Residual: Couchy local Windows handoff; not run from this agent.

## F8 `q * 256` int overflow

- Status: **fixed**
- Exposure: extra `2147483648` should wrap to byte 0; `int` multiply overflowed.
- Fix: `(double)q * 256.0`.
- Proof: `F8_EmitU8WrapsAboveInt32Max`.
- Residual: none for this wrap.

## F9 JDK-only APK plaintext manifest

- Status: **fixed**
- Exposure: `PackZipSigned` returned `data/app.apk` with text XML, not AXML.
- Fix: fail if aapt/zipalign/apksigner/android.jar missing. Removed `PackZipSigned`.
- Proof: `F9` + `ApkTests` expects `not installed` when tools absent; no apk written.
- Residual: real APK still needs Android build-tools (not a standalone Vire requirement).

## F10 Android clang host fallback

- Status: **fixed**
- Exposure: PATH `clang` produced host x86-64 `.so` while reporting android success.
- Fix: NDK clang only; always `--target=aarch64-linux-android35`.
- Proof: `F10` + `AndroidSoTests` expects `phone SDK is not installed` without NDK.
- Residual: android `.so` is optional toolchain, not required to run Vire.

## F11 native self-extend

- Status: **fixed**
- Exposure: live length reload on `extend with a, a`.
- Fix: snapshot source length in `[rbp-64]`.
- Proof: `F11_NativeExtendSnapshotsSourceLength`.
- Residual: Unicorn self-extend guest optional; interpreter F1 covers host.

## F12 native extend nonnumeric extra

- Status: **fixed**
- Exposure: `extend with [], ["x"]` appended in PE; host rejects.
- Fix: non-tag-1 extra jumps `extend_bad`.
- Proof: Unicorn PE `extend with [], ["x"]` EXIT 1 `extend needs numbers in the extra list`. `F12_NativeExtendRejectsNonnumericExtra`.
- Residual: none for reject path.

## F13 PE reserve grep

- Status: **fixed**
- Exposure: `native-arena-check.sh` grepped 32MB header; emit writes 1MB stack/heap reserve; 32MB is the VirtualAlloc arena.
- Fix: grep `1048576`; keep 32MB arena greps on rt/more.
- Proof: `F13` + `bash tools/native-arena-check.sh`.
- Residual: none.

## Dependency inventory

Runtime `vire.csproj`: no PackageReference. SDK pin `10.0.403`. Test-only xunit 2.9.3 / Microsoft.NET.Test.Sdk. `dotnet list package --vulnerable` to be recorded in the PR report. No CVE IDs invented.

## FCG stack readiness blockers (no FCG implementation)

- Native `read` is `data/`|`site/` only; compiler `use` files live in `src/`.
- Host VC selfhost stage2 `files stay in data or site`.
- 32MB / 5M / list 100000 caps unchanged — a full FCG rebuild may need a later explicit cap policy, not a silent raise.
- Windows gen1/gen2 hash proof is a separate local gate.
