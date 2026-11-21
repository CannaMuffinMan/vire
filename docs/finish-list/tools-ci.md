# tools / checks / .github / data — finish list

Lane: `cursor/cleanup-tools-ci` off `cursor/windows-pe-proof-fixes` `@c813695`. Caps unchanged: arena 33554432, list 100000, steps 5000000, compiler itemCap 1e6.

## Reference graph (live callers)

Roots walked: `.github/workflows/*.yml`, `tests/Vire.Tests/*.cs`, `CompilerStage.Files`, `tools/couchstation-windows-all.ps1`, `tools/stage-compiler-src.sh` / `native-selfhost-handoff.ps1` data copies, and intra-`tools/` sources.

### CompilerStage / VirePaths data copies (keep)

`compile-native.vire` and every `src/rt*.txt|vire` listed in `CompilerStage.Files` → `data/compile-native.vire` and `data/src/*`. Staging scripts: `tools/stage-compiler-src.sh`, `tools/native-selfhost-handoff.ps1`.

### `data/rebuild/*` (keep)

- `data/rebuild/chain/{000001,blocks,head}.json` — `tools/rebuild-chain-diff.sh`, `tools/rebuild-chain-tamper.sh`
- `data/rebuild-dist/*.html` — `tools/rebuild-portal-diff.sh` (and portal PE stub)

### CI (`.github/workflows`) — every job kept

| Workflow | Tools invoked |
|---|---|
| `check.yml` | `check-tracked-binaries.sh`, `selfhost-check.sh`, `native-arena-check.sh`, `native-sec-emu-check.sh`, `l1-residuals-check.sh`, `gen2-emitfix-if-check.sh`, `native-gc-kind-check.sh`, `selfhost-check.ps1`, `native-hello-handoff.ps1`, `native-sec-windows.ps1`, `native-smoke.ps1`, `native-oom.ps1`, `native-gc-loop-proof.ps1`, `schema-prove-windows.ps1`, `native-tcp-windows.ps1`, `native-list-cap-proof.ps1`, `native-selfhost-handoff.ps1`, `pg-prove-windows.ps1`, `pg-tls-prove-windows.ps1`, `redis-skip-path-guard.ps1`, `redis-prove-windows.ps1`, `redis-tls-prove-windows.ps1`, `pg-redis-tls-windows.ps1`, `gen2-emitfix-if-windows.ps1` |
| `fuzz.yml` | `fuzz-campaign.sh`, `fuzz-native-pe.sh`, `fuzz-windows.ps1` (`fuzz-long.sh` is a documented wrapper around `fuzz-campaign.sh`) |
| `native-elf.yml` | `native-elf-hello.sh`, `native-elf-files.sh`, `native-elf-nofollow.sh`, `native-elf-tcp.sh`, `rebuild-health-diff.sh`, `native-elf-selfhost.sh`, `native-elf-win-hello.ps1`, `native-elf-cross.sh` |
| `crypto.yml` | `crypto-prove.sh`, `crypto-prove-windows.ps1` |
| `native-at.yml` | `at-map-check.sh`, `at-map-windows.ps1` |
| `native-gen2-heap.yml` | `gen2-heap-check.sh`, `gen2-heap-windows.ps1` |
| `native-json.yml` | `json-prove.sh`, `json-prove-windows.ps1` |
| `native-limits.yml` | `native-limits-check.sh`, `native-limits-windows.ps1` |
| `native-net.yml` | `native-selfhost-handoff.ps1`, `native-net-windows.ps1` |
| `native-security.yml` | `native-security-linux.sh`, `native-sec-emu-check.sh`, `native-hello-handoff.ps1`, `native-security-windows.ps1`, `native-sec-windows.ps1` |

Helpers those scripts call: `native-pe-emu.py`, `native-sec-emu.py`, `rebuild-chain-remainder.py`, `native-host-info.ps1`, `stage-compiler-src.sh`.

### Tests

- `HarnessTests` / `CopilotFindingsTests` / `NativeArenaTests` / `RebuildChainContractTests` / `NativeJsonPeTests` string-assert on several `tools/*` files (kept).
- `SuiteTests.InterpreterSuitePasses` runs `tests.vire` plus every `checks/*.vire` with `define main` (`core.vire`, `secure.vire`) — **not** recursive into `checks/native-deps/`.
- `CompilerStageTests` copies the Files list into `data/`.

### CouchStation (`tools/couchstation-windows-all.ps1`)

Runs: `native-selfhost-handoff.ps1`, `native-selfhost-proof.ps1` ×3, `native-net-windows.ps1`, `rebuild-fcgcpa-windows.ps1`, `rebuild-fcgbds-worker-windows.ps1`, `json-prove-windows.ps1`, `crypto-prove-windows.ps1`, `pg-prove-windows.ps1`, `pg-tls-prove-windows.ps1`, `fuzz-windows.ps1`, `native-json-parse-windows.ps1`, `rebuild-sop-proxy-windows.ps1`, `rebuild-portal-windows.ps1`, `native-dns-windows.ps1`, `redis-tls-prove-windows.ps1`, `aes-gcm-windows.ps1`, `rebuild-headers-windows.ps1`, `rebuild-obs-listen-windows.ps1`, `rebuild-proxy-windows.ps1`, `tls-server-windows.ps1`, `pbkdf2-windows.ps1`, `apigo-ws-windows.ps1`, `rebuild-proxy-ws-windows.ps1`, `tls-schannel-windows.ps1`, `pg-redis-tls-windows.ps1`, `listen-ws-windows.ps1`, `ws-refuse-windows.ps1`, `proxy-reply-windows.ps1`.

### Other live Linux proof harnesses (not in CI, still capabilities)

`aes-gcm-linux.sh`, `apigo-ws-linux.sh`, `native-elf-dns.sh`, `native-elf-json-parse.sh`, `native-elf-tls.sh`, `native-pe-emu-check.sh`, `native-security-linux.sh`, `native-ws-linux.sh`, `pbkdf2-linux.sh`, `pg-prove-linux.sh`, `pg-tls-prove-linux.sh`, `proxy-reply-proof.sh`, `redis-tls-prove-linux.sh`, `ws-refuse-proof.sh`, and the `rebuild-*-diff.sh` / `rebuild-chain-tamper.sh` / `rebuild-fcgbc-diff.sh` / `rebuild-rpc-portal-rpc-diff.sh` family. Packers `pack-tls-pe.py`, `patch-rt-net-body.py`, `patch-rt-net-ws.py` regenerate staged blobs.

### `checks/native-deps/*`

Consumed by `tools/native-deps.ps1` (Windows PE deps lock). Not deleted.

## Placeholders (`TODO(VIRE-FINISH-NOW)`)

| File | What's missing | Priority |
|---|---|---|
| `tools/rebuild-proxy-windows.ps1` | Full host-vs-PE proxy modes vs loopback upstream (couchstation currently compiles MZ only in a sibling proof) | high |
| `tools/rebuild-proxy-ws-windows.ps1` | Host-vs-PE proxy-ws 101 / 400 / 403 | high |
| `tools/apigo-ws-windows.ps1` | Compile `apigo-ws` to PE and match ELF 101/echo/fail-closed | high |
| `tools/rebuild-portal-windows.ps1` | PE twins of `rebuild-portal-diff.sh` contracts | high |
| `tools/rebuild-sop-proxy-windows.ps1` | PE twins of landing SOP HMAC + listen | high |
| `tools/rebuild-obs-listen-windows.ps1` | PE GET `/obs` 307 and listen `/proxy` 200 | medium |
| `tools/native-forms.ps1` | Tracked `data/native-forms/{try-miss,for-list}.vire` fixtures | medium |

## Removals

| Path | Why dead | Evidence |
|---|---|---|
| `tools/vire-101.js` | One-off pptxgen deck, not a compiler/CI/self-host path | No refs in workflows, tests, couchstation, GUIDE |
| `tools/make_article_pdf.py` | One-off PDF writer; `if False:` dump of a stale article | Same; unused `article.txt` read |
| `tools/copilot-evidence.sh` | PR42 host one-off superseded by xUnit | No CI/test call; `CopilotFindingsTests` covers F1/F3/F8/F12/F13 |
| `tools/perf-parse-heartbeats.py` | One-off log parser | Never sourced by CI/tests/other tools |
| `checks/compiled.ps1` | Hardcoded `D:\_scratch\vire` scratch probe | Zero refs; live path is `tools/selfhost-check.ps1` |

No workflow jobs deleted (all still invoke existing tools). No `data/` snapshots deleted (all are CompilerStage copies or rebuild fixtures). `.gitattributes` `eol=lf` untouched.

## Cross-lane notes (untouched)

- `article.txt` / `Vire-post-mortem.pdf` (if present at repo root) were only consumed by the deleted PDF script — other lane.
- GUIDE samples (`work.vire`, `board.vire`, `serve.vire`) skipped by `samples-check.ps1` are product files, not this lane.
- Duplicate `Convert-HexToExe` copies inside many `.ps1` files are live, not dead; a shared helper would be a refactor outside “rip dead code”.
- `fuzz-long.sh` is a 5-line wrapper; CI calls `fuzz-campaign.sh` directly. Left as the documented entry from `PHASE0-FUZZ.md`.
- Packed blob generators (`pack-tls-pe.py`, `patch-rt-net-*.py`) are not in CI but are the intended way to regenerate `src/rt-*-blob.txt`; kept.
- `vire-index*.ps1` / `vire-project.ps1` / `samples-check.ps1` / `stdlib-check.ps1` / `site-pages-check.ps1` / `deps-*-check.ps1` / `native-{hash,large,replace,deps}.ps1` are unused by CI but implement real GUIDE/package/native proofs; kept.
