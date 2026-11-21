# rt-core dead-code lane (Nov 21 2026)

Lane paths: `src/rt.vire`, `src/rt-more.vire`, `src/rt-json.vire`, `src/rt-schema.vire`, `src/rt-linux.vire`, `src/pe.vire`, `src/elf.vire`, `src/asm.vire`, `compiler.vire`, `compile-native.vire`.

Whole-repo grep (src, tools, tests, checks, .github, docs, `*.csproj`, `*.cs`, scripts, data staging lists) before each deletion.

## Removals

| path | symbol | why dead | evidence |
|---|---|---|---|
| `src/asm.vire` | `hexPairs` | Superseded 256-entry list. `hexOf` slices `hexTable`. Never called. | `rg hexPairs` → define only in `src/asm.vire` (+ staged `data/src/asm.vire`, stale `COMPILE-PERF.md` text). `HexOfTests` uses `hexOf` only. |
| `src/rt-linux.vire` | `emitLinuxThunks` | Never called except by `emitLinuxNetThunks`. ELF IAT pokes `stub_*` in `finishElfImage`. | `rg emitLinuxThunks` → define + one call in this file and `data/src` copy. |
| `src/rt-linux.vire` | `emitLinuxNetThunks` | Never called. `openElfNetImage` / `openElfTlsImage` use `emitLinuxNetStubs`. | `rg emitLinuxNetThunks` → define only (+ `data/src` copy). |
| `src/rt-json.vire` | `json_need` | Unreachable. Parser uses `json_here` (peek, no consume). | `rg json_need` → define only. |
| `compiler.vire` | `assemble` | Superseded by `compileUnit` (`use`/`need`/`deps.lock`). `main` never calls it. | `rg 'define assemble'` → this define only. Landing HTML has English word "assemble", not this function. |

`emitIatThunk` stays: `src/rt-tls.vire` (outside this lane) still calls it.

`openPeTlsImage` stays: `TlsTests.cs` asserts the name.

`buildExe` stays: `probe-build-exe.vire` (outside) calls it.

`schema_parse` stays: finished public `parse` + `schema_check` wrapper. Guests still call the two steps; not deleted.

## Placeholders (`TODO(VIRE-FINISH-NOW)`)

| file | symbol | what's missing | priority |
|---|---|---|---|
| `compile-native.vire` | tokenize (`.` after digits) | Native lexer rejects fractional literals (`that number is not ready`). Host `number` exists; native emit has no float path. | medium |

No other unfinished-but-intended feature in these files was reduced to a stub. Working code was not replaced with TODOs.

## Cross-lane notes

- `data/src/asm.vire`, `data/src/rt-linux.vire`, `data/compile-native.vire`: staged copies. This lane does not edit `data/`. `CompilerStageTests` / `tools/stage-compiler-src.sh` recopy from `src/`.
- `COMPILE-PERF.md` still says `hexOf` indexes `hexPairs`. Docs lane should retarget that sentence to `hexTable`.
- `src/rt-tls.vire` still uses `emitIatThunk`. Do not delete that helper from `rt-linux.vire`.
- `probe-build-exe.vire` still uses `buildExe`.
- Duplicate `data/src/*` trees look like restage artifacts, not extra dead functions in this lane.
- `tests/native/fixtures/gc-tagged-walk/compile-native.vire` is a frozen fixture (outside this lane).
