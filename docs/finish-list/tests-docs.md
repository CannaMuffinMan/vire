# Finish list: tests / docs / samples lane

Placeholders use `TODO(VIRE-FINISH-NOW):` exactly. Live tests of live code were not deleted.

| File | What's missing | Priority |
|---|---|---|
| `tests/rebuild/contracts/fcgbds-dashboard-go/BLOCKED.md` | Dashboard-go static/headers/502/tilt/WS/TLS/DB routes still blocked | high |
| `tests/rebuild/contracts/rpc-portal-go/BLOCKED.md` | rpc-portal outbound holdings/rpc, JWT vault, dist static, 405 | high |
| `tests/rebuild/contracts/edge-go/BLOCKED.md` | Host map, maintenance bypass, payments refuse, public bind | high |
| `tests/rebuild/contracts/dev-portal-go/BLOCKED.md` | Cookie gate, JWT session, `/fcg-api/` proxy, dist static | high |
| `tests/rebuild/FCGBDS-WORKER.md` | Native POST `body` SEGV workaround, reviewer TTL, PE proof | high |
| `tests/json/vectors/` | JSONTestSuite subset only; more `n_`/`y_` files not imported | low |
| `everything.vire` | Not in `FuzzCore.LoadGrammarSeeds` extras (still a live sample) | low |

## Cross-lane notes (untouched)

These look unused or stale but sit outside this lane's edit paths:

- `tools/vire-101.js` writes `D:/_scratch/worktrees/vire-e-len/Vire-101.pptx` (local path, not the in-repo deck).
- `tools/make_article_pdf.py` regenerates `Vire-post-mortem.pdf`; not invoked from CI.
- `tools/native-selfhost-proof.ps1` is still on disk; `HarnessTests` asserts `check.yml` does not call it, while `tools/couchstation-windows-all.ps1` still does.
- `data/compile-native.vire` and `data/src/*.vire` duplicate root `compile-native.vire` / `src/` (staging copies for native `read`).
- `tests/native/fixtures/gc-tagged-walk/compile-native.vire` is an older compiler snapshot for `tools/gen2-emitfix-*` (other lane).
- `compiler.vire`, `compile-native.vire`, crypto/kdf/pbkdf2/aes/hex-range guests belong to other lanes.
- `GAP-CLOSURE.md` is mentioned only as "do not import" in the archived security audit; it is not in this tree.
- `systems/` and `optional/live.vire` are scanned by `tests.vire` / GUIDE, not this cleanup.
- `src/rt-net-unpacked.vire` vs `src/rt-net.vire` dual emit paths: packed-listen work, not this lane.

## Deleted here (not placeholders)

Scratch probes and superseded emitters with no remaining callers after a repo-wide grep: `probe-*.vire`, `dump-net-extras.vire` (wrote uncommitted `data/src/rt-net-full-*` blobs; `compile-native.vire` already calls `emitNetRuntime`), `make-hello.vire` (hand PE writer replaced by `compile-native.vire`), `guest-empty.vire` (not in tests, tools, or `FuzzCore` extras).
