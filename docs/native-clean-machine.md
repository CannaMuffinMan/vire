# How to prove gen1.exe on a clean Windows PATH

Use this recipe after an already-built `gen1.exe` exists. It is not a way to skip the .NET bootstrap.

## What this proves

`gen1.exe` is a Windows x64 PE emitted by the native compiler sources. After bootstrap, that PE compiles `guest-hello.vire` and rebuilds `compile-native.vire` without launching `dotnet`, `gcc`, `clang`, MinGW, or Java. Equal SHA-256 of `gen1.hex` and `gen2.hex` is the full compiler fixed point, not a hello-only check.

This does not prove that GitHub's `windows-latest` image lacks a .NET SDK. The image still has one, and it also has Strawberry `gcc`. The prove job does not run `setup-dotnet`. Isolate PATH is only `System32`, `Windows`, and PowerShell. The script inspects the PE import table and watches child processes.

## Trust chain

1. Source SHA of this tree.
2. Bootstrap: `dotnet exec bin/Release/net10.0/vire.dll compile-native.vire data/compile-native.vire data/gen1.hex`. That step is the C# interpreter. It is not the native compiler.
3. PowerShell hex-to-bytes writes `data/gen1.exe`. That conversion is allowed. It is not gcc, clang, or `dotnet publish`.
4. Native: `gen1.exe data/guest-hello.vire …` and `gen1.exe data/compile-native.vire data/clean-gen2.hex`.
5. SHA-256 of `gen1.hex` equals SHA-256 of `clean-gen2.hex`.

Pinned baseline on PR42 `3d9fc58c80629f1fd6ac11b3576831f5c869087d`: equal hash `48f12268ace6f0e5ebb58f07bff090ec91bc78058342515cf56368e2e768f815` of `gen1.hex` and `gen2.hex`. A later equal pair may differ from that string if compiler bytes change. Equality of the two hex files still has to hold. The `.exe` is those hex bytes after conversion.

## What you need

- Windows x64. Linux Unicorn is not this gate. Do not use a personal PC for the official proof. Use GitHub Actions job `prove` in `.github/workflows/native-clean-machine.yml`.
- Bootstrap outputs: `data/gen1.exe`, `data/gen1.hex`, `data/compile-native.vire`, `data/src/*.vire`.
- Caps stay 32MB arena, list 100000, `VIRE_BUDGET` 5000000. Do not raise them. Do not add Defender exclusions.

## Bootstrap (explicit .NET phase)

From the repo root, with the .NET 10 SDK:

```text
dotnet build vire.csproj -c Release
pwsh -File tools/native-clean-machine.ps1 -Phase bootstrap
```

That calls `tools/native-selfhost-handoff.ps1`. Expect `native selfhost handoff ok` and equal `gen1_sha256` / `gen2_sha256`.

A published single-file `vire.exe` from `dotnet publish` is still CoreCLR. Do not treat it as `gen1.exe`.

## Prove (no foreign compiler)

```text
pwsh -File tools/native-clean-machine.ps1 -Phase prove
```

The script fails if `data/gen1.exe` is missing. It does not call `dotnet` to fill that gap.

Expected log lines include:

- `pe_imports_dlls kernel32.dll`
- `isolated_has_dotnet=absent` (and the same for gcc, clang, cl, javac, java, mingw32-make)
- `step_gen1_hello_file` pointing at `data\gen1.exe`
- stdout `compiled` then `hello from stage`
- `gen1_sha256` equal to `gen2_sha256`
- `native clean machine prove ok`

`continue-on-error` stays off. A hash mismatch fails the job.

## OS libraries

`src/pe.vire` `openImage` writes one import DLL, `kernel32.dll`, and these names:

GetStdHandle, WriteFile, ExitProcess, VirtualAlloc, CreateFileA, ReadFile, GetFileSize, CloseHandle, GetCommandLineA, GetFileAttributesA, GetFileInformationByHandle, SetUnhandledExceptionFilter, AddVectoredExceptionHandler, SetFilePointerEx, SetEndOfFile.

The prove script parses the PE bytes and fails if the IAT names another DLL, a .NET host library, or a different kernel32 set. PATH edits are not that proof.

## Package

The script writes `data/native-clean-machine.zip` and `data/native-clean-machine-pkg/MANIFEST.txt`. CI uploads them as artifacts. Do not commit `*.exe` or `*.hex`.

The zip is a relocatable tree that matches how native `use` resolves. Extract it and keep that folder as the working directory:

- `gen1.exe` at the root
- `data/compile-native.vire`
- `data/src/asm.vire`, `pe.vire`, `rt.vire`, `rt-more.vire`
- `data/guest-hello.vire`
- `data/gen1.hex` and `data/gen2.hex` (the equal-hash proof is those hex files)
- `MANIFEST.txt` and `clean-env-capture.txt`

Native `read` only allows a path that starts with `data/` or `site/`. `use "src/pe.vire"` from guest `data/compile-native.vire` becomes `data/src/pe.vire`. A zip that puts `compile-native.vire` next to `src/` at the root will not load.

From that folder:

```text
.\gen1.exe data\guest-hello.vire data\hello.hex
.\gen1.exe data\compile-native.vire data\gen2.hex
```

Turn hex into a PE with the PowerShell conversion in `tools/native-clean-machine.ps1`. That step is not gcc or `dotnet publish`. A later machine still needs Windows to run the PE.

## Gaps this recipe does not close

- Host compile of gen1 still needs .NET (S1). Removing that needs a prior trusted `gen1.exe`.
- Native PE has no `listen`, sockets, or TLS. FCG API stays on the interpreter until a later port.
- Local GrokBuild host-compile time (S7) is a different lane.
- Skills `/interrogate` and `/blast-radius` live on unmerged `origin/tooling/pstack-skills` (PR28). They are not vendored in this tree.
