# Fuzz campaign run

- tip: `227c0e0a22c817492d090fa2443ed9f264ecb644`
- host: Unix 6.12.113.0
- utc: 2026-11-15T09:06:09Z
- requested: ~20 minutes wall (about 5 min per target), new seeds beyond `20261030`
- VIRE_FUZZ_SEED: `71115000` (plus path top-up `71115904`)
- testhost wall: 17m50s (four targets) + 2m10s (path top-up) ≈ **20 min**

## Seeds

| Target | Seed | Notes |
|---|---:|---|
| frontend | 71115101 | `71115000 + 101` |
| builtins | 71115102 | `71115000 + 102` |
| gc | 71115103 | `71115000 + 103` |
| path | 71115104 | `71115000 + 104`; 2M-iter cap at 170.6s |
| path (top-up) | 71116008 | `71115904 + 104`; extra 130s after raising `MaxIters` |

Replay: `VIRE_FUZZ_SEED=71115000 VIRE_FUZZ_SECONDS=300` (and `VIRE_FUZZ_SEED=71115904 VIRE_FUZZ_ONLY=path VIRE_FUZZ_SECONDS=130`).

## Executions

| Target | Seed | Executions | Seconds | Findings | Hangs | Crashes |
|---|---:|---:|---:|---:|---:|---:|
| frontend | 71115101 | 644169 | 300.000 | 0 | 0 | 0 |
| builtins | 71115102 | 1636151 | 300.000 | 0 | 0 | 0 |
| gc | 71115103 | 170530 | 300.001 | 0 | 0 | 0 |
| path | 71115104 | 2000000 | 170.601 | 0 | 0 | 0 |
| path (top-up) | 71116008 | 1570044 | 130.000 | 0 | 0 | 0 |

Path combined: **3,570,044** executions, **300.601** seconds.

## Findings

None this run. No crash, hang, sandbox escape, or limit-bypass oracle failure. Nothing written under `tests/fuzz/findings/` except `README.md`.

Windows `fuzz.yml` `workflow_dispatch` was attempted (`gh workflow run fuzz.yml --ref cursor/fuzz-campaign-856d`) and returned **HTTP 403 Resource not accessible by integration**. This agent cannot fire the real Windows PE job; a repo admin can dispatch it from the Actions tab.
