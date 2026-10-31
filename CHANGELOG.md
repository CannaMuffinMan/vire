# Changelog

## Phase 3B (native safety, continued)

- Native `rt_alloc` stops at the 1 MiB arena (`ran out of memory`, exit 1). File reads bump through `rt_alloc`. Interpreter host OOM uses the same message.
- Native `+` `-` `*` `/` and unary minus refuse silent wrap: the result must fit a 32-bit whole number or `that number overflowed`. Interpreter still widens to decimal.
- Native `number with` text that does not fit a 32-bit whole number uses the same overflow path (`that number overflowed`) instead of wrapping. Digit overflow during the parse also fails that way. Trailing junk still reports `that text is not a number` even when the digit prefix overflows. Interpreter and `.vc` still widen to decimal when `int` parse cannot.
- Native `number with` accepts the same whitespace, `+`/`-`, decimal, and exponent text as the interpreter when the value is a 32-bit whole number. A real that is not a whole number, or that does not fit, is `that number overflowed`. A lone `+` or `-` is `that text is not a number`.
- `compile-native` refuses a source literal that does not fit a signed 32-bit whole number (`that number overflowed`) instead of truncating it in `emitU32`. `-2147483648` still compiles.
- `rt_list_cat` and interpreter/`.vc` list `+` share the 100,000-item cap and `list is too large`. Text `+` shares the 1,000,000-character cap and `text is too large to write`.

## Phase 0

Hardening of the local runner on .NET 10. Commits C0–C9, in order.

- C0. Baseline: compiler, CompiledMachine, native sources, tests, api, sites. `.gitignore` for build output and key files.
- C1. net10.0 projects, xUnit harness, `PortGuard` (loopback port 0 only), Dockerfile digest pins, SHA-pinned Actions on ubuntu (windows jobs exist for self-host and native smoke).
- C2. Cycle-safe `say`/`json`, JSON depth 256, checked arithmetic, shared `Budget`, dedicated 64 MB stack, catch-all exit 3.
- C3. Per-evaluation `exprDepth` (cap 256). `tools/selfhost-check` stage1 = stage2 = stage3 on unsealed payloads.
- C4. Shared `SafeName`, write-then-run refused, SSRF connect-to-checked-IP with an allowlisted public-address set.
- C5. XOR `VIRE1` seals removed. `VC2` AES-256-GCM, required key, `vire keygen`.
- C6. `listen`: per-request budget and 5 s deadline, 64 slots, header/body limits, `Connection: close`.
- C7. `POST /block` server-computed index/previous/proof, segmented chain ≤ 512 KB, 503 on a broken chain, 507 when full. Authorization left open.
- C8. `serve` removed. `listen` GET/HEAD of `site/` with SafePath, no listing, 404 on traversal, symlink, and `.vire`.
- C9. `SECURITY.md`, GUIDE limits/seal/`listen`/paths/.NET 10, this changelog.

- Close-out. `PHASE0-DONE.md` maps each Phase 0 done-criterion to a test or CI job. Crash corpus runs in-process. Self-host CI compares unsealed stage-1/2/3 payloads with `cmp`. `tracked-binaries` job fails if git tracks exe/dll/pdb/hex or non-fixture `.vc`. Docker `FROM` digests and Actions SHAs stay pinned; tests fail if a pin is dropped.

- Track D fuzz. Seeded in-process fuzz (`FuzzTests`) for lexer/parser, `.vc` loader, JSON, and `listen` request parse. Nightly/`workflow_dispatch` job `fuzz.yml`. Parser block-depth cap, JSON size cap, fail-closed compiled loader. Findings in `PHASE0-FUZZ.md`.

Open questions carried forward: who may `POST /block`; whether blocks should keep a `por` field.

## Phase 3A (compiler grammar, first cut)

- Dual-mode conformance harness: each suite program runs in the interpreter and as compiled `.vc`; stdout must match, and stderr matches after normalizing columns.
- `compiler.vire` parses `for`/`skip`, `else if`, `try`/`miss`, `use`/`need`, map literals, decimals, and emits line/column on the tree.
- `CompiledMachine` executes those steps, fills in more builtins used by the suite, and reports the real line and column on errors.
