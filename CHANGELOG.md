# Changelog

## Phase 1 (safe stdlib groundwork)

Crypto and JSON pieces that do not wait on types or capabilities:

- Builtins `random`, `token`, `hmac`, `samebytes`, `encrypt`, `decrypt` on both `Machine` and `CompiledMachine`, implemented once in `VireCrypto` with the .NET BCL (`RandomNumberGenerator`, `HMACSHA256`, `AesGcm`, `FixedTimeEquals`).
- AES-256-GCM encrypt always generates a 12-byte nonce; decrypt fails closed on tampers. HMAC known-answer tests follow RFC 4231. GCM known-answer tests follow the all-zero NIST vectors.
- `parse` accepts an optional schema map (`kind`, `need`, `keys`, `closed`) with explicit depth and size limits. Seeded fuzz covers the parser and GCM decrypt.
- Duplicate JSON object keys are rejected (`json has a duplicate key`). The same `Json.Read` path loads compiled `.vc` files, so a `.vc` with duplicate keys in its JSON tree is refused rather than last-wins.
- Recursive schemas are refused. Schema `need` lists are deduped into a local table (caller's schema is not mutated), capped at 100,000 names of at most 1,024 characters, and charged per entry before hashing. Value checks charge the step budget (and the listen deadline) once per value node and once per `need` entry.
- Ed25519 is documented as left: no standalone type in the .NET 10 BCL, no hand-rolled substitute.

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

Open questions carried forward: who may `POST /block`; whether blocks should keep a `por` field.

## Phase 3A (compiler grammar, first cut)

- Dual-mode conformance harness: each suite program runs in the interpreter and as compiled `.vc`; stdout must match, and stderr matches after normalizing columns.
- `compiler.vire` parses `for`/`skip`, `else if`, `try`/`miss`, `use`/`need`, map literals, decimals, and emits line/column on the tree.
- `CompiledMachine` executes those steps, fills in more builtins used by the suite, and reports the real line and column on errors.

## Phase 3A close-out (cut 3)

- Full suite (`tests.vire`, `checks/`, `systems/`, grammar programs) must match raw stdout/stderr in both modes. Error tests assert line and column. Crash fixtures dual-run and must not exit 3.
- Loader/VM rejects junk `.vc` steps (bad opcode, bad operand type, out-of-range jump, stack underflow). Seeded fuzz `20261030` in `dotnet test`.
- `PHASE3A-DONE.md` maps each done-criterion to a test or CI job. `windows-gui` covers WinForms `Form` construction on `windows-latest`.
