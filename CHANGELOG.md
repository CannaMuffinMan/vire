# Changelog

## VireApk host-only close (this branch)

- `VireApk.Pack` is not a guest builtin. APK packing is not a Vire product. SDK lookup honors `ANDROID_SDK_ROOT` / `ANDROID_HOME` before `D:\\Android`. NDK lookup honors `ANDROID_NDK_HOME` / `ANDROID_NDK_ROOT` before SDK/`D:\\Android`. Missing tools name those env vars. `ApkTests` / `AndroidSoTests` fail closed without tools and fail the success path with that named env instead of passing. Caps unchanged.

## Tests/docs dead-code cleanup (this branch)

- Root emit/compile probe programs (`probe-*.vire`), unused `dump-net-extras.vire`, superseded `make-hello.vire`, and unreferenced `guest-empty.vire` removed. Live guests, samples, and xUnit fixtures were not deleted.
- Obsolete handoff/phase/perf/audit notes (`PHASE0-DONE.md`, `PHASE0-FUZZ.md`, `LOCAL-CLI-HANDOFF.md`, `INTEGRATE-38.md`, `COMPILE-EXTEND.md`, `COMPILE-PERF.md`, `EMIT-PERF.md`, `SELFHOST.md`, `SECURITY-AUDIT.md`, and the Nov 5 `NATIVE-COMPILER.md` work log) folded into `docs/history.md`. `NATIVE-COMPILER.md` keeps current self-host status only.
- Unfinished rebuild sidecars stay as `TODO(VIRE-FINISH-NOW)` lines in their `BLOCKED.md` files and `docs/FINISH-LIST.md`. Caps unchanged.

## WebSocket refuse fail-closed (this branch)

- Packed native `listen` no longer overwrites HTTP `rt_listen` with an auto-101 dispatcher. RFC 6455 101 is emitted only when the route returns `"status":101`. GET `/ws/refuse` is 403 on host and ELF (`tools/ws-refuse-proof.sh`). With `"port"` both splice (host `TryWsHijack` / packed `land_ws_send`). CouchStation: `tools/ws-refuse-windows.ps1` (PE not executed here). Residual: native 101 without `"port"` is JSON HTTP 101 (in-process echo stays on the host). Caps unchanged.

## Packed listen + proxy_reply (this branch)

- Packed 3-param `listen` parks the route `body` as `lea rdx,[rip+txt_empty]` (in-place blob+2728, reloc `txt_empty`) so GET/HEAD nobody is a heap text, not integer 1. FAIL_BEFORE `962be3ac`: native empty HTTP / SEGV `rdx=1` vs host `200 up-ok`. Extra Vire trampoline statements overflowed list cap 100000 on self-host; this patch does not grow `emitLandingHttp`. `tools/proxy-reply-proof.sh`. CouchStation: `tools/proxy-reply-windows.ps1` (PE not executed here). Residual: packed POST body is also `txt_empty` on this 24-byte site; `land_st_405` still dropped (list cap 100000, not raised). Caps unchanged.

## Native Postgres / Redis TLS on PE SChannel (this branch)

- Merge of #109 / #116 onto #126. ELF OpenSSL is unchanged. PE `tls_wrap` is emitted through the SChannel guest (`src/rt-tls-pe.vire`): hostname verification on, TLS 1.2+, no skip-verify, no `LoadLibrary`. `pg_open_ssl` verify-full and `rediss://` (tls_connect) use that stack. CouchStation: `tools/pg-redis-tls-windows.ps1`. Residual: SCRAM-SHA-256-PLUS, RESP3, PE execute on this Linux agent.

## Native Postgres TLS (this branch)

- `pg_open_ssl` sends SSLRequest, refuses `'N'` for `require`/`verify-full`, then `tls_wrap` (cert check on; hostname for verify-full). SCRAM-SHA-256 and simple query over TLS. Test CA generated at prove time. Channel binding SCRAM-SHA-256-PLUS is residual.
- Guest `tls_wrap` wraps an existing loopback TCP handle. Windows PE SChannel IAT (`secur32`/`crypt32`) is emitted, not a fail-closed stub.

## Native TLS (this branch)

- Guest `tls_connect` / `tls_send` / `tls_recv` / `tls_close`. Host `SslStream`. Linux ELF OpenSSL 3 only on TLS guests (`docs/native-tls.md`). CA paths use the data/site gate. `OpenSSL_version_num` must be ≥ 3.0. Test certs at test time.
- `tls_listen`: TLS 1.2+ termination on the HTTP listener (rank 11). Host `SslStream`; Linux ELF `SSL_accept` wrapping `rt_listen`. Loopback tests, fail-closed handshake/plaintext/downgrade. Windows PE still fail-closed. Contract `tests/rebuild/contracts/health.json`.
- Listen-side RFC 6455 Upgrade hijack: valid websocket GET is spliced onto a loopback upstream (`{"status":101,"port":N}`). Host `VireListen` + native `land_ws_send`. `wss://` on `tls_listen`. `tools/rebuild-listen-ws-diff.sh` / `rebuild-listen-wss-diff.sh`. PE CouchStation: `tools/listen-ws-windows.ps1` (not run on Linux).

## Phase 0

Hardening of the local runner on .NET 10. Commits C0–C9, in order.

- C0. Baseline: compiler, CompiledMachine, native sources, tests, api, sites. `.gitignore` for build output and key files.
- C1. net10.0 projects, xUnit harness, `PortGuard` (loopback port 0 only), Dockerfile digest pins, SHA-pinned Actions on ubuntu (windows jobs exist for self-host and native smoke).
- C2. Cycle-safe `say`/`json`, JSON depth 256, checked arithmetic, shared `Budget`, dedicated 64 MB stack, catch-all exit 3.
- C3. Per-evaluation `exprDepth` (cap 256). `tools/selfhost-check` stage1 = stage2 = stage3 on unsealed payloads.
- C4. Shared `SafeName`, write-then-run refused, SSRF connect-to-checked-IP with an allowlisted public-address set.
- C5. XOR `VIRE1` seals removed. `VC2` AES-256-GCM, required key, `vire keygen`.
- C6. `listen`: per-request budget and 5 s deadline, 64 slots, header/body limits, `Connection: close`.
- C7. `POST /block` server-computed index/previous/proof, segmented chain ≤ 512 KB, 503 on a broken chain, 507 when full. Write path later required a Bearer secret (`FCG_BLOCK_TOKEN` / `FCG_API_TOKEN`), deny-by-default.
- C8. `serve` removed. `listen` GET/HEAD of `site/` with SafePath, no listing, 404 on traversal, symlink, and `.vire`.
- C9. `SECURITY.md`, GUIDE limits/seal/`listen`/paths/.NET 10, this changelog.

- Close-out. Phase 0 done-criteria map (archived in `docs/history.md`) to tests and CI jobs. Crash corpus runs in-process. Self-host CI compares unsealed stage-1/2/3 payloads with `cmp`. `tracked-binaries` job fails if git tracks exe/dll/pdb/hex or non-fixture `.vc`. Docker `FROM` digests and Actions SHAs stay pinned; tests fail if a pin is dropped.

- Track D fuzz. Seeded in-process fuzz (`FuzzTests`) for lexer/parser, `.vc` loader, JSON, and `listen` request parse. Nightly/`workflow_dispatch` job `fuzz.yml`. Parser block-depth cap, JSON size cap, fail-closed compiled loader. Track D finding table archived in `docs/history.md`.
- Fuzz campaign (`FUZZ-CAMPAIGN.md`): grammar-aware frontend, builtins, GC/list-cap, path bind, Unicorn + Windows PE jobs. Nightly stays off the PR `check.yml` path. Caps unchanged.

Open questions carried forward: whether blocks should keep a `por` field.

## Phase 3A (compiler grammar, first cut)

- Dual-mode conformance harness: each suite program runs in the interpreter and as compiled `.vc`; stdout must match, and stderr matches after normalizing columns.
- `compiler.vire` parses `for`/`skip`, `else if`, `try`/`miss`, `use`/`need`, map literals, decimals, and emits line/column on the tree.
- `CompiledMachine` executes those steps, fills in more builtins used by the suite, and reports the real line and column on errors.
