# Vulnerability / finding evidence ledger

Vulnerable SHA: `7c7c8ea3dcc4030ba8714fc2330d30b67f8d6867` (merged PR40).
No CVE IDs are assigned. Items are first-party findings. Zero known vulnerabilities is an objective, not a claim of absolute safety.

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
