# Native hard-coded limits

Inventory of numeric caps in the native compiler and PE runtime. The three **guarded** product caps stay exactly as they are. Everything else is an implementation limit: this branch removes the ones that stopped native from matching the host interpreter.

Line numbers are for this tree (`native-compiler` plus this change).

## Guarded caps (do not raise)

| Cap | Value | Where | Notes |
|---|---|---|---|
| Native arena | 33554432 (32MB) | `src/rt.vire:17` mapping size; `src/rt-more.vire:100` alloc limit; `src/rt-more.vire:1697` path copy | PE header reserves stay 1MB at `src/pe.vire` 224/240, not 32MB |
| Host list / map | 100000 | `Vire.cs:214`, `Vire.cs:222`, `Vire.cs:335-336` | Guest interpreter. Compiler mode uses `itemCap` 1000000 (`Vire.cs:407`) so a PE image can be built |
| Step budget | 5000000 | `Vire.cs:3027` `ProgramStepCap` | `VIRE_BUDGET` cannot exceed this. Native `while`/`for` use a separate counter (`src/rt-more.vire:1548`, 2000000 ticks wait) |

Related, also leave alone:

- Native call-frame cap **64** (`src/rt.vire:163` `1024` bytes = 64×16; `src/rt.vire:167-168` `frame_deep` / `msg_deep`). Matches host guest `MaxCalls = 64` (`Vire.cs:131`, `Vire.cs:498`). Guest `boom` still stops. This is **not** a reason to recurse in the compiler parser.
- Host parser nest **256** (`Vire.cs` expression / block / JSON). Native compiler now parses with an explicit stack so it does not spend those 64 VM frames on `parseOr`…`parseAtom`.

## Implementation limits (fixed or documented)

### Parser nesting (fixed)

**Was:** `compile-native.vire` `parseExpr` → `parseOr` → `parseAnd` → `parseCmp` → `parseSum` → `parseProduct` → `parseUnary` → `parsePrimary` → `parseAtom` → `parseExpr`. Nested `(1 + (1 + …))` hit host `MaxCalls` 64 at **depth 6** (`definitions called too deeply` at the old `parseAnd` call). That forced deep expressions in crypto/KDF sources to be rewritten as `let`s.

**Now:** `compile-native.vire` `precOf` / `parseExpr` (from line 237) is an iterative precedence climber. `emitExpr` (from `emitAtom`/`emitExpr`) walks the AST with an explicit stack. Depth 80 nested `+` compiles. Host interpreter still evaluates the same program.

### PE `text is too large to write` (aligned with host)

| Site | Value | Message | Role |
|---|---|---|---|
| `src/rt-more.vire:604-616` | 1000000 | `msg_bigtxt` | `rt_text_cat` — same as host guest `MaxText` (`Vire.cs:337`) |
| `src/rt-more.vire:2219-2245` | 1000000 | `msg_bigtxt` | `rt_join` — same as host guest text |
| `src/rt-more.vire:1876-1940` | 2000000 | `msg_bigtxt` | `rt_write` — same as host compiler `textCap` (`Vire.cs:408`) |
| `src/rt-more.vire:2066` | 2000000 | `msg_oom` | `rt_hex` output length (2× bytes) — host `HexBytes` allows up to 1000000 **bytes** (`Vire.cs:2908`) |

FIPS 1M SHA (`crypto-mb.vire` / `tests/native/million-hash.vire`) builds a 1_000_000-byte text by doubling **without** crossing 1_000_000, then `hash`. Host and native PE both print `cdc76e5c9914fb9281a1c7e284d73e67f1809a48a497200e046d39ccc7112cd0`. A doubled 524288+524288 (=1048576) cat still fails on **both** with `text is too large to write`; that is the guarded guest `MaxText`, not a PE-only bug.

`compile-native.vire` writes the image with builtin `hex` + `write`, not `hexOf`/`join`. Selfhost hex (~753664 chars) fits both 1e6 join and 2e6 write.

### Emit size / format (already rel32; string pool ASCII)

| Site | Limit | Status |
|---|---|---|
| `compile-native.vire` `emitJmp` / `emitJz` / `src/rt-more.vire` `emitRel` | 32-bit RIP displacement | **Not** an 8-bit `jmp`. Large functions use `E9` / `0F 8x` + rel32. No remaining ±128 jump cap in the compiler emit path |
| `src/asm.vire` `emitU32` / `emitU64` | immediates | `num` literals use `mov rcx, imm64` (`compile-native.vire` `emitAtom`) |
| `compile-native.vire` `pool` ~1347 | `codeOf` < 0 → `that text cannot be written yet` | ASCII + CR/LF/HT only (`src/pe.vire` `codeOf`). Host strings are UTF-16. **Residual:** non-ASCII literals still fail native emit |
| `src/pe.vire` `parkPool` | one `emitU8` per character + length prefix | No extra size cap beyond image/hex/write |
| `src/rt.vire:515` | 1000000 | `read` file size — host `MaxText` |
| `src/rt-more.vire:1368,1384` | 2000000 | `push` list/bytes — compiler-sized; guests on host stay at 100000 |

### Other numbers (not this lane)

Net recv 1000000 (`src/rt-net.vire`), listen body 1MB, intern table 128 (`src/rt-more.vire:1211`), trap slots 384, `MaxRuns` 8. Unchanged.

## Proof

`tools/native-limits-check.sh` (Linux) and `tools/native-limits-windows.ps1` (Windows) print `FAIL_BEFORE at <base SHA>` by actually running `git show` of `compile-native.vire` at `origin/native-compiler`, then `PASS_AFTER` on HEAD. Windows also runs the gen1 PE and requires host stdout = PE stdout.
