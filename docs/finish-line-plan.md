# Vire finish-line plan (Nov 10–13 ET)

Operator GO (Canna, 2026-11-10 4:18 AM ET): plan first; then up to five cloud agents; **today** Vire compiling itself; **Friday Nov 13 ET** FCG stack **built by Vire**. Targets, not guarantees. No merge, release, deploy, main/`native-compiler` push, cap raise, sandbox weaken, or price/spend change from this document.

This file is the implementation/acceptance plan. Dispatch briefs: `docs/finish-line-dispatch.md`. Older multilingual/FCG inventory (unread client still applies): PR39 `docs/multilingual-source-compiler-plan.md`, `docs/fcg-source-inventory.md`, `docs/fcg-local-handoff.md` on `cursor/multilingual-compile-plan-beb3`.

**Couchy launches lanes after review. This planning commit does not start them.**

---

## 1. Verified HEAD (this planning run)

| Fact | Value | Source |
| --- | --- | --- |
| This plan branch | `cursor/finish-line-plan-0b9c` from `origin/native-compiler` `7c7c8ea` | git |
| Security workstream | **PR42** https://github.com/CannaMuffinMan/vire/pull/42 draft | `gh pr view 42` |
| PR42 head | `3d9fc58c80629f1fd6ac11b3576831f5c869087d` | `headRefOid` |
| Chat wrapper | may still say PR41 | stale PR41 is a different branch |
| Windows gen1 hello compile | exit 0 | jobs `129677976694`, `129677996797` |
| Windows gen1 hello **run** | exit 0, `hello from stage` | same |
| Windows gen2 native rebuild | exit 0 | same |
| Equal SHA-256 | `48f12268ace6f0e5ebb58f07bff090ec91bc78058342515cf56368e2e768f815` | `gen1_sha256` = `gen2_sha256` |
| F7 sandbox text on Windows | `files stay inside the program folder` then `native sec windows recipe ok` | `native-windows` on run `42770835327` |
| F2 ARM64 | `test-linux-arm64` Passed 1 (`F2_LinuxOrdinaryFileLinkCountIsOne`) | job on same runs |
| F4 Windows RX vs copy | **unproven on OS** | FINDINGS-LEDGER / Unicorn only |
| F5 two-process replace race | **unrun** | ledger |
| F6 crash-PE log | **not separately logged** | ledger |
| pstack 4-adversary interrogate | **not executed** (skills on unmerged PR28) | `origin/tooling/pstack-skills` |
| Local GrokBuild `7c7c8ea` | `gen1_host` **TIMEOUT 420s at steps 25363** | operator fact; do **not** raise timeout/caps as the fix |
| CI `gen1_host` | ~332–362 s wall, ~170656 steps | same Windows jobs |

`.NET` bootstrap vs native compiler (must stay named separately):

1. **Bootstrap:** `dotnet exec …/vire.dll compile-native.vire data/compile-native.vire data/gen1.hex` then hex→PE. This is the C# interpreter emitting a PE. It is not “Vire without .NET.”
2. **Native compiler:** `gen1.exe` compiling guests and compiling `data/compile-native.vire` again. On `3d9fc58` Windows CI this **does** rebuild the compiler and match hashes.
3. **Unicorn** is stubbed kernel32. It is not the Windows gate.
4. **VC fixed-point** (`compiler.vire` → `stage2.vc` SHA) is a **different** self-host (bytecode). Already green on `selfhost` / `selfhost-windows`. It does not replace native PE.

`vire.csproj` has **no** `PackageReference`. Runtime is BCL + this repo. Test-only xunit. Do not add gcc/clang/Java/npm as a Vire compile dependency. `VireBuild.cs` still may shell `cl.exe` / NDK; that is a **host foreign build**, not Vire compiling those languages.

---

## 2. What “selfcompiles today” means (acceptance)

**Pass (Nov 10 ET, stronger than emu/VC):** all of the following on **real Windows** at a named SHA (today: `3d9fc58` already holds 1–4 on GitHub-hosted `windows-latest`):

| # | Criterion | Command / artifact | Status at `3d9fc58` |
| --- | --- | --- | --- |
| S1 | Host bootstrap emits gen1 | `dotnet exec vire.dll compile-native.vire data/compile-native.vire data/gen1.hex` exit 0, `compiled` | CI pass (~6 min, 170k steps) |
| S2 | gen1 runs hello | `gen1.exe data/guest-hello.vire data/gen1-hello.hex` then run PE; stdout `hello from stage` exit 0 | CI pass (compile ~20 ms, run ~11–14 ms) |
| S3 | gen1 rebuilds the compiler | `gen1.exe data/compile-native.vire data/gen2.hex` exit 0 `compiled` | CI pass |
| S4 | Fixed point | SHA-256(gen1.hex)==SHA-256(gen2.hex) printed | `48f12268…` |
| S5 | Caps unchanged | 32MB `VirtualAlloc`, list 100000, `VIRE_BUDGET`≤5e6, sandbox/Defender/tests not skipped | source + CI |
| S6 | Clean-machine native use | A directory with **only** `gen1.exe` + `data/compile-native.vire` + `data/src/*.vire` + guest; **no** .NET SDK, **no** gcc/clang; gen1 compiles hello and the compiler | **Not packaged.** CI still installs .NET to *produce* gen1. After gen1 exists, the PE itself does not load `coreclr`. **Gap: documented zip + script that proves no `dotnet` on PATH.** |
| S7 | Usable host performance | Same SHA: host compile of compiler finishes on **local GrokBuild** without raising 420s/5e6; steps/sec explained vs CI | **FAIL on 7c7c8ea local** (25363 steps / 420s). Diagnose; do not bump timeout as the solution. |
| S8 | Honest product split | README/GUIDE name: interpreter = .NET; native compiler = Windows x64 PE; Linux run of PE = Unicorn or wine (unsupported) | Partial (`README.md` still .NET-first) |

**Fail:** Unicorn-only hello; VC `selfhost ok` used as native proof; continue-on-error green; raising 32MB/5e6/list 100000; wrapping `dotnet publish` and calling it native selfcompile.

**Already true today on CI Windows:** S1–S5. **Not true today:** S6 packaging, S7 local host compile, S8 docs. “End of today” that is honest: **declare S1–S5 met at `3d9fc58`**, ship S6/S8 as a small docs+artifact lane, treat S7 as a **performance defect** (likely local config/hot-path), not a missing language feature.

---

## 3. Inventory (source-backed)

### 3.1 Language

Manual: `GUIDE.md`. Grammar lives in `Vire.cs` `Parser` and is reimplemented in `compiler.vire` (VC) and `compile-native.vire` (PE). No shared VIR (`docs/vir-ir.md` does not exist on `native-compiler`; planned in PR39 ML1).

Surface that exists: `define`/`end`, `let`, `if`/`else if`, `while`, `for`, `try`/`miss`, `stop`/`skip`, `put`/`into`, `use`, `need`, lists/maps/text/numbers/bool/none, `bytes`, comments `~`.

### 3.2 Three runtimes (do not collapse)

| Runtime | Entry | Output | Host OS |
| --- | --- | --- | --- |
| C# interpreter | `dotnet` / published `vire` | none (direct eval) | Linux/macOS/Windows |
| VC bytecode | `compiler.vire` → `VIRE-VC2` AES-GCM | `.vc` | same, needs seal key |
| Native PE | `compile-native.vire` + `src/{asm,pe,rt,rt-more}.vire` | Windows x64 PE via hex | **Execute: Windows.** Linux: Unicorn stubs |

Published single-file `vire` is still **CoreCLR**, not gen1.

### 3.3 Stdlib / packages

`deps/*/lib.vire` + `deps.lock` hashes (ui, textkit, listkit, jsonkit, filekit, numkit). Not a CVE feed. PR19 `vire.lock` not on this HEAD.

### 3.4 Build / foreign

| Path | Role | FCG relevance |
| --- | --- | --- |
| `VireBuild.cs` | `build` builtin: MSVC / Android NDK | **External compiler.** Must not become the FCG path. |
| `VireApk.cs` | APK; fail closed without aapt (PR42 F9) | Optional; not FCG client |
| `VireForeign.cs` | `foreign` | Not a language frontend |
| `windows/vire.windows.csproj` | WinForms `open`/`show` | Not WebView2/Chromium |

### 3.5 Test / CI

`.github/workflows/check.yml`: build, test, test-linux-arm64, tracked-binaries, image, selfhost, selfhost-windows, native-windows, native-selfhost-windows, publish. `continue-on-error` removed on native-selfhost at `3d9fc58`.

### 3.6 Platforms

| Claim | Evidence |
| --- | --- |
| Linux x64 interpreter | Docker / `dotnet` CI |
| Linux ARM64 interpreter nlink | F2 job pass (narrow filter, not full suite) |
| Windows interpreter | `selfhost-windows` |
| Windows native PE | `native-selfhost-windows` S1–S4 |
| macOS | publish RID exists; no native PE |
| Linux native ELF | PRs 27/30 **unmerged**, not this HEAD |

### 3.7 Security proofs vs gaps

See PR42 `FINDINGS-LEDGER.md` (on that branch). Caps: `SECURITY.md`. Native arena 32MB: `src/rt.vire` / `rt-more.vire` `33554432`.

| ID | Implemented | Verified | Residual |
| --- | --- | --- | --- |
| F1, F3, F8, F9, F10, F12, F13 | yes | linux/xunit/emu | — |
| F2 | yes | linux-x64 + **ARM64 F2 test** | full ARM test suite unrun |
| F7 | yes | Windows log contains sandbox sentence | — |
| F11 | yes + bytes reload | Windows gen1/gen2 `48f12268…` | keep regression test |
| F4 | path copy | Unicorn | real Windows RX `.text` |
| F5 | SetEndOfFile, no CREATE_ALWAYS | Unicorn + hardlink recipe | two-process replace race |
| F6 | crash to stdout | emit | dedicated crash PE log |
| Interrogate | — | — | 4-adversary not run |

### 3.8 Native PE vs interpreter capability gap

PE IAT (`src/pe.vire`): stdio, VirtualAlloc, files, GetCommandLine, attributes, file info, crash filter, SetFilePointerEx, SetEndOfFile. **No** socket, TLS, `listen`, `fetch`/`post`, `seal`, WinForms, `foreign`, `build`.

So **FCG `api/fcgcpa.vire` cannot run as gen1 PE today.** It runs on the **.NET interpreter** (`VireListen.cs`). Friday “built by Vire” for the API means **interpreter or VC**, unless a later lane ports `listen` (large, security-sensitive, not a stub).

---

## 4. Local performance diagnosis (S7) — experiment design

**Symptom:** same `7c7c8ea` tree: CI Windows host compile ~170k steps in ~6 min; local GrokBuild hit **420s at 25363 steps** (~60 steps/s vs CI ~470 steps/s). That is not “needs a longer timeout.” Caps stay 5e6.

**Do not:** touch Canna’s PC; raise `TimeoutSec` 420→hours; raise `VIRE_BUDGET`; disable Defender as the fix.

**Where:** GrokBuild Windows VM / GitHub `windows-latest` comparison only.

**Design (estimates):**

1. Confirm configuration: Release vs Debug, `VIRE_HEADLESS=1`, antivirus scanning `data/*.hex`, pagefile, single-thread. **Estimate 0.5–2 h.**
2. Reuse probes in `COMPILE-PERF.md` / `probe-*.vire` (hexOf, emitList, openImage) with an **external** timer and `vire: still running steps=` lines. Record steps/s. **Estimate 1–3 h.**
3. If probes are fast but full `compile-native.vire` as guest is slow: log which `use` file / function. Existing `INTEGRATE-38.md` Linux guest compile was ~66s. **Estimate 2–6 h.**
4. If Defender I/O: name it; do not add exclusions (invariants). Compare write rate of hex. **Estimate 1–2 h.**
5. Hot-path fixes only if a **repeatable** probe on CI+GrokBuild shows the same bottleneck (emitU8 leftover, list copy). File ownership: compile emit in `compile-native.vire` **or** `src/asm.vire` — **not** simultaneous with security IAT in `src/pe.vire` / `path_ok`.

**Pass:** local `gen1_host` completes at 5e6 with steps/s within 2× of CI, or a written root cause that is environmental (and a recipe that does not raise caps).

---

## 5. FCG stack — sourced vs unknown

In-tree (this repo, `native-compiler` / PR42):

| Piece | Source | Built how today | Native PE? |
| --- | --- | --- | --- |
| Web2 API | `api/fcgcpa.vire` + `api/README.md` | `dotnet … api/fcgcpa.vire` | **No** (`listen` is C#) |
| Demo chain | `systems/chain.vire`, API `data/chain/` | interpreter | hash exists in PE; API loop does not |
| Landing | `sites/landing/site.vire` | writes HTML/CSS strings | write-only if those builtins exist |
| Couch Potato page | `sites/cpa/app.vire` | same | same |
| Shop | URL `shop.forevercouchgang.space` only | **unknown** | — |
| Skinned browser / Chromium / WebView2 | **not in vire** | **unknown** | — |
| Proof of Rot miner | README phrase only | **unknown** | — |
| OAuth Twitch/YouTube clients | `/connect` JSON URLs | **unknown** | — |
| TLS terminator | `SECURITY.md` non-guarantee | **none in-process** | — |
| Billing | `/payments` 403, payments off | **off** | — |
| Admin | not found | **unknown** | — |
| Chain id | `forevercouchgang.blockchain` | files + POST `/block` | — |
| Railway | `PORT` in README | deploy **forbidden** this week | — |
| Testnet | **must not** land in this public repo | — | — |

PR39 (2026-11-07): `gh repo list` / `gh repo view CannaMuffinMan/fcgcpa-prod` → **not resolved**. Only public repo **vire**. Cloud token still cannot inventory the client. **Do not clone private repos onto this box.** Local-only handoff remains `docs/fcg-local-handoff.md` (PR39 branch). Notion FCG Bot Relay confirms Canna GO for FCG **implementation** is this message; it does **not** supply Chromium sources.

**Rewrite vs wrap:** “FCG stack built by Vire” means FCG **behavior is Vire source** compiled/interpreted by Vire. A wrapper that shells Go/.NET/npm/Chromium **fails** the goal (same as ML plan Appendix B). HTML/CSS **string emit** is already Vire; it is not a HTML frontend compiler (ML3). Direct C instead of `cl.exe` is ML2, **after** self-host, and is **not** the FCG client.

### What can credibly finish by Friday Nov 13 ET

| Credible | Not credible without missing sources |
| --- | --- |
| Keep API + landing + CPA generating from `.vire` under interpreter, tests, no deploy | Full skinned Chromium/WebView2 app in Vire |
| Document S1–S8; S6 zip of gen1 | Native `listen`+TLS+OAuth in four days |
| Residual F4/F5/F6 evidence or explicit OS blocker | “Entire stack” including unread `fcgcpa-prod` |
| ML1 fail-closed detector only (no fake C/JS compile) | Compiling the FCG client from unknown language |
| Local GrokBuild perf diagnosis | Cap/timeout raise as success |

**Friday pass (narrow, sourced):** (F1) S1–S5 still green on integrated SHA; (F2) S6 recipe exists; (F3) `api/fcgcpa.vire` + site emitters still run under interpreter with existing tests; (F4) written inventory of **unread** client/shop/PoR; (F5) no testnet, no payments on, no wrap compilers. **Friday fail:** demo stubs, invented Chromium, `cl.exe`/`tsc` in the FCG path, merge to main.

---

## 6. Dependency graph / critical path

```
PR42 3d9fc58 ──S1–S5 Windows native fixed-point (DONE on CI)
        │
        ├─► S6 clean-machine gen1 zip/docs (lane Product)
        ├─► S7 local host-compile perf (lane Perf) ──must not raise caps
        ├─► F4/F5/F6 OS evidence (lane Sec-impl) ──no emit parser edits
        └─► Reviewer (lane Review) ──no writes
                 │
                 ▼
        Operator: integrate SHA (humans merge, not agents)
                 │
        ┌────────┴────────┐
        ▼                 ▼
   ML1 detector      FCG in-tree API/sites
   (after S1–S5;     interpreter only until listen-in-PE
    no cl.exe)       exists (not this week unless sourced)
        │
        ▼
   ML2/ML3/client ──BLOCKED on fcgcpa-prod / browser / PoR sources
```

**Critical path to “today selfcompile”:** already on CI; remaining is S6/S8 honesty + S7 local. **Critical path to Friday FCG:** missing client source is the hard block; in-tree API/sites are the only finite work.

---

## 7. Milestones (ET) — pass/fail

Estimates are labeled **estimates**.

| When | Milestone | Pass | Fail |
| --- | --- | --- | --- |
| Nov 10 EOD | Selfcompile declaration | S1–S5 cited at `3d9fc58` (or newer equal-hash SHA); S6 script merged to a **draft** PR; README names .NET vs PE | Calling Unicorn/VC the native gate; timeout bump |
| Nov 10–11 | Perf | steps/s diagnosis artifact; optional emit PR **or** environmental RCA | Caps raised |
| Nov 11 | Security residuals | F4/F5/F6: OS proof **or** named access blocker | Silent “fixed” without logs |
| Nov 11–12 | FCG in-tree | Inventory refresh; API/site tests still green; **no** new product surface without source | Chromium stub, testnet |
| Nov 13 EOD | “Stack built by Vire” | Only sourced pieces, in Vire, tests; unread pieces listed | Claim of full FCG |

---

## 8. Security / integration order

1. Keep PR42 draft until F4/F5/F6 are evidenced or explicitly waived by Canna.
2. No agent merges. Humans integrate: security → perf (if it touches emit, **after** security SHA) → product docs → ML1.
3. Shared files: **one lane owns `src/rt-more.vire` path/IAT; another may own `compile-native.vire` emit hot paths; never both.** `src/pe.vire` IAT only security. Preserve merge-base `native-compiler` `7c7c8ea` until humans fast-forward.
4. Final integrated SHA must re-run `native-selfhost-windows` equal-hash (not continue-on-error).
5. `/interrogate` `/blast-radius`: execute if PR28 skills are on the worktree; else record gap (this run: **gap**, `git show` only).
6. Invariants: 32MB, list 100000, 5M, sandbox, Defender, no test deletes, no host file probing, no FCG testnet in repo.

---

## 9. Risky assumptions

- GitHub `windows-latest` equals “clean machine” for S6 (it still has .NET for bootstrap). **Mitigation:** PATH without dotnet in a subshell after gen1 exists.
- Local 25363-step stall is environmental. **If it is a latent interpreter bug, S7 becomes a multi-day emit/runtime fix.**
- `fcgcpa-prod` or a browser repo exists privately. **If not, Friday FCG is in-tree only.**
- ARM64 full `dotnet test` would pass (only F2 filter ran).
- pstack arena is unavailable until PR28 lands; reviewer lane uses Copilot + humans.

---

## 10. Lanes (ceiling 5; Couchy launches)

Exact briefs: `docs/finish-line-dispatch.md`.

| Lane | Role | Writes | Base | Depends |
| --- | --- | --- | --- | --- |
| L1 Review | adversarial / blast-radius | **none** | n/a | reads all PRs |
| L2 Sec | F4/F5/F6 OS evidence | `src/rt*.vire`, `src/pe.vire`, `tools/native-sec-*.ps1`, tests, ledger | **PR42 branch** | L1 comments |
| L3 Perf | S7 host compile steps/s | `compile-native.vire`, `src/asm.vire`, probes, `COMPILE-PERF.md` | `native-compiler` **or** PR42 **after** L2 freeze of rt/pe | not L2 same files |
| L4 Product | S6/S8 gen1 zip + README split | `docs/`, `tools/native-clean-machine.*`, `README.md`/`GUIDE.md` | `native-compiler` | S1–S5 SHA |
| L5 FCG-in-tree | inventory + API/site tests only | `docs/fcg-*.md`, tests around `api/` `sites/` — **no** new listen/TLS | `native-compiler` | unread client stays documented |

**Not launched here.** Do not fill extra lanes (ML2 C, ELF, intern PR31) this week unless Canna names them; they collide with emit/runtime.

---

## 11. Measurable commands (copy)

Windows CI already:

```text
pwsh -File tools/native-selfhost-handoff.ps1
# expect gen1_sha256 == gen2_sha256
# 3d9fc58: 48f12268ace6f0e5ebb58f07bff090ec91bc78058342515cf56368e2e768f815
```

VC (not native):

```text
bash tools/selfhost-check.sh
```

S6 (to be added by L4): after gen1.exe exists, `where.exe dotnet` fails in that shell, `.\gen1.exe data\guest-hello.vire data\out.hex` still works.

S7: compare `vire: still running steps=` timestamps on GrokBuild vs CI for `compile-native.vire` as guest.
