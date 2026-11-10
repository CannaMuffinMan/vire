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

### F4. Native hardlinks

`GetFileInformationByHandle` `nlink` at offset 40. Write opens `OPEN_EXISTING` first. Unicorn `nlink2` refused and left `SECRET`. Truncation is `SetFilePointerEx` plus `SetEndOfFile` on that same handle. There is no `CREATE_ALWAYS` after the nlink check.

### F5. Path index and length clobbered (this review)

`mov al, [rcx+rax]` replaced the index with `'/'` (47). A later `movzx edx` on the scan overwrote `rdx` (the length), so the scan walked into the terminating NUL and refused legal long names. Proven by CPU probe and Unicorn. **Fixed** with `movzx r8d` in the scan (length stays in `rdx`) and `movzx edx` in the walk (length already on the stack). Unicorn long name GFA is `data` then the full leaf. `data/../outside.txt` fails closed with `CREATE []`.

### F6. `CREATE_ALWAYS` truncated before nlink (this review)

Disposition 2 emptied a hardlink, then the refuse path ran. Proven in Unicorn. **Fixed** by `OPEN_EXISTING` inspect, refuse without truncate, then `SetEndOfFile` on the validated handle. Write emit does not use `CREATE_ALWAYS`.

## Overlap (do not concatenate drafts)

| PR | Head (as of 2026-11-07 fetch) | Hot files vs this branch | Resolution |
|---|---|---|---|
| 31 intern | `18c2623` | `src/rt.vire`, `src/rt-more.vire` | Ported intern/`heap_cell` onto this integration draft. PR31 branch left at `18c2623`. |
| 32 gap/lstat | `3550d5c` | `VirePaths.cs`, `src/pe.vire`, `src/rt-more.vire` | Same Linux `lstat` idea. This walk covers **parents** and `rt_read`. Do not import GAP-CLOSURE.md. |
| 33 emitList | `3f9e0cd` | `src/rt.vire` `emitList` | Untouched here. Performance agent owns 33/34. |
| 34 hexOf | `7cbc63c` (base 33) | none expected | Do not pull. |

CI `test` 8 failures on this PR match base Linux Windows-only foreign/Android/APK/toolchain/headless contracts. Not introduced here. `native-windows` **PASS hello** on GitHub (real `hello.exe`). That is not the junction/hardlink recipe.

## Verification on this Linux VM

- PathSsrf + NativePathSafety + NativeArena + NativePeEmit: Native* filter 11 passed after intern port. Full suite still has the same Linux Windows-only foreign/Android/APK/toolchain/headless failures as base.
- `bash tools/native-sec-emu-check.sh`: hello stdout, long-name GFA `data`, parent reparse, nlink2 keeps `SECRET`, depth 65, `data/../outside.txt` refused, `data/linkdir` symlink refused. Unicorn 2.1.4. Heap mapping `0x2000000`.
- `bash tools/native-pe-emu-check.sh`: intern-chars prints `A`/`b`/`9`/`Ab9`, hello-stage prints `hello from stage`, HEAP_SIZE `0x2000000`. intern-chars HEAP_BUMP `0x500a0` (value stack 0x50000 plus ~160B). Stubbed kernel32, not OS proof.
- Host `dotnet compile-native` medians (3 runs, python `perf_counter`, no GNU time): hello.vire 2.551s, intern-chars.vire 2.599s. Protection path/frame/nlink still on. Intern is an alloc cut at runtime, not a compile-speed claim.
- Windows junction/hardlink: **blocked**. Recipe `tools/native-sec-windows.ps1`.
- Native fixed-point gen1→gen2 hash + hello: **not run**. `tools/native-selfhost-proof.ps1` is the bounded Windows recipe. Not wired into `check.yml`.
- Self-host `files stay in data or site` on CI: pre-existing vs compiler.vire. Not treated as this patch. Hours-long selfhost not run.

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

