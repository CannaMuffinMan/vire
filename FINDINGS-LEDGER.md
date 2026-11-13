# Vulnerability / finding evidence ledger

Vulnerable SHA (immutable): `7c7c8ea3dcc4030ba8714fc2330d30b67f8d6867`
#57 merge baseline: `d818f1691ed8659538a10255c58211ebc1316e00` (proven head `4097d27f100c0b244ca8691349c513d4ac235962`).
This branch replays PR42/48/49 commits after `3d9fc58` onto that baseline (not stacked on #42/#48/#49).
Evidence commits include `0d1a320` · `b7ee393` · `3d9fc58` plus leftover `2b53c32`…`a8b080b`.
PR42 frozen review head: `dee819a7f0a256c70faa042b048fb4f8e542ab44`.
FAIL_BEFORE at d818f169 (check run `43214687746`, native-selfhost-windows job `131170809061`): `IsCompilerProgram` filename sniff; no `TryLinuxFdId`; `Break` always opens `data/break.txt`; gen1_host_sec 376.308; gen1=gen2 `debc11ec8a9e756626b27f8b917e02864015ec45922ecebff263a2c76f2ee60e`. Product `VIRE_TEST_TOCTOU_MS` was never on d818 (introduced on the #42 stack in `607624e` then removed in `7278a8d`); this land keeps it out of product OpenFile.
No CVE IDs. Caps/sandbox/Defender unchanged.

## Implemented vs verified

| ID | Implemented | Verified (property, not crash-only) | Still open |
|---|---|---|---|
| F1 | yes | 7c7c8ea TIMEOUT 3s vs after `[1, 2, 1, 2]` exit 0 | — |
| F2 | yes | linux-x64 + ARM F2; ARM filter now also `HardLinkCannotRewriteDepsLock` | full ARM suite unrun |
| F3 | yes | before `that expression is not ready`; after Unicorn `3` | — |
| F4 | yes | Unicorn + Windows `f4_double_read` / intern section; **W^X** PE `.text` `0x60000020` / `.data` `0xC0000040` + `VirtualQuery` / SEC_IMAGE + silent `rt_wx_check` | intern may sit in RW `.data`; property is copy-before-NUL |
| F5 | yes | Unicorn nlink; Windows hardlink; **until-hit then fixed==0**; dest nlink==1 then **tmp + MoveFileExA** atomic replace under `data/` | walk-then-open is a separate gate (`f_walk`) |
| F6 | yes | stdout `crash code/rip/off`; startup `rt_crash_prepare` bind+no-reparse into `crash_abs`; VEH CreateFile only that absolute path | log skipped if prepare fails (junctioned `data\`) or `CREATE_NEW` exists |
| F7 | yes | `42770835327` printed `files stay inside the program folder` | — |
| F8 | yes | `and 255` on host; `mov rcx,imm64` in compile-native; host+Unicorn `[0, 0, 1]` for 2^31 / 2^39 / 2^31+1 | — |
| F9 | yes | PackZipSigned gone | — |
| F10 | yes | host clang fallback gone | — |
| F11 | yes + bytes reload | Windows `3d9fc58` gen1 hello 0 / gen2 0 / equal `48f12268ace6f0e5ebb58f07bff090ec91bc78058342515cf56368e2e768f815` jobs `129677976694` `129677996797` | re-prove after this PE-byte change |
| F12 | yes | Unicorn EXIT 1 numbers message | — |
| F13 | yes | forbids 32MB at PE 224 **and** 240; planted 240 write must fail; CI `native-arena-check.sh` | — |
| walk-then-open | yes | Unicorn + Windows Sleep-widener job `129796755075` vuln `outside_hits=1` / fixed `0` | host C# TOCTOU is a separate gate |
| host TOCTOU | yes | `HostCheckThenOpenToctouFailBeforePassAfter`: `File.AppendAllText` after swap writes outside; `AppendAllTextInside` file-id refuses | Windows job filter on `native-windows` |
| Linux case | yes | `LinuxWritableZoneCompareIsCaseSensitive`; `use Data/` is not `data/` | — |
| trailing dots | yes | emu `payload.bat.` CREATE []; Windows `native_trailing_dot refused`; Win32 `WriteAllText` strips to `payload.bat` (fail-before) | — |
| F8 wrap | yes | host+Unicorn `[0, 0, 1]`; compile-native `72, 185` imm64 | 7c7c8ea native wrap mismatch in emu-check |
| compiler-mode claim | yes | guest `compiler.vire` + `emitU8` + `VIRE_BUDGET=10` no longer gets 50M; `--compiler` host flag; env only lowers | landed on #57 baseline |
| product TOCTOU env | yes | `VIRE_TEST_TOCTOU_MS` never in d818 product; tests use `TestToctouDelayMs`; file-id bind is new vs d818 | landed on #57 baseline |
| Break probe skip | yes | `VIRE_DEBUGGER=1` still stops; unset means `break_probes=0` | landed on #57 baseline |

## Fail-before / fail-after (linux-x64 this VM, SDK 10.0.403)

Worktree `/tmp/vire-7c7c8ea` at 7c7c8ea vs `/agent/repos/vire` at 0d1a320.

F1 guest `let a be [1, 2]` / `extend with a, a`:
- before: `TIMEOUT` (3s, never printed the list)
- after: exit 0 `[1, 2, 1, 2]`

F8 guest `extend with [], [2147483648, 549755813888, 2147483649]`:
- before (WholeDiv clamp / one subtract): `[256]` / `[256]`/`[257]` class results, native `mov rcx,imm32` disagreed
- after: host and Unicorn `[0, 0, 1]`

F3 `compile-native.vire data/list-expr.vire` with `[1 + 2]`:
- before: exit 1 `that expression is not ready`
- after: compile exit 0; Unicorn STDOUT `3`

F13 `bash tools/native-arena-check.sh`:
- before: exit 1 (and a planted `poke32 … 240, 33554432` used to pass)
- after: `native arena check ok`; planted 240 write fails; `check.yml` runs the script

F12 Unicorn `extend with [], ["x"]` on 0d1a320: EXIT 1 `extend needs numbers in the extra list`

## Selfhost distinction (not a PR42 regression)

PR38 CI used `run data/stage1.vc compiler.vire` (no `data/` prefix) → `files stay in data or site`.
Merged 7c7c8ea `tools/selfhost-check.sh` uses `run data/stage1.vc data/compiler.vire data/stage2.vc`.
This VM on 0d1a320: `bash tools/selfhost-check.sh` → stage1=stage2=stage3 `cfb30cad2cf27b2fd543add142be0bf9a5baea0d8b6824cde218f67f228350e4` `selfhost ok`.
GitHub 7c7c8ea and PR42 `selfhost` / `selfhost-windows` **pass**. Sandbox not weakened.

## Windows CI (GitHub windows-latest, not Unicorn)

7c7c8ea run `42730292404`:
- native-windows: hello compile exit 0; `native sec windows recipe ok`; smoke `PASS hello`
- native-selfhost-windows (`continue-on-error: true`): gen1 hello exit 0 `hello from stage`; gen2 exit 0; **gen1_sha256=gen2_sha256=`e5d05d00073800b2fc7710f8538925de086ad6f92c5ba7b363a82f4d7a01e728`**

PR42 `b7ee393` run `42768841182` (21 checks named success; **rollup is not proof**):
- native-windows: `hello_host_compile_exit 0`; Junction/Hardlink created; `native sec windows recipe ok`; smoke PASS hello. Recipe did **not** print `files stay inside the program folder` because native stdout was not echoed (fixed this push).
- native-selfhost-windows: `step_hello_pe ok`; `gen1_host` exit 0; **`gen1_hello` compile exit 0**; **`gen1_hello_run` exit `-1073741819` `crash_access_violation`**. No `gen1_sha256` / `gen2_sha256`. Job green only because `continue-on-error: true`.

That AV is a **regression of the F11 snapshot**: `extend_bloop` compared the snapshotted count but kept `rdx` as the destination object, so `extend` of a **bytes** extra (compile-native `emitList`) copied garbage after the first byte. 7c7c8ea reloaded `[rbp-16]` every bytes iteration; gen1 hello ran. This push restores `mov rdx, [rbp-16]` before `[rdx+16]`.

Linux Unicorn after the reload (host gen1.hex compiling `data/guest-hello.vire`):
- EXIT 0 `compiled`
- `sha256(data/guest-hello.hex) == sha256(data/emu-gen1-hello.hex) == 4e2e7d8d6362c94d6f907c24ac4a8ee647be9cfb9e22de1005e23d6e86b8b9dc`
- emu of that PE: EXIT 0 STDOUT `hello from stage` FAULTS []

`3d9fc58` jobs `129677976694` / `129677996797`: gen1 hello compile/run **0**, gen2 **0**, **gen1_sha256=gen2_sha256=`48f12268ace6f0e5ebb58f07bff090ec91bc78058342515cf56368e2e768f815`**. `native-windows` printed `files stay inside the program folder`. This F4/F5/F6 push changes `src/rt.vire` pool bytes — **equal-hash must reprint**.

## pstack / interrogate / blast-radius

Vendored skills are on unmerged `origin/tooling/pstack-skills` (PR28 draft): `.cursor/skills/{poteto-mode,interrogate,blast-radius}/SKILL.md`. They are **not** on `native-compiler` / PR42 worktree. Inspected via `git show origin/tooling/pstack-skills:...`. Did not copy/install that tree into this PR.

- **interrogate**: requires arena Phase A/B with four `generalPurpose` adversaries and Phase F reruns. **Not executed.** Blocker: skills + multi-model arena not on this branch/runtime.
- **blast-radius**: safety fact for the AV was “F11 snapshot still walks the extra bytes object.” Proven by Unicorn fail-mode (b7ee393 gen1-hello AV on Windows; after reload, gen1 hello hex matches host and runs). nlink1 write still `ok`; nlink2 still refuses (`native-sec-emu-check.sh` ok). Caps 32MB / list 100000 / 5M, sandbox, Defender untouched.

## Standalone vs bootstrap

Delivered runtime is **.NET 10** (`dotnet exec` / `dotnet publish` single-file `vire` / `vire.exe`). No gcc/clang/Java required to interpret or to emit native Windows x64 PE. Android APK/`.so` need NDK/aapt and **fail closed** without them (F9/F10). Native PE still needs a Windows loader (or Unicorn stub) to execute; this Linux VM cannot run the PE on a real kernel32.

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
- Proof: `F2_LinuxOrdinaryFileLinkCountIsOne` linux-x64; GitHub `ubuntu-24.04-arm` job Passed 1 on `3d9fc58`.
- Residual: that job is the F2 filter only, not the full suite.

## F3 numeric-list fast path

- Status: **fixed**
- Exposure: `[1 + 2]`, `[1, "x"]`, `[-value]` failed `that expression is not ready`.
- Fix: always `parseExpr` for list elements in `compile-native.vire`.
- Proof: `F3_CompileNativeKeepsListExpressions` plus compile-native guest `[1 + 2]` (see PR commands).
- Residual: none for parsing.

## F4 path walk writes interned strings

- Status: **fixed**; Windows OS recipe this push
- Exposure: in-place `mov [rcx+rax], 0` on interned path (Copilot: `.text` RX; guest pool may be `.data` RW). Second `read` of the same literal can fail if the slash was NULled.
- Fix: `rt_alloc`+`rt_memcpy` scratch copy, then walk.
- Fail-before: 7c7c8ea PE of `f4.vire` (worktree, isolated `data/f4/note.txt`).
- Pass-after: this SHA PE prints `NOTE` twice (`f4_double_read`).
- Residual: if vuln PE also prints twice, intern is RW and first read still “works”; copy remains required.

## F5 reopen-after-nlink TOCTOU

- Status: **fixed**; Windows two-process recipe this push
- Exposure: CloseHandle then CREATE_ALWAYS on the path after nlink==1.
- Fix: `SetFilePointerEx`+`SetEndOfFile` on the validated handle.
- Fail-before: 7c7c8ea write PE vs racer hardlinking `data/f5-slot.txt` onto `data/f5-keep.txt` (40 rounds). Hit count logged; 0 hits ≠ proof of safety on 7c7c8ea (CREATE_ALWAYS still in that tree).
- Pass-after: this SHA write PE **must** leave `KEEP` (0 victim hits).
- Residual: reopen-after-nlink is the handle truncate. Walk-then-open (GFA then CreateFile with no directory handle) is **not** this fix.

## Walk-then-open TOCTOU (Adversary 4 at 3d9fc58)

- Status: **emit + Unicorn this push**; Windows junction-swap recipe this push; **not frozen**
- Exposure: after `GetFileAttributesA` on `data` and `data/note.txt`, rename `data`→`data.real` and point `data` at `outside/`. `CreateFileA('data/note.txt')` wrote outside `hacked`; real stayed `SECRET-KEEP-ME-LONG`. Static parent reparse still refused.
- Fix: `rt_bind_path` opens `.` with `FILE_FLAG_BACKUP_SEMANTICS`, `GetFinalPathNameByHandleA` on cwd and the opened file; remainder must be `/data/` or `/site/` (fail closed).
- Fail-before: 7c7c8ea write PE in Unicorn `walk-open-race` and Windows `walk-vuln.exe` until first outside hit.
- Pass-after: this SHA write PE refuses; outside stays `SECRET-KEEP-ME-LONG`.

## F4 W^X (this lane)

- Status: **implemented**; Windows `VirtualQuery` after `SEC_IMAGE` map plus in-process `rt_wx_check`
- FAIL_BEFORE: `7fd41b88` IAT has no `VirtualQuery`
- PASS_AFTER: this SHA IAT includes `VirtualQuery`; hello PE `.text` not writable, `.data` not executable; hello still prints `hello from vire`
- Residual: `SEC_IMAGE` mapping is the loader's section protect, not a second running process's `VirtualQueryEx`

## F5 atomic replace (this lane)

- Status: **implemented** in native `rt_write`
- FAIL_BEFORE: `7fd41b88` had no `MoveFileExA`; dest was truncated in place
- PASS_AFTER: dest nlink==1, write `dest.tmp`, `MoveFileExA`; two-process reader must not see mixed OLD/NEW
- Residual: empty reads during create of a brand-new name are possible before the first successful replace

## F6 crash log hardlink truncate

- Status: **fixed**; Windows crash PE this push
- Exposure: `crash-rip.txt` CREATE_ALWAYS; later relative `data/crash.log` CREATE_NEW followed a junctioned `data\` outside the program folder.
- Fix: RIP on stdout (no `crash-rip.txt`). Startup `rt_crash_prepare` rejects `FILE_ATTRIBUTE_REPARSE_POINT` on `data`, `rt_bind_path`s the directory, stores absolute `crash_abs`. VEH CreateFile uses only that buffer.
- Fail-before: `7fd41b88` (no dedicated log); junction leak `1600038` writes `crash.log` through `data\` junction.
- Pass-after: this SHA, junctioned `data\` does not receive `crash.log`; real `data\crash.log` still gets `crash code/rip/off`.
- Residual: stdout crash hex is intended. Patch is a test fixture in `data/native-sec-windows`, not product code. Crash before `rt_crash_prepare` (null at very first instruction) skips the log.

## F7 junction test accepts any nonzero exit

- Status: **fixed** (recipe)
- Exposure: crash exit 1 without sandbox text counted as pass.
- Fix: require `files stay inside the program folder`; echo native stdout so CI logs the string.
- Proof: `F7_WindowsJunctionRecipeRequiresSandboxText`. b7ee393 Windows job reached `recipe ok` without printing the text.
- Residual: next `native-windows` log must contain the sandbox sentence.

## F8 `q * 256` int overflow

- Status: **fixed**
- Exposure: extra `2147483648` should wrap to byte 0; `int` multiply overflowed.
- Fix: `(double)q * 256.0`.
- Proof: `F8_EmitU8WrapsToAnd255` plus Unicorn wrap guest `[0, 0, 1]`.
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

- Status: **fixed, then regression found, then reload restored**
- Exposure: live length on `extend with a, a`; first snapshot patch dropped `mov rdx,[rbp-16]` on the bytes loop, so compile-native `extend` of byte buffers emitted corrupt PE (Windows `gen1_hello_run` ACCESS_VIOLATION, property = wrong code bytes not a sandbox crash).
- Fix: snapshot `[rbp-64]` **and** reload extra pointer each bytes iteration (same as 7c7c8ea).
- Proof: `F11_NativeExtendSnapshotsSourceLength` asserts both sequences; Unicorn gen1 hello hash equals host and runs `hello from stage`.
- Residual: Windows OS gen1/gen2 hashes after this push.

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
