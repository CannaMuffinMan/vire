# Changelog

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

## Phase 3A residuals (cut 4)

- One source nesting limit of 256 (parentheses, lists, maps, blocks, unary, operator chains) in the C# lexer/parser, `compiler.vire`, `.vc` loader, and both VMs. Overflow is `source is nested too deeply` with line and column, identical in interpreter and compiled mode.
- Numeric literals longer than 100 digits are `that number is too large` with the same line and column in both modes.
- `fail with message, line, column` reports a `VireError` at that location so the compiler can match interpreter diagnostics.
- Hosting `compiler.vire` / `compiler.vc` raises call depth to 8192 so a 256-deep parse cannot hit the user-program cap of 64.

## Phase 3A close-out (cut 3)

- Full suite (`tests.vire`, `checks/`, `systems/`, grammar programs) must match raw stdout/stderr in both modes. Error tests assert line and column. Crash fixtures dual-run and must not exit 3.
- Loader/VM rejects junk `.vc` steps (bad opcode, bad operand type, out-of-range jump, stack underflow). Seeded fuzz `20261030` in `dotnet test`.
- `PHASE3A-DONE.md` maps each done-criterion to a test or CI job. `windows-gui` covers WinForms `Form` construction on `windows-latest`.
