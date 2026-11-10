# Integration of compiler speed onto PR #38

PR #38 (`e0d70a0`, `cursor/native-runtime-32mb-0b9c`) is unchanged. This branch is `cursor/integrate-perf-38-0258`.

Security hunks kept: `GetFileAttributesA` / `GetFileInformationByHandle`, `frame_base`, `heap_cell`, `intern_tab`, Linux `lstat` hardlinks.

Compiler hunks kept: `emitList` -> `extend`, `hexOf` in-range, `buildExe` list concat, `rt_extend`, host `extend`.

## Source staging

Native `read` still only opens `data/` and `site/`. `tools/stage-compiler-src.sh` copies `compile-native.vire` and `src/*.vire` into `data/` / `data/src/` without widening that policy. Hashes must match.

## Measured on this Linux VM (Release, `VIRE_BUDGET` unset)

| Job | Wall | Notes |
|---|---|---|
| host compile hello | 1.125–1.276s | not a PR #36 microprobe claim |
| host compile `data/staged-use.vire` (`use src/asm.vire` under `data/`) | 2.994s | staging works |
| host compile `data/compile-native.vire` as guest | 66.002s | compiler-as-guest hex emitted |
| Unicorn `data/p-hello.hex` | EXIT 0, `hello from stage` | not Win32, not gen1/gen2 |

Hello hex SHA `747f6e1d…` (44032 chars). Different from pre-intern trees because PR #38 runtime is in the image.

## Tests

42 passed: CompilerStage, NativeExtend, NativePath, NativeArena, NativePe, Extend, PathSsrf, EmitU8, HexOf, BudgetCap.

## Unproven

Real Win32 PE. gen1.hex == gen2.hex. Hours-long proof script. See `LOCAL-CLI-HANDOFF.md`.
