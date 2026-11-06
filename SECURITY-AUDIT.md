# Security audit (2026-11-06)

Dedicated security lane against `native-compiler` at `0f758e7`. Not a CVE filing. No live targets.

## Tracks

**Dependency CVEs** are only those verified against resolved versions and an advisory database.

**First-party issues** do not get invented CVE IDs.

## Dependency inventory

Runtime product (`vire.csproj`) has no PackageReference. It is a .NET 10 executable (`net10.0`, SDK pin `10.0.403` in `global.json`).

Test-only packages (`tests/Vire.Tests/Vire.Tests.csproj`):

- `Microsoft.NET.Test.Sdk` 17.14.1
- `xunit` 2.9.3
- `xunit.runner.visualstudio` 3.1.4

`dotnet list package --vulnerable --include-transitive` on this VM (SDK 10.0.403, nuget.org) reported no vulnerable packages for `vire.csproj` (no PackageReference) and for `Vire.Tests` including transitives:

- `Microsoft.CodeCoverage` 17.14.1
- `Microsoft.TestPlatform.ObjectModel` 17.14.1
- `Microsoft.TestPlatform.TestHost` 17.14.1
- `Newtonsoft.Json` 13.0.3
- `xunit.abstractions` 2.0.3
- `xunit.analyzers` 1.18.0
- `xunit.assert` 2.9.3
- `xunit.core` 2.9.3
- `xunit.extensibility.core` 2.9.3
- `xunit.extensibility.execution` 2.9.3

That is not a clean bill for the shared .NET 10 runtime on every OS. It is the NuGet advisory feed for the restored packages. No package bump in this PR.

.NET 10 servicing after 10.0.403 is outside this change. Hosting/runtime CVEs need an SDK bump Canna chooses, not a silent `global.json` edit.

## First-party findings

### F1. Linux host hardlink bypass of `deps.lock` / sandbox files

- **Surface:** interpreter `VirePaths.LinkCount` on Linux. Version: `native-compiler` `0f758e7`.
- **Evidence:** `LinkCount` returned 1 on non-Windows, so `RefuseReparse` never saw `nlink > 1`. `PathSsrfTests.HardLinkCannotRewriteDepsLock` returned on Linux before this change.
- **Prerequisites:** attacker can create a hardlink from `data/` to `deps.lock` or another file in the program folder (same filesystem).
- **Impact:** `write` through the link rewrites the target. First-party issue, no CVE.
- **Status:** **fixed** on this branch with `lstat` `st_nlink`. Regression: `HardLinkCannotRewriteDepsLock` now runs `ln` on Linux.
- **Overlap:** PR 32 drafts the same host `lstat`. This branch does not take PR 32's gap plan, workflow, or foreign-test Linux contracts.

### F2. Native `read`/`write` follow leaf and parent reparse points

- **Surface:** native PE `rt_read`, `rt_check_path`, `CreateFileA`. Host already refuses via `GetFullPath` plus `ReparsePoint`.
- **Evidence:** native path scan only rejects `..`, `:`, `\`, and NUL in the string. `rt_read` opened with `CreateFileA` and `FILE_ATTRIBUTE_NORMAL` (128) and never called `rt_check_path`. Parent directory junctions are followed by Win32.
- **Prerequisites:** Windows native image, symlink or junction under `data/` or `site/` pointing outside the tree, and a program that `read`/`write`s that path.
- **Impact:** sandbox escape for native programs. First-party. **Windows PE execute unproven on this Linux VM.**
- **Status:** **fixed in source** (fail closed). Prefix `GetFileAttributesA` walk, `FILE_FLAG_OPEN_REPARSE_POINT`, `GetFileInformationByHandle` reparse and `nlink` checks, `rt_read` calls `rt_check_path`. Source tests in `NativePathSafetyTests`. PE run **unproven**.

### F3. Native frame chain vs value stack (heap+64KB)

- **Surface:** `rt_save_frame` vs entry stub `r13 = heap+65536`. Native has no `MaxCalls`.
- **Evidence:** `rt_save_frame` was `mov [r15], r14; add r15, 8` with no bound. Interpreter `Budget.MaxCalls` is 64.
- **Prerequisites:** native PE, recursion or call chain deeper than 8192 frames to reach 64KB, or any depth past 64 to mismatch host.
- **Impact:** overwrite of the value stack / memory corruption. First-party.
- **Status:** **fixed in source** at 64 frames (512 bytes from `frame_base`), matching host depth. Fail closed with `definitions called too deeply`. PE run **unproven**. Independent of PR 31 intern/`heap_cell` work. Overlaps `src/rt.vire` with PR 31.

### F4. Native hardlinks

Covered by F2 handle `nlink` check. **Unproven on Windows.**

## Draft PRs inspected (not imported)

- PR 31 intern RIP-relative / `heap_cell`. Performance/native-arena. Do not duplicate as a security finding. Hot file `src/rt.vire` / `src/rt-more.vire`.
- PR 32 Linux `lstat` + leaf GFA only. This branch walks **parents** and adds handle `nlink`, and wires `rt_read`.
- PR 33 `emitList` speed. No security import. `src/rt.vire` `emitList` left unchanged.

## Deferred / not claimed

- macOS `nlink` (still returns 1).
- Native PE execute, Unicorn, self-host fixed-point.
- Raising 32MB arena, 5M steps, or list cap 100000.
- Public CVE submission.
- FCG product policy (`POST /block`).
- `/interrogate` four-model army (blocked: scoped review). Blast radius proven by the Linux hardlink test, not by a panel.

## Caps

32MB arena, `ProgramStepCap` 5_000_000, list cap 100_000: unchanged.
