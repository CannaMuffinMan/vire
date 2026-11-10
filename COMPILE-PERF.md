# Remaining host compile time after PR #33

Base is PR #33 (`3f9e0cdd13b4fad66f4c3fcc11b7d5290ecb73e9`), itself on `native-compiler` `0f758e702771ed3276ee553a76c7a86cc83846dd`. Not PR #31 or PR #32.

Windows numbers below are from local Grok Build, not rerun here. Linux numbers were measured on this VM.

## Uninstrumented profile (Linux x86_64, PR #33, Release, `VIRE_BUDGET=5000000`, 60s cap)

| Probe | Wall | Role |
|---|---|---|
| `probe-load-pe.vire` | 0.060s | parse `pe`/`asm`/`rt`/`rt-more` |
| `probe-open-image.vire` | 0.385s | parse plus `emitRuntime` |
| `probe-hexof.vire` 18944 bytes | 1.313s | `hexOf` plus building the list |
| `probe-emitlist.vire` 21000 | 0.191s | already fixed in PR #33 |
| `probe-emitu8.vire` 21000 | 1.555s | leftover per-call `emitU8` |
| compile empty guest | 2.003s | |
| compile hello guest | 2.031s | |
| compile strings guest | 2.071s | |
| compile expr guest | 2.228s | |

Guest size and strings were not the remaining Linux cost. `hexOf` was. It called `hexIndex` (text, find, number, maybe `floorDiv`) once per output byte. Same shape as the old `emitU8` loop.

## After `hexOf` in-range lookup (same VM, uninstrumented)

| Probe | Wall |
|---|---|
| `probe-hexof.vire` | 0.178s |
| compile empty | 1.130s |
| compile hello | 1.167s |
| compile strings | 1.166s |
| compile expr | 1.269s |

Hello `.hex` SHA-256 `c82fcb56dab3407745e40510e230eae29fbf5c1770fdd90124ad9985ed8a3173`, 37888 chars, same as PR #33 and the Windows report. PE execute still unproven here.

In-range whole bytes index `hexPairs` directly. Out of range and non-whole numbers still use `hexIndex` (including `72.5` -> `48`). Caps unchanged.

## Windows recipe for local Build (do not treat Linux walls as Windows)

From an isolated checkout of this branch, Release `dotnet` 10:

```text
set VIRE_BUDGET=5000000
dotnet exec bin\Release\net10.0\vire.dll probe-hexof.vire
dotnet exec bin\Release\net10.0\vire.dll compile-native.vire guest-hello.vire data\guest-hello.hex
dotnet exec bin\Release\net10.0\vire.dll compile-native.vire guest-strings.vire data\guest-strings.hex
dotnet exec bin\Release\net10.0\vire.dll compile-native.vire guest-expr.vire data\guest-expr.hex
dotnet test tests\Vire.Tests\Vire.Tests.csproj -c Release --filter "FullyQualifiedName~HexOf|FullyQualifiedName~EmitU8"
```

Time each `dotnet exec` with an external timer. Compare hello `.hex` SHA to `c82fcb56…`. Do not run `native-selfhost-proof.ps1`.

## Remaining

`openImage` / runtime emit, `buildExe` byte copy, leftover `emitU8` call sites, lexer on huge guests. Host bulk-append builtin is still later. Native PE run and gen1/gen2 fixed-point unproven. Native sandbox parent-symlink and frame overlap stay merge blockers on other PRs.

## Host `VireDebug.Break` skip unless `VIRE_DEBUGGER=1`

Each user-function `Call` used to run `VireDebug.Break`, which created `data/`, walked reparse points, and called `File.Exists` on `data/break.txt`. CI job `129755174034` on SHA `2304852` charged `total_steps=164117` with `break_probes=1619992` and `phase_gen1host_sec 304.117`. After the skip, job `129759130623` on SHA `b1de7a3` kept the same step count and printed `break_probes=0` with `phase_gen1host_sec 8.426`. Caps and Defender are unchanged. Named-function stops still run when `VIRE_DEBUGGER=1`.
