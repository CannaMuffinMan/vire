# Emit fast path

Host byte emission for the native compiler. Caps unchanged. Native PE execute and gen1/gen2 fixed-point stay unproven on this Linux host.

## Hypothesis

Tree-walk `emitList` -> `emitU8` (normalize, `floorDiv`) dominates host compile of small programs. Secondary guesses (lexer, maps, rebuild runtime, native arena) were not the first patch.

## Before (this Linux x86_64 VM, 2026-11-06, Release `vire.dll`)

`dotnet exec bin/Release/net10.0/vire.dll`, `VIRE_BUDGET` unset.

| Probe | Wall |
|---|---|
| `probe-push.vire` 21000 push | 0.085s |
| `probe-emitu8.vire` 21000 `emitU8` of 72 | 1.442s |
| `probe-emitlist.vire` 21000 in-range `emitList` | 1.591s |
| `emit-range.vire` | 0.066s, stdout locked |

Windows report at `18c2623` (user-supplied, not rerun here). Host compile hello-stage ~31-36s. 21000 `emitU8` ~34s vs push ~0.13-0.18s. Same shape, larger absolute times. Linux hello 2.604s on a different branch/host is not the same probe.

## After (same VM, same `dotnet exec` Release dll)

| Probe | Wall |
|---|---|
| `probe-push.vire` 21000 push | 0.089s |
| `probe-emitu8.vire` 21000 `emitU8` of 72 | 1.389s (still a call per byte) |
| `probe-emitlist.vire` 21000 in-range `emitList` | 0.185s |
| `compile-native.vire` `data/hello-emit.vire` | 2.523s before stash, 2.147s after |
| hello `.hex` | 37888 bytes, SHA-256 `bac704b422ffafe53dc867cd16debc37277f25cd4aea8f06c67602e885e040ce` identical |

`emitU8` body fast-path did not move the 21000-call probe. Skipping the `emitU8` call in `emitList` did. Hello host emit dropped about 0.38s on this machine. Not Windows 31s and not a millisecond claim.

## Semantics

`emitU8` still wraps. In-range 0..255 is `push`. Out of range still uses `floorDiv` and the negative clamp. `emitList` `push`es in-range bytes and calls `emitU8` otherwise.

`data/src/` is not in this tree. Only `src/asm.vire` and `src/rt.vire` changed.

## Later (aspirations, not measurements)

0. This patch. Per-byte call density.
1. Host bulk-append builtin shared with `CompiledMachine`.
2. Lexer range checks, char interning, nonquadratic strings. Same semantics.
3. `.vc` host compiler artifact with parity.
4. Native intern/32MB/fixed-point. PR #31. Separate.
5. Runtime template and image buffer after earlier gates.

Seconds-to-milliseconds in older notes are hopes, not gates.

## Unproven

Windows PE run. gen1.hex == gen2.hex. Hours-long self-compile. Native parent-symlink and hardlink sandbox. Native frame vs value stack.
