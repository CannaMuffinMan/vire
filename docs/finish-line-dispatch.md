# Finish-line dispatch briefs (Couchy launches; agents do not self-spawn)

Ceiling **5**. Do not start until Couchy assigns. No merges. No main/`native-compiler` pushes. No cap raises. No external compilers added as Vire dependencies. No FCG testnet. No Canna-PC actions.

Parent plan: `docs/finish-line-plan.md`. Evidence SHA: PR42 `3d9fc58` Windows hash `48f12268ace6f0e5ebb58f07bff090ec91bc78058342515cf56368e2e768f815`.

---

## L1 — Independent security / adversarial reviewer

**Purpose:** `/interrogate` + `/blast-radius` on the **diff that would ship**, not a writeup.

| | |
| --- | --- |
| **Writes** | **None.** Comments on PRs only if Couchy later allows `post_comment`; default is a **report file in the reviewer store / chat**, not the Vire tree. |
| **Branch** | none (detached read of PR42, L2–L5 heads) |
| **Base** | n/a |
| **Owned files** | none |
| **May read** | entire tree, CI logs, PR39 docs on `origin/cursor/multilingual-compile-plan-beb3`, pstack on `origin/tooling/pstack-skills` via `git show` |
| **Tests** | rerun any finding’s command; drop unverified claims |
| **Exclusions** | no `git commit`, no file edits, no `gh pr merge`, no installing untrusted skills copies into this repo |
| **pstack** | If `.cursor/skills/interrogate/SKILL.md` is **not** in the worktree, **do not pretend**. `git show origin/tooling/pstack-skills:.cursor/skills/interrogate/SKILL.md`. Four `generalPurpose` adversaries only if Task/arena is actually available; else **blocker**. |
| **PR dependency** | none |
| **Pass** | written findings with command+output, or “no verified findings” plus pstack gap |
| **Estimate** | 0.5–1 day parallel with L2 |

---

## L2 — Security residuals (F4 / F5 / F6)

**Purpose:** OS evidence for remaining Copilot items. Not new language features.

| | |
| --- | --- |
| **Branch name** | keep `cursor/pr40-copilot-fixes-0b9c` **or** `cursor/pr42-f456-0b9c` off **PR42 HEAD `3d9fc58`** (do not rebase onto later perf) |
| **Base** | `native-compiler` (`7c7c8ea`); PR stays **draft 42** |
| **Owned files** | `src/rt.vire`, `src/rt-more.vire` (path/write/crash only), `src/pe.vire` (IAT only), `data/src/rt.vire`, `data/src/rt-more.vire`, `data/src/pe.vire`, `tools/native-sec-windows.ps1`, `tools/native-sec-emu.py`, `FINDINGS-LEDGER.md`, `tests/Vire.Tests/CopilotFindingsTests.cs` |
| **Exclusions** | `compile-native.vire` parser/emit, `src/asm.vire`, `compiler.vire`, `Vire.cs` except tests, `api/`, `sites/`, README product copy |
| **Tests** | existing CopilotFindings + `native-sec-windows.ps1` + emu check. **No skips/deletes.** F5 race: two processes in `data/` only, no host-protected files. F4: prove RX `.text` not written (or name Unicorn-only residual). F6: crash stdout, no `crash-rip.txt`. |
| **Must re-prove** | `native-selfhost-windows` equal SHA after any emit/runtime byte change |
| **PR dependency** | L1 may comment; L3 must not land overlapping hunks first |
| **Estimate** | 1–2 days; F5 race may remain **access-limited** |

---

## L3 — Host compile performance (S7)

**Purpose:** Explain GrokBuild `gen1_host` TIMEOUT 420s @ **25363 steps** vs CI ~170656 steps in ~332–362s. **Do not raise timeout or caps.**

| | |
| --- | --- |
| **Branch** | `cursor/host-compile-perf-0b9c` |
| **Base** | `native-compiler` **until** L2 freezes `src/rt-more.vire` / `src/pe.vire`. If emit-only, may stack **after** PR42 **without** editing path_ok/IAT. |
| **Owned files** | `compile-native.vire` (emit/hexOf/buildExe only), `data/compile-native.vire` (keep hash-sync), `src/asm.vire` + `data/src/asm.vire`, `probe-*.vire`, `COMPILE-PERF.md`, `tools/` probe scripts |
| **Exclusions** | `src/rt-more.vire`, `src/pe.vire`, `src/rt.vire`, sandbox, Defender, `VireListen.cs` |
| **Tests** | HexOf/EmitU8/Extend tests; must not change hello/gen1 SHA **unless** documented and Windows selfhost re-run |
| **Experiment** | `docs/finish-line-plan.md` §4. GrokBuild VM + `windows-latest` logs only |
| **PR dependency** | wait if L2 has open IAT/path hunks |
| **Estimate** | 0.5–2 days diagnosis; fix unknown |
| **Pass** | RCA artifact; steps/s within 2× CI **or** environmental proof |

---

## L4 — Product: .NET bootstrap vs native PE (S6, S8)

**Purpose:** Make the split undeniable and ship a **clean-machine** recipe for **already-built** `gen1.exe`.

| | |
| --- | --- |
| **Branch** | `cursor/native-clean-machine-0b9c` |
| **Base** | `native-compiler` or PR42 **docs/tools only** |
| **Owned files** | `README.md`, `GUIDE.md`, `NATIVE-COMPILER.md`, `SELFHOST.md`, `docs/native-clean-machine.md` (new), `tools/native-clean-machine.ps1` (new). **No** runtime emit. |
| **Exclusions** | compiler/runtime sources, API, sites |
| **Tests** | script fails if `dotnet` is used after gen1 exists; CI job may build gen1 with dotnet then invoke gen1 in a PATH without it |
| **Exclusions (tech)** | no gcc/clang; hex→exe in PowerShell/.NET **bootstrap** is allowed **once**; running guests must be `gen1.exe` |
| **PR dependency** | S1–S5 SHA (`3d9fc58` or later equal-hash) |
| **Estimate** | 0.5–1 day |
| **Pass** | documented zip layout; CI log: gen1 hello + gen2 without calling `dotnet exec` for those steps |

---

## L5 — FCG in-tree only (sourced)

**Purpose:** Friday “built by Vire” for **files that exist**. Inventory gaps. **No** Chromium/WebView2/PoR invention. **No** wrapping npm/Go.

| | |
| --- | --- |
| **Branch** | `cursor/fcg-intree-0b9c` |
| **Base** | `native-compiler` |
| **Owned files** | `docs/fcg-source-inventory.md` (copy/update from PR39), `docs/fcg-local-handoff.md`, tests that already cover `api/fcgcpa.vire` / site emitters if present. **Prefer docs + existing tests.** |
| **Exclusions** | `src/*`, `compile-native.vire`, payments on, `POST /mine`, chain testnet, Railway deploy, OBS, secrets, cloning `fcgcpa-prod` onto the cloud box |
| **May cloud-read** | GitHub if token resolves more repos; Notion FCG pages **without** pasting secrets |
| **Tests** | existing API/listen tests; do not skip |
| **PR dependency** | none on L2/L3 files |
| **Estimate** | 0.5–1 day for inventory refresh; implementation of unread client = **blocked** |
| **Pass** | updated inventory; in-tree API/sites still run under **interpreter**; missing client/shop/PoR/TLS marked **unknown** |
| **Fail** | stub browser, `Process.Start` of foreign compilers, claiming full stack |

---

## Collision guard

| File | Owner |
| --- | --- |
| `src/rt-more.vire` path/write/extend | **L2 only** this week |
| `src/pe.vire` | **L2 only** |
| `compile-native.vire` emit | **L3 only** |
| README/GUIDE | **L4 only** |
| `docs/fcg-*` | **L5 only** |
| `docs/finish-line-*.md` | planning branch; later edits by Couchy |

If L3 needs `extend` bytes loop, **stop** and wait for L2 SHA.

Integrated SHA (human merge): re-run jobs `native-selfhost-windows` + `native-windows` + `test` + F2 ARM filter. Equal hash required.

---

## Tick prompt (if Couchy runs a coordinator)

Do not use this planning agent as the 5th implementation lane. Coordinator is optional and **counts toward 5** if it is a cloud agent. Prefer Couchy (human) as coordinator so all five slots are L1–L5.
