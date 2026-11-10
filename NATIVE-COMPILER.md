# About the native Windows compiler

Vire has three runtimes. Do not collapse them.

| Runtime | How you start it | What it produces | Where it runs |
| --- | --- | --- | --- |
| C# interpreter | `dotnet exec …/vire.dll` or `dotnet run` | Direct eval of `.vire` | Linux, macOS, Windows |
| Single-file publish | `dotnet publish -p:PublishSingleFile=true` | A CoreCLR `vire` / `vire.exe` | Same OSes, still .NET |
| VC bytecode | `compiler.vire` sealed as `VIRE-VC2` | `.vc` | Same OSes, needs a seal key |
| Native PE | `compile-native.vire` plus `src/asm.vire`, `src/pe.vire`, `src/rt.vire`, `src/rt-more.vire` | Windows x64 PE via hex | Execute on Windows. Linux Unicorn stubs kernel32 and is not the Windows gate. |

The native compiler is the last row. It is not the interpreter. It is not single-file publish.

## Bootstrap vs native use

Bootstrap still uses .NET. On Windows CI that command is:

```text
dotnet exec bin\Release\net10.0\vire.dll compile-native.vire data\compile-native.vire data\gen1.hex
```

PowerShell then turns hex into `data\gen1.exe`. That conversion is not gcc, clang, or MinGW.

Native use is `gen1.exe` compiling a guest and compiling `data\compile-native.vire` again. On PR42 `3d9fc58c80629f1fd6ac11b3576831f5c869087d`, Windows job `native-selfhost-windows` printed equal SHA-256 `48f12268ace6f0e5ebb58f07bff090ec91bc78058342515cf56368e2e768f815` and ran gen1 hello with `hello from stage`, exit 0.

A PATH without `dotnet.exe` is not enough to claim ".NET is gone." Inspect the PE import table and the processes `gen1.exe` starts. `docs/native-clean-machine.md` is that recipe. Caps stay 32MB `VirtualAlloc` arena, host list 100000, `ProgramStepCap` 5,000,000. Do not raise them. Host compile of a file named `compile-native.vire` that contains `emitU8` uses `CompilerStepCap` 50,000,000 and ignores `VIRE_BUDGET`. The PE ignores `VIRE_BUDGET` too. Native loops stop at 2,000,000 ticks.

Root `compile-native.vire` uses `src/` on the host. The guest copy must be `data/compile-native.vire` so `use "src/pe.vire"` reads `data/src/pe.vire`. Those pairs must match or gen1 and gen2 disagree. Equal SHA-256 is of the hex files.

## What native PE cannot do yet

The IAT is `kernel32.dll` only (stdio, VirtualAlloc, files, command line, crash filter, file pointer). There is no socket, TLS, `listen`, `fetch`, `seal`, WinForms, or `foreign`/`build`. Programs that need those stay on the interpreter.

## History that is no longer the gate

Older notes in this file described a 32MB self-compile access violation and a 256MB stub mismatch. That was before the PR42 Windows equal-hash run. Keep the old narrative only as a warning: do not raise the arena to paper over allocator bugs. The current gate is real Windows `native-selfhost-windows` plus `native-clean-machine` prove, not Unicorn and not VC `selfhost ok`.
