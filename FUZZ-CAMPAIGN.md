# Fuzz campaign (native-compiler tip `227c0e0a22c817492d090fa2443ed9f264ecb644`)

Branch: `cursor/fuzz-campaign-856d`. Does not touch `cursor/native-security-lane9-a95f` (PR #71) or PR #78.

Hard caps asserted unchanged: native arena **32MB** (`33554432`), guest list **100000**, steps **5_000_000**, `MaxCalls` **64**. No sandbox weakening, no Defender changes, no outside compilers.

## Inventory (reused)

| Piece | Role |
|---|---|
| `tests/Vire.Tests/FuzzTests.cs` | Track D seeded LCG (`seed 20261030`): lexer/parser, seal loader, JSON, HTTP listen parse |
| `tests/Vire.Tests/FuzzRegressionTests.cs` | Nested blocks, JSON size, sealed garbage `.vc` |
| `tests/fuzz/corpus/` | Text seeds (`*.vire`, `*.json`, `http-*.txt`) |
| `tests/crash/`, `tests/conformance/`, `tests/native/`, `samples/`, `greet.vire`, `guest-*.vire` | Grammar-aware mutation parents |
| `PHASE0-FUZZ.md` / `tools/fuzz-long.sh` / `.github/workflows/fuzz.yml` | Existing nightly 20k-iter job |

New grammar seeds: `tests/fuzz/corpus/grammar-builtins.vire`, `grammar-lists.vire`.

## Targets added

| Target | What it mutates | Oracle |
|---|---|---|
| `frontend` | Random + grammar-aware `.vire` (splice/nest/inject builtins from tests/examples) through `Lexer`/`Parser` and `Program.RunFile` | No host crash; `VireError` ok; hang > 4s |
| `builtins` | `split` / `at` / `json` / `parse` / text cat / `text` / `has` / `push` via generated programs and `Machine.Call` | Guest errors only; list/text caps |
| `gc` | Near list cap 100000, doubled strings toward `MaxText`, json/to_text/has/add | Fail-closed (`list is too large` / text too large); never print `escaped-list-cap` |
| `path` | `..`, device names, ADS-ish names, Linux symlink to a file outside the sandbox, `CheckName`/`CombineUnder`/`DataOrSite`/`UseFile` | Must not read `secret` from outside |
| native PE (Linux Unicorn) | Host `compile-native.vire` of mutated tiny guests, `tools/native-pe-emu.py` | `FAULTS []`, heap mapping `0x2000000` (32MB) |
| native PE (Windows CI) | Same guests as real `.exe` plus `mklink /J` junction probe | AV / hang / `secret` leak recorded under `tests/fuzz/findings/` |

Mutator: LCG `state = state * 1664525 + 1013904223`. Default PR tests still use `20261030` xor per target. Time-boxed runs take `VIRE_FUZZ_SEED` (this Canna run: `71115000`) plus `+101…+104`. Every finding is minimized (`FuzzCore.MinimizeText`) and hashed (SHA-256).

## Canna 20-minute run (2026-11-15)

Linux in-process, harness on `cursor/fuzz-campaign-856d`. Base seed **`71115000`** (not `20261030`). `VIRE_FUZZ_SECONDS=300` per target.

| Target | Seed | Executions | Seconds | Findings |
|---|---:|---:|---:|---:|
| frontend | 71115101 | 644169 | 300.000 | 0 |
| builtins | 71115102 | 1636151 | 300.000 | 0 |
| gc | 71115103 | 170530 | 300.001 | 0 |
| path | 71115104 | 2000000 | 170.601 | 0 |
| path top-up | 71116008 | 1570044 | 130.000 | 0 |

Wall clock ~20 min (17m50s testhost + 2m10s path top-up after the 2M-iter cap). **Findings: none.** `workflow_dispatch` of `fuzz.yml` for Windows PE returned 403 from this integration.

## Earlier session (Linux)

Host: Ubuntu 24.04, SDK 10.0.404. In-process campaign `VIRE_FUZZ_SECONDS=90` per target (wall ~6 min after earlier 45s/120s shakedowns).

| Target | Executions | Seconds | Findings |
|---|---:|---:|---:|
| frontend | 161239 | 90.000 | 0 |
| builtins | 405027 | 90.000 | 0 |
| gc | 39485 | 90.031 | 0 |
| path | 906783 | 90.000 | 0 |
| Track D `FuzzTests` (default 400×4 plus seal/json/http) | included in `dotnet test … ~Fuzz` | ~1–2s | 0 |
| native PE Unicorn (`VIRE_FUZZ_NATIVE_ITERS=2`) | 2 compile+emu | ~3s | 0 (`HEAP_SIZE 0x2000000`, `FAULTS []`) |

Longer shakedown (`120s`/target): frontend 226416, builtins 556662, path 1213536, gc 52265. A `gc` “finding” was a **fuzzer oracle bug** (the 400-item list program printed `escaped-list-cap`). That reproducer was deleted; the oracle now only uses that string when the loop bound is 100001. Re-run after the fix: 0 findings.

### Findings

None that are product crashes, hangs, memory corruption, sandbox escapes, or limit bypasses.

No security fix is included in this PR. Caps and path checks were not changed.

## Nightly / Windows CI (does not run on `pull_request`)

`.github/workflows/fuzz.yml`:

- `schedule: 17 4 * * *` and `workflow_dispatch` only (ordinary PR `check.yml` still runs the short `Fuzz*` facts only).
- **fuzz-long** (`ubuntu-latest`, timeout 25m): `VIRE_FUZZ_SECONDS=600` in-process campaign (all four targets + Track D) then 4 Unicorn PE guests / 180s.
- **fuzz-windows** (`windows-latest`, timeout 20m): 60s/target in-process + `tools/fuzz-windows.ps1` (up to 4 real PE runs, 180s, junction probe).

Reproducers land in `tests/fuzz/findings/`. Set `VIRE_FUZZ_FAIL_ON_FINDING=1` locally if a red test is wanted.

## How to replay

```bash
# short (PR)
dotnet test tests/Vire.Tests/Vire.Tests.csproj -c Release --filter "FullyQualifiedName~Fuzz"

# time-boxed campaign
VIRE_FUZZ_SECONDS=90 bash tools/fuzz-campaign.sh

# native PE (Linux Unicorn)
VIRE_FUZZ_NATIVE_ITERS=4 bash tools/fuzz-native-pe.sh
```
