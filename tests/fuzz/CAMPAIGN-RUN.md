# Fuzz campaign run

- tip: `6e969fc2e9c94f537bad69b948e56670096c2a1b` (merged native-compiler)
- host: Unix 6.12.113.0
- utc: 2026-11-16T04:59:59.9462163Z
- VIRE_FUZZ_ITERS: 2000000
- VIRE_FUZZ_SECONDS: 40
- VIRE_FUZZ_SEED: 71117000

## Executions

| Target | Seed | Executions | Seconds | Findings | Hangs | Crashes |
|---|---:|---:|---:|---:|---:|---:|
| frontend | 71117101 | 74052 | 40.000 | 0 | 0 | 0 |
| builtins | 71117102 | 191568 | 40.000 | 0 | 0 | 0 |
| gc | 71117103 | 21842 | 40.001 | 0 | 0 | 0 |
| path | 71117104 | 430927 | 40.000 | 0 | 0 | 0 |

## Findings

In-process: none.

Native PE Unicorn (Linux, `pe` flag; not this testhost):

- `tests/fuzz/findings/native-pe-json-map.vire` — `json with {"a": 2}` → `UC_ERR_READ_UNMAPPED`
- `tests/fuzz/findings/native-pe-parse-array.vire` — `parse with "[1,true,null]"` → `UC_ERR_WRITE_UNMAPPED`
