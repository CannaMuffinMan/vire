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

`GetFileInformationByHandle` `nlink` at offset 40. Write opens `OPEN_EXISTING` first. Unicorn `nlink2` refused and left `SECRET`. Then `CREATE_ALWAYS` only after a clean nlink check so a normal file still truncates. Windows hardlink execute **blocked** (same recipe).

### F5. Path index and length clobbered (this review)

`mov al, [rcx+rax]` replaced the index with `'/'` (47). A later `movzx edx` on the scan overwrote `rdx` (the length), so the scan walked into the terminating NUL and refused legal long names. Proven by CPU probe and Unicorn. **Fixed** with `movzx r8d` in the scan (length stays in `rdx`) and `movzx edx` in the walk (length already on the stack). Unicorn long name GFA is `data` then the full leaf. `data/../outside.txt` fails closed with `CREATE []`.

### F6. `CREATE_ALWAYS` truncated before nlink (this review)

Disposition 2 emptied a hardlink, then the refuse path ran. Proven in Unicorn. **Fixed** by `OPEN_EXISTING` inspect, refuse without truncate, `CREATE_ALWAYS` only after nlink==1.

## Overlap (do not concatenate drafts)

| PR | Head (as of 2026-11-07 fetch) | Hot files vs this branch | Resolution |
|---|---|---|---|
| 31 intern | `18c2623` | `src/rt.vire`, `src/rt-more.vire` | Keep intern/`heap_cell` on 31. This branch adds `frame_base` and path checks only. |
| 32 gap/lstat | `3550d5c` | `VirePaths.cs`, `src/pe.vire`, `src/rt-more.vire` | Same Linux `lstat` idea. This walk covers **parents** and `rt_read`. Do not import GAP-CLOSURE.md. |
| 33 emitList | `3f9e0cd` | `src/rt.vire` `emitList` | Untouched here. Performance agent owns 33/34. |
| 34 hexOf | `7cbc63c` (base 33) | none expected | Do not pull. |

CI `test` 8 failures on this PR match base Linux Windows-only foreign/Android/APK/toolchain/headless contracts. Not introduced here. `native-windows` **PASS hello** on GitHub (real `hello.exe`). That is not the junction/hardlink recipe.

## Verification on this Linux VM

- PathSsrf + NativePathSafety: 20 passed.
- `bash tools/native-sec-emu-check.sh`: hello stdout, long-name GFA `data`, parent reparse, nlink2 keeps `SECRET`, depth 65, `data/../outside.txt` refused, `data/linkdir` symlink refused. Unicorn 2.1.4. Heap mapping `0x2000000`.
- Windows junction/hardlink: **blocked**. Recipe `tools/native-sec-windows.ps1`.
- Self-host `files stay in data or site` on CI: pre-existing vs compiler.vire. Not treated as this patch. Hours-long selfhost not run.

## Gates

- `/poteto-mode`: smallest fail-closed emit fixes after proven probes.
- `/setup-pstack`: **blocked** (interactive).
- `/interrogate`: two Grok adversaries, not four (Opus weekly cap). Findings F5 and F6 survived reruns and were fixed. Remaining "emu follows leaf symlink" was an emu `stat` vs `lstat` bug and was fixed in the stub.
- `/blast-radius`: host hardlink test; Unicorn nlink2 does not `CREATE_ALWAYS`; hello still prints.

## Caps

32MB arena, `ProgramStepCap` 5_000_000, list 100_000: unchanged.
