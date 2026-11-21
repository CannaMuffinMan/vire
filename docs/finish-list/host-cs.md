# Host C# finish list (cleanup lane)

Placeholders use `TODO(VIRE-FINISH-NOW):` exactly.

## Placeholders kept

| File | Symbol | What's missing | Priority |
| --- | --- | --- | --- |
| windows/vire.windows.csproj | Compile ItemGroup | WINDOWS project compiles only `Vire.cs` and `Compiled.cs`. A real Windows host build still needs the rest of the host files (`VirePaths`, `VireSeal`, `VireNet`, `VireTls`, `VireFiles`, `VireListen`, `VireWs`, `VireApk`, `VireBuild`, `VireDebug`, `VireForeign`, `VireInspect`, `VireDns`, `CompilerStage`). | high |
| Vire.cs / Compiled.cs | Builtin `serve` | Guest `serve` is a compatibility stub that throws `serve was removed; use listen`. Leave as-is unless the language drops the name. | low |
| VireApk.cs | `VireApk.Pack` | Packing works from tests/host C# only; there is no guest builtin named `apk`. Add a builtin only if product still wants APK from `.vire` (NATIVE-COMPILER.md currently treats APK as a sidetrack). | low |

## Cross-lane notes (untouched)

- `src/`, `data/src/`, `compile-native.vire`, `tests/`, `.github/`: not this lane. Duplicate HTTP reason strings live in native `parkMsg` tables; keep `VireListen.ReasonOf` in lockstep if those lanes change codes.
- `StatusOf` can emit 405/307/204/429 via JSON/`FcgbcStatus`, but `ReasonOf` has no 204/307/405/429 phrases (unknown codes fall through to `"OK"`). Do not change `ReasonOf` here without matching native tables.
- `Vire.cs` and `Compiled.cs` still duplicate builtin dispatch. Merging them is a compiler/runtime lane, not dead-code deletion.
- `deps/`, `api/`, `optional/`, `systems/` are live samples/packages, not unused host C#.
- Sandbox paths (`VirePaths` / `VireSeal` / `VireForeign`) were only trimmed of unused overloads; behavior of remaining methods is unchanged.
