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

- Windows `native-windows` job `129796755075` (`5b39c9a`): F4/F5/F6/walk recipe ok. `native-selfhost-windows` job `129796754998`: gen1=gen2 `7fad880322a59feaa9542f51557939bdd5eb7b65070ea8f1c37e50f6509be9cb`.
- `tools/native-sec-emu-check.sh` is on the Linux `selfhost` job: wrap `[0, 0, 1]`, trailing-dot refuse, walk-open-race fail-before `7c7c8ea` / pass-after HEAD.
- Caps 32MB / list 100000 / 5M, sandbox, and Defender are unchanged. PR 42 stays draft.

## Gates

- `/poteto-mode`: smallest fail-closed emit fixes after proven probes.
- `/setup-pstack`: **blocked** (interactive).
- `/interrogate`: two Grok adversaries, not four (Opus weekly cap). Findings F5 and F6 survived reruns and were fixed. Remaining "emu follows leaf symlink" was an emu `stat` vs `lstat` bug and was fixed in the stub.
- `/blast-radius`: host hardlink test; Unicorn nlink2 does not `CREATE_ALWAYS`; write uses SetEndOfFile; hello still prints.

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

