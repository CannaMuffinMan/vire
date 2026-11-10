# Native selfhost checklist

Standing on its own means gen1 (native PE of `compile-native.vire`) compiles `compile-native.vire` plus a guest to gen2, and gen1.hex equals gen2.hex. Hello hex equality is not that proof. VC bytecode selfhost (`compiler.vire` → stage2 `.vc`) is a different loop. It does not replace native PE.

## Status at PR42 `3d9fc58c80629f1fd6ac11b3576831f5c869087d`

Windows CI job `native-selfhost-windows` (`tools/native-selfhost-handoff.ps1`), `continue-on-error` off:

1. Host interprets `compile-native.vire` and emits gen1. Done. This step is .NET bootstrap.
2. Stage `data/src/` copies of `asm`, `pe`, `rt`, `rt-more`. Done in the handoff script.
3. `gen1.exe` compiles `guest-hello.vire`. stdout `hello from stage`, exit 0. Done on Windows.
4. `gen1.exe` compiles `data/compile-native.vire` to gen2. SHA-256 match `48f12268ace6f0e5ebb58f07bff090ec91bc78058342515cf56368e2e768f815`. Done on Windows.
5. Caps stay 5e6 steps, list 100000 on the host, 32MB native arena. Unchanged.
6. Clean-machine native use after gen1 exists: `docs/native-clean-machine.md` and job `prove` in `.github/workflows/native-clean-machine.yml`. That job must not call `dotnet` for hello or gen2.

Linux Unicorn and `selfhost` / `selfhost-windows` VC checks are still useful. They are not S1–S6.

## Bootstrap recipe (Windows)

```text
set VIRE_BUDGET=5000000
dotnet build vire.csproj -c Release
pwsh -File tools/native-selfhost-handoff.ps1
```

Or `pwsh -File tools/native-clean-machine.ps1 -Phase bootstrap`, which calls that handoff.

Hex to exe is PowerShell byte conversion. Do not add gcc or clang as a Vire compile dependency.

## Native prove recipe

```text
pwsh -File tools/native-clean-machine.ps1 -Phase prove
```

Fails if `data/gen1.exe` is missing. Does not run `dotnet exec` for those steps.

## This file vs other lanes

Native path/frame/IAT evidence stays the security lane. Host compile performance (local TIMEOUT vs CI) stays the perf lane. Do not raise timeouts or caps here.
