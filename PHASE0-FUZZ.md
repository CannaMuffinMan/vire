# Phase 0 Track D: security fuzz harness

Base: `phase0/closeout`. Branch: `phase0/fuzz`.

Deterministic seeded fuzz runs inside ordinary `dotnet test` (`FuzzTests`, 400 iterations, seed `20261030`). A longer job is `workflow_dispatch` / nightly (`fuzz.yml`, `tools/fuzz-long.sh`, `VIRE_FUZZ_ITERS`). Corpus is text only under `tests/fuzz/corpus/`.

## Findings

| Finding | Before | Fix | Regression |
|---|---|---|---|
| Deep `if`/`while`/`try` blocks recursed in the parser with no cap; enough nesting could overflow the stack. | Stack overflow / process death | Parser `blockNest` cap 256 → `block is nested too deeply` | `FuzzRegressionTests.NestedBlocksHitAVireErrorNotAStackOverflow` |
| `.vc` loader decrypted then `Json.Read` + unchecked casts. Sealed JSON that was not a funcs table threw `InvalidCastException` (exit 3) instead of a Vire error. | Internal error / could look like a crash | `CompiledProgram.LoadFuncs` validates shape; JSON errors become `compiled file is damaged` | `FuzzRegressionTests.SealedGarbageJsonDoesNotRunAndDoesNotCrash` |
| `Json.Read` had a depth cap but no input size cap. | Unbounded allocation on a huge string | Refuse inputs longer than 1,000,000 characters | `FuzzRegressionTests.JsonOverSizeLimitIsRefused` |

Lockfile parser (`VireLock.Parse`): seeded fuzz in `FuzzTests.LockfileParserSeededFuzzNeverCrashes` plus `FuzzRegressionTests.HostileLockfilesAreVireErrorsNotCrashes`. Corpus: `tests/fuzz/corpus/lock-*.txt`.

Listen request parsing is now `HttpWire` (header block 16 KB, request line 8 KB, body 1 MB, no chunked). Fuzz covers truncated, oversized, and malformed request lines/headers/bodies. AES-256-GCM still fail-closes on truncate/flip/forge (`SealTests` plus `FuzzTests.SealLoaderSeededFuzzRejectsAndFailsClosed`).
