# Vire gap-closure plan

This is an engineering plan for practical cross-platform use and interoperability with existing codebases. It is not a claim that Vire compiles C#, Rust, or JavaScript, and it is not a claim that native PE self-host is done.

Evidence is from this tree at branch `native-compiler` (`0f758e702771ed3276ee553a76c7a86cc83846dd` at plan start) plus measurements recorded under Verification. PR #31 (intern / `r15` heap) stays a separate review.

## Four different jobs

| Job | What it means | Status in this repo |
|---|---|---|
| Run Vire on a host | Interpreter and `compiler.vire` bytecode on that OS | Linux x64 and Windows x64 are the CI hosts. macOS is documented for publish, not exercised. |
| Generate a native target | `compile-native.vire` emits a Windows x64 PE | Windows-only ABI. No ELF or Mach-O backend. Linux can emit the PE hex. Running it needs Windows or an emulator. |
| Embed or call another language | `foreign` loads a DLL export | Windows only. Linux throws `could not open that dll`. `build` C / Android / driver need Windows MSVC, Android NDK paths, or `aapt.exe`. |
| Migrate an existing project | Rewrite or wrap a C#/Rust/JS tree as Vire | Not a product. Vire can sit beside other files. It does not translate them. |

## Done means

A gap is closed when a named command fails loud on the wrong behavior and passes on the intended one, without raising step/arena/list caps, without widening path/network rights, and without treating a skip as a pass.

## Gaps

### G1. Linux CI lies about Windows-only tools

**Finding.** `dotnet test` on Ubuntu runs `ForeignTests`, `ForeignArgsTests`, `ForeignTextTests`, `DriverImageTests`, `AndroidSoTests`, `ApkTests`, `ToolchainTests`. They throw `FileNotFoundException` (`kernel32.dll`, `cmd.exe`) or `VireError` (`the C compiler is not installed`, `aapt is not installed`). `HeadlessWindowTests` looks for ASCII `Write Vire - done` while `work.vire` prints `Write Vire — done`.

**Done.** On non-Windows, those tests assert the documented refuse/missing-tool message. On Windows they keep the real DLL/PE/APK assertions. Headless matches the sample bytes.

**Depends on.** Nothing.

### G2. No portable host harness in CI

**Finding.** `tools/samples-check.ps1` covers hello, deps, count, term, vault and names window/network skips as skips. It is not in `.github/workflows/check.yml`. Ubuntu CI has no bash twin. Interpreter vs `compiler.vire` for a tiny program is only in xUnit `DualMode`.

**Done.** `tools/portable-check.sh` runs those interpreter checks, compiles `samples/hello.vire` with `compiler.vire`, reruns the `.vc`, asserts identical stdout, prints wall times, and is a `check.yml` job. Skips stay labeled skip.

**Depends on.** G1 if the same job also runs `dotnet test`.

### G3. Host vs native path sandbox

**Finding.** Host `VirePaths.RefuseReparse` refuses symlinks. Native `rt_check_path` only checks a `data/` or `site/` prefix and literal `..` / `:`. `CreateFileA` then follows a `data/` symlink (shown under Unicorn on PR #31). Deep `r15` frame chains can walk into the value stack at heap+64KB. That overlap is older than intern.

**Done on this branch (emit + host).** Native `rt_check_path` calls `GetFileAttributesA` and refuses `FILE_ATTRIBUTE_REPARSE_POINT` (0x400) on the leaf path. `PortabilityMatrixTests.NativePathCheckCallsGetFileAttributesA` locks the import names. Host `VirePaths.LinkCount` uses `lstat` on Linux so `PathSsrfTests.HardLinkCannotRewriteDepsLock` refuses `nlink>1` (this VM: pass after the P/Invoke). Caps are unchanged.

**Still open.** Native PE execute of the reparse bit (Windows or Unicorn). Native does not walk parent directories, so a `data/` directory symlink can still be followed by `CreateFileA`. Native has no `nlink` check. Deep frame cursor vs value stack at heap+64KB. Native PE self-host SHA-256. Do not raise 32MB to hide those.

**Depends on.** Do not treat emit-only GFA as a proven Windows run.

### G4. Compile-time bottleneck

**Finding.** `NATIVE-COMPILER.md` records ~60 minutes to host-compile `compile-native.vire` itself. Host-compiling a tiny program through that same compiler is seconds (measured). `compiler.vire` stage-1/2/3 is the bytecode self-host path, already in CI, and is not native PE.

**Measured on this Linux x86_64 VM** (`bash tools/portable-check.sh`, Release `vire.dll`, 2026-11-06). Wall times from `time.perf_counter()`. One run, not a claim of speedup.

| Work | Wall |
|---|---|
| interp `samples/hello.vire` | 0.054s |
| interp `samples/deps-demo.vire` | 0.064s |
| interp `count.vire` | 0.054s |
| interp `term.vire` | 0.060s |
| interp `vault.vire` | 0.066s |
| `compiler.vire` → hello `.vc` | 0.080s |
| `compile-native.vire` → hello `.hex` | 2.604s |

Bytecode hello stdout matched the interpreter. Native hex was emitted. PE execute was not run here.

**Still open.** Cutting native compiler allocations (PR #31 intern) and fitting self-compile in 32MB. Hours-long host rebuild of the compiler is stopped. `NATIVE-COMPILER.md` still records ~60 minutes for host-compiling `compile-native.vire` itself. That number was not remeasured this run.

### G5. Backends and ABIs

**Finding.** One native backend: Windows x64 PE, kernel32 imports, 32MB `VirtualAlloc` bump. Host publish RIDs in README: `linux-x64`, `linux-arm64`, `osx-x64`, `osx-arm64`, `win-x64`. CI `publish` job builds `win-x64` and `linux-x64` only, on `ubuntu-latest`. Docker is linux-x64.

**Done.** Matrix in this file and `PortabilityMatrixTests` that fail if CI starts claiming osx/native-linux without a job.

**Product decision (Canna).** Whether to add macOS runners, cross-publish osx artifacts as unverified, or drop osx from README. Whether a Linux ELF native backend is wanted at all.

### G6. Runtime / library parity

**Finding.** Interpreter and `CompiledMachine` share DualMode conformance for listed grammar files. Native PE is a separate runtime (`src/rt*.vire`). `foreign`, windows `show`, APK, and driver are host Windows. `listen` is loopback by default.

**Done.** Portable check plus DualMode remain the bytecode parity gate. Native smoke stays Windows.

### G7. Packages and build tooling

**Finding.** `need` / `deps.lock` / hash pin exist (`DepsLockTests`). `vire-project.ps1` and index scripts are PowerShell. No `cargo`-style lock for mixing Vire into a Node or Rust tree.

**Done for this run.** `samples/deps-demo.vire` stays in portable-check as the representative “Vire beside other files” fixture.

**Product decision.** A portable `vire project` CLI vs keeping PowerShell.

### G8. Interoperability boundary

**Finding.** `foreign` is LoadLibraryExW of a file inside the program folder, not of `C:\Windows`. That is in-process native code with the host’s full rights. It is not a sandbox. Linux has no equivalent.

**Done.** Tests assert Linux refuse. GUIDE/SECURITY already put desktop and native outside Phase 0 guarantees.

**Product decision.** Whether Linux should `dlopen` a `.so` the same way. Default here is no, until Canna says yes, because it expands process rights.

### G9. Diagnostics

**Finding.** Native failures are `ExitProcess` with a short message. No PDB. Interpreter errors have line/col. `VIRE_DEBUG=1` prints stacks.

**Still open.** Native traces. Not this run.

### G10. Release / distribution

**Finding.** No git binaries. Actions upload `vire.exe` / `vire`. Docker image runs `tests.vire`.

**Still open.** Signed releases, macOS notarization. Product decision.

## Security blockers that stay explicit

1. Native `data/` symlink follow, until G3’s attribute check is in the image and proven on Windows or Unicorn.
2. Native frame cursor vs value stack overlap.
3. PR #31 intern/`r15` alloc limit. Separate PR. Do not mix into this one.
4. Caps stay 5,000,000 steps, 32MB native arena, 2,000,000 list items.

## Priority order

1. G1 Linux test contracts (CI truth).
2. G2 portable harness.
3. G3 native reparse refuse (emit + tests).
4. G4 measured times in the harness.
5. Record G5–G10 as decisions or later work.

## Acceptance commands

```text
dotnet test tests/Vire.Tests/Vire.Tests.csproj -c Release --nologo
bash tools/portable-check.sh
bash tools/native-arena-check.sh   # if present on the branch
```

Windows only, not this VM:

```text
pwsh -File tools/native-smoke.ps1
pwsh -File tools/native-selfhost-proof.ps1
```

## What Canna still decides

- Merge or reject PR #31 independently of this plan.
- macOS CI vs README-only osx RIDs.
- Linux `dlopen` foreign, or keep refuse.
- ELF native backend, or keep PE-only.
- Who may `POST /block` (already open in CHANGELOG).

## Verification this run

Commands (budget unset so `BudgetCapTests` sees the default 5,000,000):

```text
unset VIRE_BUDGET
dotnet test tests/Vire.Tests/Vire.Tests.csproj -c Release --nologo
bash tools/portable-check.sh
```

Results on this VM:

- `dotnet test` Release: 126 passed, 0 failed, 3 m 3 s.
- `portable-check.sh`: ok. Times in G4. Skips labeled for `work.vire`, `board.vire`, `serve.vire`, `optional/live.vire`.
- Native PE self-host and Unicorn PE execute: not run.
- Interrogate/how subagents: not spawned (one cloud agent).

## What this PR does not do

- Does not merge or rebase PR #31.
- Does not add ELF, Mach-O, macOS CI, or Linux `dlopen`.
- Does not raise caps or loosen path/network rules.
- Does not claim Vire compiles other languages or that native self-host is proven.
