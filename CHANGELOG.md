# Changelog

## Native Postgres TLS (this branch)

- `pg_open_ssl` sends SSLRequest, refuses `'N'` for `require`/`verify-full`, then `tls_wrap` (cert check on; hostname for verify-full). SCRAM-SHA-256 and simple query over TLS. Test CA generated at prove time. Channel binding SCRAM-SHA-256-PLUS is residual.
- Guest `tls_wrap` wraps an existing loopback TCP handle. Windows PE Schannel IAT (`secur32`/`crypt32`) is emitted, not a fail-closed stub.

## Native TLS (this branch)

- Guest `tls_connect` / `tls_send` / `tls_recv` / `tls_close`. Host `SslStream`. Linux ELF OpenSSL 3 only on TLS guests (`docs/native-tls.md`). CA paths use the data/site gate. `OpenSSL_version_num` must be ≥ 3.0. Test certs at test time.
- `tls_listen`: TLS 1.2+ termination on the HTTP listener (rank 11). Host `SslStream`; Linux ELF `SSL_accept` wrapping `rt_listen`. Loopback tests, fail-closed handshake/plaintext/downgrade. Windows PE still fail-closed. Contract `tests/rebuild/contracts/health.json`.

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
