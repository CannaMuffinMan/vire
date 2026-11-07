# Direct multilingual source compilation plan

This program adds Vire frontends that parse, typecheck, and lower other languages' source into a shared IR, then reuse Vire optimization and backends. CVE and advisory matching run on resolved identities during that compile. The operator lands PRs ML1 through ML6. This planning run implements none of them.

## How to read this

One box is one unit of work. Every box names the evidence that checks it. A nested box is a sub-step of the box above it. Check a box only when its evidence exists, a file, a log line, a screenshot, a test run, or a SHA. The body is a how-to. The appendices explain and record.

The program runs `pstack/skills/poteto-mode/playbooks/autopilot-stack.md`. The operator lands ML1 through ML6. Owners stop at merge-ready. Do not merge from this planning branch.

Tests alone are not sufficient verification. A PR is verified only when its unit, live, and perf boxes are all checked.

## Program checklist

### Arm the program

- [ ] State the protocol and this plan to the operator, then stop. Start execution only on the operator's explicit go.
- [ ] Read these from trunk at program start. Re-read them at every tick.
  - [ ] `git show origin/main:pstack/skills/poteto-mode/playbooks/autopilot-stack.md`
  - [ ] `git show origin/native-compiler:NATIVE-COMPILER.md`
  - [ ] `git show origin/main:pstack/skills/swarm/SKILL.md`
  - [ ] `git show origin/main:pstack/skills/control-cli/SKILL.md`
  - [ ] `git show origin/main:pstack/skills/poteto-mode/playbooks/opening-a-pr.md`
  - [ ] `git show origin/main:pstack/skills/how/SKILL.md`
  - [ ] `git show origin/main:pstack/skills/blast-radius/SKILL.md`
- [ ] On the operator's go, arm the audit tick as `/loop 1h` with the tick prompt below. Never leave the cadence to memory. This planning run must not start that loop.
- [ ] Use this tick prompt, verbatim. "Re-read the execution playbook from trunk. Audit the operation against it and fix drift in this tick. Probe every active lane and judge progress by side effects only. Stand down a stuck lane and dispatch its replacement now. Then post a short status message to the operator in chat only when the audit found a tracked change that no earlier status message reported, such as a PR opened, a code-ready head, a round launched or closed, a verdict, a merge, a stuck agent and the action taken, a blocker added or cleared, or a decision only the operator can make. Name every such change and nothing else. Do not repeat a table, the merged list, or an unchanged blocker. If the audit found none, end the turn with no reply text. Either way, log this tick's row in your decision trail. The row names the items reported, or none."
- [ ] On the operator's hold or stand-down, send every owner a zero-writes order at once.

### Spawn owners

- [ ] Spawn one owner per PR with the full lifecycle the execution playbook names.
- [ ] Follow this dependency graph. Start dependent work only after its parent merges, or base it on the parent branch when the execution playbook stacks.
  - [ ] ML1 branches from `native-compiler` after self-host proof or with an explicit operator waiver recorded in the PR.
  - [ ] ML2 after ML1.
  - [ ] ML3 after ML1. ML3 may stack beside ML2.
  - [ ] ML4 after ML1. ML4 may stack beside ML2 and ML3.
  - [ ] ML5 after ML2 and ML3.
  - [ ] ML6 after ML4 and ML5.
- [ ] Hold the file boundaries. ML1 touches only `docs/`, new `ir/` notes, and tests that fail closed on unknown languages. ML2 touches C frontend files plus `VireBuild.cs` deletion of `Process.Start` to `cl.exe`. ML3 touches HTML and CSS frontend files plus FCG fixtures under `sites/`. ML4 touches lock, SBOM, and advisory snapshot files. ML5 touches analysis passes. ML6 touches cache invalidation. Do not edit `cursor/native-selfhost-intern-0258` or `cursor/security-audit-fix-0b9c`.
- [ ] Hold the review gate. ML2, ML3, and ML5 change a compile CLI interaction. They wait for the operator's review in chat with screenshots and a video before merge.

### PR mechanics, for every PR

- [ ] Resolve the forge once. Default to `gh`; if `command -v origin` succeeds and Origin can resolve the repository, use `origin pr` for every PR operation. Record any fallback to `gh`. Never require `gt`.
- [ ] Open the PR ready, never draft, per **Opening a PR**. Use the run's built-in PR tool when it has one, else `origin pr create --status open --base <base-branch>` or `gh pr create --base <base-branch>` according to the resolved forge. A stack child targets its parent branch.
- [ ] Run the repo's lint and typecheck once before the PR-facing push. Push with hooks on.
- [ ] Run `/deslop` before each commit and `/no-comments` before review.
- [ ] Triage every Bugbot and security-reviewer comment per `../references/bugbot-triage.md`.
- [ ] Rebase onto current trunk before the code-ready report and babysit. Keep that merge base in fix rounds. Rebase again only at merge prep, on a `git merge-tree` conflict with trunk, on a CI failure that comes from a change on trunk, or when a known concurrent change to the same files lands.

### Verdict and merge, for every PR

- [ ] A full swarm runs once, at the code-ready head. Another full swarm runs only for new behavior, a redesign, or a large new diff. A rebase, a merge-conflict resolution, or a minor fix gets a single verifier at the new head, and a wording-only change gets none. Run each full swarm per `pstack/skills/swarm/SKILL.md`. One gates lane. The ten live lanes from the PR's **Verify, live** block. The perf lane from its **Verify, perf** block. Two or more audit lanes, each with its own focus, that read the diff and the receipts and distrust the PR body. The root audits the receipts in the merge-ready report before the verdict.
- [ ] Judge every finding by the execution playbook's blocking rule. The verdict is clean when none blocks. A failure on trunk behavior in a lane marked `Regression lane against trunk.` is recorded against trunk and does not block the PR. A new head gets a fresh verdict, except for results that stay valid under the patch-id rule in `playbooks/shipping.md`.
- [ ] The owner stops at merge-ready. The operator squash-merges bottom-up. Do not force-push `native-compiler`. Do not raise `ProgramStepCap`, the 32MB native arena, or the 100000 list cap.

### Boot recipe, for every live lane

Each live lane runs on its own cloud VM at the PR head. Drive through `control-cli` from `cursor-team-kit`.

- [ ] `git fetch origin <head-branch> && git checkout <head SHA>`.
- [ ] Build with `dotnet build -c Release`. Do not start Station, Brain, payments, or testnet.
- [ ] Deliver input only through the control skill's commands. Name the read-only diagnostics.
- [ ] Save every screenshot to `/tmp/swarm-<pr-id>/worker-<n>/<slug>.png` and return the paths with the report.

## Record VIR and refuse host compilers (ML1)

**Depends on.** None as a docs and detector scaffold. Native self-host SHA-256 fixed-point remains unproven on `native-compiler` `0f758e702771ed3276ee553a76c7a86cc83846dd`. A later frontend that emits native PE waits on that proof or an operator waiver.

**Files.**

- [ ] Edit `docs/multilingual-source-compiler-plan.md` only if the detector contract changes.
- [ ] Create `docs/vir-ir.md` with VIR node kinds, language tags, and fail-closed diagnostics.
- [ ] Create failing tests that compile a `.c` file without `cl.exe` and refuse unknown languages.

**Build.**

- [ ] Add a language detector that keys off extension, then a bounded first-token sniff, and never starts `cl.exe`, `tsc`, `rustc`, or `gcc`.

**You see.**

- [ ] `vire compile other.c` prints `vire: no C frontend yet` (until ML2) and exit 2, with no child `cl.exe`.

**Verify, unit.** Tests alone are not sufficient verification. A PR is verified only when its unit, live, and perf boxes are all checked.

- [ ] New test `HostCompilerMustNotStart`. Run `dotnet test tests/Vire.Tests/Vire.Tests.csproj -c Release --filter FullyQualifiedName~HostCompiler`.

**Verify, live.** Tests alone are not sufficient verification. A PR is verified only when its unit, live, and perf boxes are all checked. Ten lanes on `grok-4.7-xhigh-fast` at the PR head, per the boot recipe.

- [ ] Lane 1. Regression lane against trunk. Run `samples/hello.vire` at trunk and head. If trunk lacks the detector, record that and gate hello stdout plus exit 0. Save `ml1-hello.png`. Pass when stdout matches and no host compiler process starts.
- [ ] Lane 2. Compile `samples/hello.vire` with `compiler.vire`. Save `ml1-vc.png`. Pass when `.vc` still seals as `VIRE-VC2`.
- [ ] Lane 3. Invoke `build` with a `.c` fixture on Linux. Save `ml1-build-c.png`. Pass when the message is the documented missing-tool or no-frontend text, not a silent `gcc` run.
- [ ] Lane 4. Pass a `.ts` file. Save `ml1-ts.png`. Pass when the diagnostic names TypeScript unsupported and exit is non-zero.
- [ ] Lane 5. Pass a mixed folder with `.vire` and `.c`. Save `ml1-mixed.png`. Pass when each file keeps its language tag and no file is silently skipped.
- [ ] Lane 6. Pass a file with a lying extension. Save `ml1-lie.png`. Pass when the sniff disagrees and the compiler stops with a hard diagnostic.
- [ ] Lane 7. Confirm `ps` during compile shows no `cl`, `tsc`, `rustc`, `gcc`. Save `ml1-ps.png`. Pass when the process list is empty of those names.
- [ ] Lane 8. Re-run `dotnet test` PathSsrf filter. Save `ml1-path.png`. Pass when path tests still pass.
- [ ] Lane 9. Open `docs/vir-ir.md` and grep VIR kinds. Save `ml1-ir-doc.png`. Pass when each kind in the test fixture is listed.
- [ ] Lane 10. Confirm caps still read 5000000, 32MB, 100000. Save `ml1-caps.png`. Pass when `ProgramStepCap` and arena constants are unchanged.

**Verify, perf.** Tests alone are not sufficient verification. A PR is verified only when its unit, live, and perf boxes are all checked.

- [ ] Metric. Wall time of interpreter `samples/hello.vire` at trunk and head. Detector work on a `.vire` hello.
- [ ] Probe. `bash tools/portable-check.sh` if present on head, else `dotnet run -c Release -- samples/hello.vire`, interleaved trunk then head.
- [ ] Baseline. Record the trunk hello wall first. PR 32 measured 0.054s on one Linux run. Re-measure. Do not treat 0.054s as a speed target.
- [ ] Rule. Head hello wall must stay within 2x trunk on the same machine. Detector-only work on hello must stay under 50ms extra absolute. Fail if a host compiler is spawned.

**Review gate.** None. ML1 is not review-gated.

**Merge.**

- [ ] Root's clean verdict at the exact head SHA.
- [ ] Bugbot triage done.
- [ ] Rebased onto current trunk after the verdict, patch-id unchanged.
- [ ] The owner squash-merges its own PR, or the root appends it to the base-branch stack and the operator lands it bottom-up.

## Lower a C subset instead of cl.exe (ML2)

**Depends on.** ML1.

**Files.**

- [ ] Create a C lexer, parser, and typecheck for the subset in Appendix B.
- [ ] Edit `VireBuild.cs` so `build` with kind `c` lowers through VIR. Delete `Process.Start` of `cl.exe` for that kind.
- [ ] Create `tests/conformance/c-subset/` fixtures.

**Build.**

- [ ] Parse a one-file C program with `int main(void)` that returns 0, lower to VIR, emit through the existing native or bytecode backend that ML1 named.

**You see.**

- [ ] `vire compile tests/conformance/c-subset/hello.c` prints `compiled` and exit 0 without `cl.exe`. Unsupported syntax prints `vire: C subset does not include <construct>` and exit 2.

**Verify, unit.** Tests alone are not sufficient verification. A PR is verified only when its unit, live, and perf boxes are all checked.

- [ ] `CSubsetHelloCompiles` and `CSubsetGotoIsHardError`. Run `dotnet test --filter FullyQualifiedName~CSubset`.

**Verify, live.** Tests alone are not sufficient verification. A PR is verified only when its unit, live, and perf boxes are all checked. Ten lanes on `grok-4.7-xhigh-fast` at the PR head, per the boot recipe.

- [ ] Lane 1. Regression lane against trunk. Run Vire hello at trunk and head. If trunk shells `cl.exe` for `build`, record that and gate the new no-child-process behavior plus hello stdout. Save `ml2-reg.png`. Pass when Vire hello still prints and C hello does not start `cl.exe`.
- [ ] Lane 2. Compile `hello.c` subset. Save `ml2-hello-c.png`. Pass when exit 0 and no MSVC include search.
- [ ] Lane 3. Feed `goto`. Save `ml2-goto.png`. Pass when the diagnostic names `goto` and no object file appears.
- [ ] Lane 4. Feed `inline asm`. Save `ml2-asm.png`. Pass when the diagnostic is hard-fail.
- [ ] Lane 5. Feed a VLA. Save `ml2-vla.png`. Pass when refused.
- [ ] Lane 6. Differential oracle. Run the same `hello.c` under system `gcc` in tests only. Save `ml2-oracle.png`. Pass when stdout matches and production code still has no `gcc` spawn.
- [ ] Lane 7. `foreign` on Linux still refuses. Save `ml2-foreign.png`. Pass when the message stays `could not open that dll` or the PR 32 documented text.
- [ ] Lane 8. Driver and Android `build` kinds stay missing-tool or unimplemented, not silently compiled. Save `ml2-kinds.png`. Pass when those kinds do not call `clang.exe`.
- [ ] Lane 9. Caps unchanged. Save `ml2-caps.png`. Pass when constants match trunk.
- [ ] Lane 10. Sibling intern and security branches untouched. Save `ml2-siblings.png`. Pass when `git merge-base` with those heads is unchanged by this diff.

**Verify, perf.** Tests alone are not sufficient verification. A PR is verified only when its unit, live, and perf boxes are all checked.

- [ ] Metric. Wall time of subset `hello.c` compile at head, plus trunk `samples/hello.vire` wall for regression.
- [ ] Probe. Interleave trunk Vire hello and head C hello plus Vire hello. Both sides must produce the Vire hello metric. Head also records C compile wall. No claimed ratio between unlike programs.
- [ ] Baseline. Record trunk Vire hello wall first.
- [ ] Rule. Head Vire hello must stay within 2x trunk. Head C hello compile has an absolute budget of 2s cold on the same class of machine as PR 32's 2.604s native Vire hello hex. Fail on timeout spawn of `cl.exe`.

**Review gate.** The operator reviews before merge.

- [ ] Copy lane 2 screenshots into `/tmp/media/ml2-review-hello.png`.
- [ ] Record a 30 to 60 second video of the change on a lane VM. Save it as `/tmp/media/ml2-review.mp4`.
- [ ] Post the screenshots and the video in chat. Stop at merge-ready. Wait for the operator's click.

**Merge.**

- [ ] Root's clean verdict at the exact head SHA.
- [ ] Bugbot triage done.
- [ ] Rebased onto current trunk after the verdict, patch-id unchanged.
- [ ] The operator lands after review.

## Compile FCG HTML and CSS as source (ML3)

**Depends on.** ML1.

**Files.**

- [ ] Create HTML and CSS frontends for the subset in Appendix B.
- [ ] Create fixtures copied from `sites/cpa/app.vire` outputs and `sites/landing/site.vire` strings, without claiming they are React.
- [ ] Edit nothing under sibling compiler or security branches.

**Build.**

- [ ] Parse the CPA HTML and CSS that Vire already writes under `sites/cpa/site/` after a local run, lower documents to VIR data plus a checked DOM emit, and refuse `<script>` until ML5 policy says otherwise.

**You see.**

- [ ] `vire compile sites/cpa/site/index.html` either compiles the document subset or, if that file is absent before a Vire emit, compiles a checked-in fixture and prints `compiled`. `<script src>` is a hard diagnostic.

**Verify, unit.** Tests alone are not sufficient verification. A PR is verified only when its unit, live, and perf boxes are all checked.

- [ ] `HtmlSubsetParsesCpaFixture` and `HtmlScriptTagIsHardError`. Run `dotnet test --filter FullyQualifiedName~HtmlSubset`.

**Verify, live.** Tests alone are not sufficient verification. A PR is verified only when its unit, live, and perf boxes are all checked. Ten lanes on `grok-4.7-xhigh-fast` at the PR head, per the boot recipe.

- [ ] Lane 1. Regression lane against trunk. Run `sites/cpa/app.vire` emit at trunk and head. If trunk only writes HTML as text, record that and gate unchanged emit paths plus the new compile diagnostic. Save `ml3-reg.png`. Pass when `app.vire` still writes under `site/` only.
- [ ] Lane 2. Compile the CPA HTML fixture. Save `ml3-html.png`. Pass when exit 0.
- [ ] Lane 3. Compile the CPA CSS fixture. Save `ml3-css.png`. Pass when exit 0.
- [ ] Lane 4. Feed `<script>`. Save `ml3-script.png`. Pass when refused.
- [ ] Lane 5. Feed a React JSX file. Save `ml3-jsx.png`. Pass when unsupported, no `tsc`.
- [ ] Lane 6. Landing page fixture with Google fonts link. Save `ml3-fonts.png`. Pass when the remote stylesheet is recorded as a network dependency, not fetched during compile unless the operator policy allows it.
- [ ] Lane 7. `api/fcgcpa.vire` still runs as Vire. Save `ml3-api.png`. Pass when `/health` path is unchanged in source.
- [ ] Lane 8. `vault.vire` still writes JS as text, not compiled. Save `ml3-vault.png`. Pass when no silent JS frontend claims success.
- [ ] Lane 9. Caps unchanged. Save `ml3-caps.png`. Pass when constants match.
- [ ] Lane 10. Confirm README of CPA still says it is not a React app. Save `ml3-readme.png`. Pass when that sentence remains.

**Verify, perf.** Tests alone are not sufficient verification. A PR is verified only when its unit, live, and perf boxes are all checked.

- [ ] Metric. Wall time of CPA HTML fixture compile at head, plus trunk `sites/cpa/app.vire` run wall.
- [ ] Probe. Interleave trunk app.vire and head app.vire plus HTML compile.
- [ ] Baseline. Record trunk `app.vire` wall first.
- [ ] Rule. Head `app.vire` within 2x trunk. HTML compile absolute budget 1s cold for the CPA fixture. Fail if the compiler fetches fonts.

**Review gate.** The operator reviews before merge.

- [ ] Copy lane 2 screenshots into `/tmp/media/ml3-review-html.png`.
- [ ] Record a 30 to 60 second video of the change on a lane VM. Save it as `/tmp/media/ml3-review.mp4`.
- [ ] Post the screenshots and the video in chat. Stop at merge-ready. Wait for the operator's click.

**Merge.**

- [ ] Root's clean verdict at the exact head SHA.
- [ ] Bugbot triage done.
- [ ] Rebased onto current trunk after the verdict, patch-id unchanged.
- [ ] The operator lands after review.

## Pin identities, SBOM, and advisory snapshots (ML4)

**Depends on.** ML1.

**Files.**

- [ ] Extend `deps.lock` or, if PR 19 `vire.lock` has landed, that format. Do not invent a second lock.
- [ ] Create advisory snapshot directory format, SBOM emit (CycloneDX JSON), and verify CLI.
- [ ] Create tests for missing snapshot, stale snapshot, hash mismatch, and offline fail-closed.

**Build.**

- [ ] At compile, hash every vendored source file, write a CycloneDX document, and match OSV plus NVD snapshots by package URL or CPE only when the snapshot content-hash matches the policy pin.

**You see.**

- [ ] `vire compile` with a lock mismatch prints `deps.lock does not match` (existing text in `Vire.cs`) or the `vire.lock` equivalent. With a missing advisory snapshot, compile warns or blocks per policy file. It never prints a made-up CVE id.

**Verify, unit.** Tests alone are not sufficient verification. A PR is verified only when its unit, live, and perf boxes are all checked.

- [ ] `DepsLockTests` plus `AdvisorySnapshotStaleBlocks`. Run `dotnet test --filter FullyQualifiedName~Lock|Advisory`.

**Verify, live.** Tests alone are not sufficient verification. A PR is verified only when its unit, live, and perf boxes are all checked. Ten lanes on `grok-4.7-xhigh-fast` at the PR head, per the boot recipe.

- [ ] Lane 1. Regression lane against trunk. Load `need` with matching `deps.lock` at trunk and head. Save `ml4-reg.png`. Pass when `hi` still prints from `DepsLockTests` equivalent.
- [ ] Lane 2. Flip last hex nibble. Save `ml4-nibble.png`. Pass when load refuses.
- [ ] Lane 3. Offline compile with pinned snapshot. Save `ml4-offline.png`. Pass when no network connect and the snapshot hash is logged.
- [ ] Lane 4. Stale snapshot older than policy max age. Save `ml4-stale.png`. Pass when warn or block per default block for `compile --release`.
- [ ] Lane 5. Version match without reachability labeled `advisory-match`. Save `ml4-match.png`. Pass when the finding says version match, not proven reachable.
- [ ] Lane 6. Unknown package with no CPE and no PURL. Save `ml4-unknown.png`. Pass when status is `unmatched`, not `clean`.
- [ ] Lane 7. Exception file with operator id and expiry. Save `ml4-exc.png`. Pass when the finding stays visible and compile continues only with `--allow-advisory`.
- [ ] Lane 8. SBOM lists vendored `deps/textkit` hash from `deps.lock`. Save `ml4-sbom.png`. Pass when the hash matches `00670c13cf1eb565dcd82dad8a38252cf4c8828ad31d92f1980dfe85c2f09e17`.
- [ ] Lane 9. No auto-rewrite of source to "fix" an advisory. Save `ml4-norewrite.png`. Pass when the fixture bytes are unchanged.
- [ ] Lane 10. Caps unchanged. Save `ml4-caps.png`. Pass when constants match.

**Verify, perf.** Tests alone are not sufficient verification. A PR is verified only when its unit, live, and perf boxes are all checked.

- [ ] Metric. Compile wall with snapshot already on disk versus first fetch. Network time is a separate number, never mixed into compiler time.
- [ ] Probe. Interleave trunk hello (no snapshot) and head hello with local snapshot. Both produce hello wall. Head also prints `advisory_ms` and `compile_ms` as two fields.
- [ ] Baseline. Record trunk hello wall first.
- [ ] Rule. Head `compile_ms` within 2x trunk hello. `advisory_ms` has no speed target. Fail if a cache hit skips a snapshot hash check.

**Review gate.** None. ML4 is not review-gated.

**Merge.**

- [ ] Root's clean verdict at the exact head SHA.
- [ ] Bugbot triage done.
- [ ] Rebased onto current trunk after the verdict, patch-id unchanged.
- [ ] The operator lands bottom-up.

## Bound compiler analyses at language edges (ML5)

**Depends on.** ML2 and ML3.

**Files.**

- [ ] Create taint, memory, and unsafe-API passes over VIR with step and node budgets.
- [ ] Create a false-positive and false-negative corpus under `tests/security-corpus/`. Do not store live exploit payloads.
- [ ] Create source-map records from VIR nodes back to original files.

**Build.**

- [ ] Walk VIR with a worklist dataflow. At a C `foreign` or HTML `href` edge, apply the policy diagnostic. Never rewrite the source to remove a finding.

**You see.**

- [ ] A fixture that copies fetch URL text into `write` reports `taint: network to file` with file, line, and evidence edges. A fixture with no such flow is silent. Unknown is `unproven`, never `safe`.

**Verify, unit.** Tests alone are not sufficient verification. A PR is verified only when its unit, live, and perf boxes are all checked.

- [ ] `TaintNetworkToWrite` and `TaintBudgetStops`. Run `dotnet test --filter FullyQualifiedName~Taint`.

**Verify, live.** Tests alone are not sufficient verification. A PR is verified only when its unit, live, and perf boxes are all checked. Ten lanes on `grok-4.7-xhigh-fast` at the PR head, per the boot recipe.

- [ ] Lane 1. Regression lane against trunk. Compile Vire hello at trunk and head. Save `ml5-reg.png`. Pass when hello stdout matches.
- [ ] Lane 2. Taint true positive fixture. Save `ml5-tp.png`. Pass when the diagnostic includes the source map.
- [ ] Lane 3. Taint true negative fixture. Save `ml5-tn.png`. Pass when no finding.
- [ ] Lane 4. Analysis hits node budget. Save `ml5-budget.png`. Pass when status is `unproven` and compile can still emit if policy is warn.
- [ ] Lane 5. Cross-language C pointer into Vire text. Save `ml5-xlang.png`. Pass when the edge is `unsafe` and not declared memory-safe.
- [ ] Lane 6. HTML `javascript:` URL. Save `ml5-jsurl.png`. Pass when blocked or warned per policy, source unchanged.
- [ ] Lane 7. Exception with audit note. Save `ml5-exc.png`. Pass when the SARIF-like log retains the finding.
- [ ] Lane 8. Fuzz one hour is not required. Run the existing `FuzzTests` filter. Save `ml5-fuzz.png`. Pass when 400 iterations still pass.
- [ ] Lane 9. Caps unchanged including analysis node cap as a new bound, not a raise of `ProgramStepCap`. Save `ml5-caps.png`. Pass when step cap is still 5000000.
- [ ] Lane 10. Confirm no CVE id is invented in diagnostics. Save `ml5-cve.png`. Pass when grep of output has no `CVE-20` unless the snapshot listed it.

**Verify, perf.** Tests alone are not sufficient verification. A PR is verified only when its unit, live, and perf boxes are all checked.

- [ ] Metric. Analysis node visits per compile, plus hello compile wall trunk vs head.
- [ ] Probe. Interleave trunk hello and head hello with analysis on. Print `analysis_nodes`.
- [ ] Baseline. Record trunk hello wall first.
- [ ] Rule. Head hello wall within 2x trunk with analysis in default bounded mode. Fail if analysis is unbounded or if cache reports clean without rehashing policy.

**Review gate.** The operator reviews before merge.

- [ ] Copy lane 2 screenshots into `/tmp/media/ml5-review-taint.png`.
- [ ] Record a 30 to 60 second video of the change on a lane VM. Save it as `/tmp/media/ml5-review.mp4`.
- [ ] Post the screenshots and the video in chat. Stop at merge-ready. Wait for the operator's click.

**Merge.**

- [ ] Root's clean verdict at the exact head SHA.
- [ ] Bugbot triage done.
- [ ] Rebased onto current trunk after the verdict, patch-id unchanged.
- [ ] The operator lands after review.

## Cache compiles without stale clean (ML6)

**Depends on.** ML4 and ML5.

**Files.**

- [ ] Create a compile cache keyed by source digest, toolchain digest, advisory snapshot digest, and policy digest.
- [ ] Create tests that flip each key and prove a miss.
- [ ] Document parallelism as deterministic shard by file path.

**Build.**

- [ ] Reuse a cache hit only after all four digests match. A policy or snapshot change invalidates "clean".

**You see.**

- [ ] Second compile of unchanged hello prints `cache hit` and identical artifact hash. Changing one advisory file byte prints `cache miss` and may change diagnostics.

**Verify, unit.** Tests alone are not sufficient verification. A PR is verified only when its unit, live, and perf boxes are all checked.

- [ ] `CacheHitRequiresFourDigests`. Run `dotnet test --filter FullyQualifiedName~CompileCache`.

**Verify, live.** Tests alone are not sufficient verification. A PR is verified only when its unit, live, and perf boxes are all checked. Ten lanes on `grok-4.7-xhigh-fast` at the PR head, per the boot recipe.

- [ ] Lane 1. Regression lane against trunk. Hello at trunk and head. Save `ml6-reg.png`. Pass when stdout matches.
- [ ] Lane 2. Warm hit. Save `ml6-hit.png`. Pass when artifact hash matches cold.
- [ ] Lane 3. Source byte flip. Save `ml6-src.png`. Pass when miss.
- [ ] Lane 4. Snapshot byte flip. Save `ml6-snap.png`. Pass when miss and no stale clean.
- [ ] Lane 5. Policy flip warn to block. Save `ml6-pol.png`. Pass when miss.
- [ ] Lane 6. Toolchain stamp flip. Save `ml6-tool.png`. Pass when miss.
- [ ] Lane 7. Parallel two files, run twice, compare hashes. Save `ml6-par.png`. Pass when deterministic.
- [ ] Lane 8. Cold vs warm times printed separately. Save `ml6-times.png`. Pass when both exist and are not mixed with network.
- [ ] Lane 9. Caps unchanged. Save `ml6-caps.png`. Pass when constants match.
- [ ] Lane 10. `compile-native.vire` hello hex path still functions if present. Save `ml6-native.png`. Pass when hex emit still runs or is skip-labeled, never a silent host compiler.

**Verify, perf.** Tests alone are not sufficient verification. A PR is verified only when its unit, live, and perf boxes are all checked.

- [ ] Metric. Cold and warm hello compile walls at head, trunk hello wall for regression.
- [ ] Probe. Interleave trunk hello, head cold, head warm.
- [ ] Baseline. Record trunk hello first.
- [ ] Rule. Head cold within 2x trunk for Vire hello. Warm must be less than or equal to cold on the same machine. Fail if warm skips digest checks. Do not publish a made-up nanosecond target.

**Review gate.** None. ML6 is not review-gated.

**Merge.**

- [ ] Root's clean verdict at the exact head SHA.
- [ ] Bugbot triage done.
- [ ] Rebased onto current trunk after the verdict, patch-id unchanged.
- [ ] The operator lands bottom-up.

## Close the program

- [ ] Every box above is checked with its evidence.
- [ ] Reply to the operator with the report the execution playbook names.

## Appendix A. Prototype evidence

This planning run did not prototype a frontend. The operator forbade compiler and runtime implementation. Unproven items stay unproven.

Measured or read on `native-compiler` `0f758e702771ed3276ee553a76c7a86cc83846dd` and live draft PRs.

- Native self-host inside 32MB is not proven. `NATIVE-COMPILER.md` records access violation at 32MB, 48MB, and 64MB, success at 96MB mapping with the allocator still wrong, and intern reverted. PR 31 is a later intern retry. Do not treat it as merged.
- Bytecode self-host path is `compiler.vire` to sealed `.vc`. DualMode tests exist. PR 20 still lists compiled arity mismatches.
- Native emit is Windows x64 PE from `compile-native.vire` plus `src/pe.vire`. No ELF or Mach-O on this HEAD.
- `VireBuild.Compile` starts `cl.exe` or `clang.exe` for `.c` (`VireBuild.cs`). That is the anti-pattern this program removes for kind `c`.
- Host `need` pins `deps.lock` SHA-256 (`Vire.cs` `LockedHash`, `DepsLockTests`). PR 19 `vire.lock` is draft on `phase1/pkg-lockfile`, not on this HEAD.
- PR 32 `GAP-CLOSURE.md` states Vire does not compile C#, Rust, or JavaScript. This program changes that goal. It does not claim current support.
- PR 32 measured interpreter hello 0.054s and `compile-native.vire` hello hex 2.604s on one Linux VM. Re-measure. Those numbers are not targets.
- PR 33, 34, and 36 own emit hot paths. PR 35 owns native sandbox. Do not duplicate them.
- FCG evidence in-repo. `sites/cpa/README.md` says the page is HTML and CSS written by Vire, not a React app. `api/fcgcpa.vire` is the web2 service. `sites/landing/site.vire` emits HTML and CSS with a Google fonts URL. `vault.vire` writes HTML, CSS, and JS as strings. No TypeScript, Rust, or npm lockfile is in this tree.
- `https://github.com/CannaMuffinMan/fcgcpa-prod` was not readable. `gh repo view` failed. `gh repo list CannaMuffinMan` returned only `vire`. See `docs/fcg-source-inventory.md`.
- PR 37 `cursor/selfhost-extend-0258` adds native `rt_extend`. PR 38 `cursor/native-runtime-32mb-0b9c` stacks intern onto the sandbox runtime. Neither is merged. Neither is a gen1/gen2 32MB proof. Do not treat them as complete.
- Late read-only explorers agreed with HEAD facts already used above and added these. `Vire.cs` has `CompilerStepCap` 50000000 for `compiler.vire` and `compile-native.vire` only. `ProgramStepCap` stays 5000000. There is no typed IR, no typechecker, and no compile cache on HEAD. `compiler.vire` `keyword` omits `now` while the C# lexer has it. `compile-native.vire` refuses a decimal point. The C sample already in tree is `samples/project-demo/hello.c`. `SECURITY.md` list cap 100000 and `NATIVE-COMPILER.md` 2000000 list cap are not the same constant. `article.txt` rejected mixing C, Python, and JavaScript into a Vire program. Canna's later request overrides that for direct foreign source compile as a separate frontend, not as C mixed inside one `.vire` file.

## Appendix B. Alternatives rejected

Shared VIR after per-language parse. Rejected alternative is per-language PE emitters copied from `compile-native.vire`. That duplicates `src/asm.vire` and cannot share advisory passes.

Rejected alternative is wrapping `tsc` or `gcc` and calling it Vire. `VireBuild.cs` already does that for C. Canna forbade it.

Rejected alternative is "compile all languages." Frontends are subsets with hard diagnostics. Full ISO C, ES202x, and HTML living standard are roadmap, not ML2 or ML3.

Rejected alternative is auto-patching vulnerable source. Findings stay diagnostics. Exceptions are explicit.

## Appendix C. Risks

- Native PE self-host missing. ML2 native emit of C can wait on interpreter or `.vc` VIR until the other agents prove a 32MB fixed-point. Watch `NATIVE-COMPILER.md` and PR 31.
- File overlap on `src/rt.vire` and `VirePaths.cs` with PR 31 to 36. Owners rebase and skip those hunks.
- CVE version match is not reachability. False positives from CPE string compare are documented by NIST CPE range fields and by OSV package-range records. Cite [CVE CPE applicability guide](https://www.cve.org/Resources/Roles/Cnas/CPEinCVERecordsGuide.pdf) and [OSV](https://osv.dev). Never invent CVE ids.
- Compiling a dependency's source does not remove its bugs. Advisories still apply to the algorithm.
- `foreign` is in-process native code with host rights (`VireForeign.cs`, GAP-CLOSURE G8). Analyses cannot prove memory safety across that edge.
- HTML compile must not fetch Google fonts at compile time (landing page). Network is advisory refresh, not page emit.
- License. Repo is MIT (`LICENSE`). Third-party frontends must not copy GCC or TypeScript sources in ways their licenses forbid. Unknown until a specific parser is chosen. Operator call.
- Caps. Do not raise 32MB, 5M steps, or list 100000.

## Appendix D. Links and reading list

Read before any implementation PR.

- This file.
- `NATIVE-COMPILER.md`, `SECURITY.md`, `GUIDE.md`, `article.txt`, `compiler.vire`, `compile-native.vire`, `Compiled.cs`, `Vire.cs` lexer and parser, `VireBuild.cs`, `VireForeign.cs`, `deps.lock`, `tests/Vire.Tests/DepsLockTests.cs`.
- Draft PRs 19, 20, 31, 32 (includes `GAP-CLOSURE.md`), 33, 34, 35, 36, 37, 38. Sibling agents [native self-host](https://cursor.com/agents/bc-8cf16e39-cfa4-56a5-b251-1f7bed790258) and [security](https://cursor.com/agents/bc-2f904236-ffd2-5503-88aa-9ec61df30b9c).
- `docs/fcg-source-inventory.md` and `docs/fcg-local-handoff.md`.
- [NVD](https://nvd.nist.gov), [CVE list](https://www.cve.org), [OSV](https://osv.dev), [GHSA](https://github.com/advisories), [CycloneDX](https://cyclonedx.org), [SPDX](https://spdx.dev), [SLSA](https://slsa.dev).
- ML1 gets `how` and `blast-radius`. ML2 and ML5 get `interrogate` on the operator's go. This planning run skipped a multi-model arena because the operator capped cost and forbade implementation.

Architecture notes the owner must keep.

Vire today has two compile paths on HEAD. `compiler.vire` tokenizes Vire, builds function lists, and writes sealed JSON bytecode (`Compiled.cs` `VIRE-VC2`). `compile-native.vire` tokenizes Vire and emits x64 into a PE (`src/pe.vire`) with a 32MB `VirtualAlloc` bump. Neither is a typed shared IR. The C# interpreter (`Parser` in `Vire.cs`) is a third frontend for the same language. Type checking is documented as planned and not present (PR 20).

Detection. One compilation unit has one language. Mixed programs are multiple units with explicit edges (`need`, `use`, later `foreign` with an ABI record). Extension maps `.vire`, `.c`, `.h`, `.html`, `.css`. A sniff that disagrees with the extension is a hard error. `.js` and `.ts` are unsupported until a later PR the operator names. Ecosystems (npm, crates, MSVC headers, React) are not languages. Stdlib, FFI, ABI, GC, async, reflection, macros, and build scripts are separate columns in the matrix below.

Ordered subsets justified by this repo, not a wish list.

1. Vire. Already parsed. Self-host still unproven. All later native proofs depend on it.
2. C subset that replaces `VireBuild` kind `c`. Evidence is `VireBuild.cs` and GAP-CLOSURE G8. Subset is `int`/`void` functions, pointers as unsafe VIR, no VLA, no `goto`, no inline asm, no `#include` of system headers until a vendored libc subset exists. `#include` of a path inside the sandbox may land after lock hashing.
3. HTML and CSS subsets for Forever Couch Gang pages. Evidence is `sites/cpa/README.md` and landing HTML. No React, no TypeScript in-repo.
4. Optional later. ES5 subset only if the operator wants `vault.vire` scripts compiled instead of written as text. C# subset only as a path to retire the .NET bootstrap. Rust, Go, Java, Python, Zig, Swift have no FCG inventory in this tree.

Compatibility matrix (current HEAD vs ambition).

| Unit | HEAD | After ML3 | Not promised |
| --- | --- | --- | --- |
| Vire source | Interpreter, `.vc`, PE emit (Windows) | Same | Self-host 32MB |
| C | Shell `cl.exe` | Direct subset | ISO C, kernel drivers |
| HTML/CSS | Strings from Vire | Direct subset | Browser engine |
| JS/TS | Served as static `.js` | Unsupported diagnostic | Node, React, tsc |
| Rust/Go/Java | Absent | Unsupported diagnostic | rustc compatibility |
| npm/cargo | Absent | Unmatched in SBOM | Full ecosystem |

Security design.

Identity. Prefer lock hash of file bytes (already `deps.lock`). Add version and PURL when a registry exists. Until then, identity is path plus SHA-256. SBOM is CycloneDX of those hashes. Vendor source in `deps/` is the whole package.

Advisories. Refresh is a separate command. Compile reads a pinned snapshot. Offline uses the pin or fail-closed. Stale means older than policy `max_age`. Matching uses OSV package ranges when a PURL exists, else NVD CPE ranges. A version hit is `advisory-match`. Reachability from VIR call graph is `reachable` only after ML5. Neither is a proof of exploitability. Unknown vulns stay unknown. Scanner misses from CPE mismatch are expected. See NVD CPE range fields `versionStartIncluding` and `versionEndExcluding`.

Policy. Default warn on `vire run` interpreter. Default block on `compile --release` and native emit. Exceptions are a signed or operator-owned file listing finding id, expiry, and reason. Diagnostics include source maps. No silent source mutation.

Threat model.

Malicious source can try unbounded parse, `#include` cycles, build hooks. Caps and no `Process.Start` of compilers are the controls. Malicious deps can match lock and still be buggy. Advisories help known ids only. Advisory integrity needs snapshot signatures (operator choice of TUF or checksum pin). Sandbox stays the existing path gate. Trusted bootstrap remains the C# runner until native gen2 matches gen1. Compiler capability is not universal remediation.

Validation.

Conformance fixtures per subset. Differential tests may use `gcc` or a browser HTML parser as oracles in CI, never in production. Fuzz uses existing `FuzzTests` plus new lexer fuzz. Security corpus holds labeled TP/TN/unproven cases without live exploits. No public CVE filing from this program.

What can be done now vs operator choice.

Now (after go). ML1 detector and docs. ML4 lock-based SBOM without a registry. HTML/CSS subset for checked-in FCG fixtures.

Needs operator. Whether ELF is a native backend (GAP-CLOSURE G5). Whether Linux `dlopen` exists (G8). Whether `vire.lock` from PR 19 supersedes `deps.lock`. Whether JS subset is wanted. Whether C `#include` of a vendored libc is in ML2. License of any parser copied from elsewhere. Advisory snapshot signature scheme.

No calendar and no cost figures. Host rebuild of `compile-native.vire` is recorded as about 60 minutes in `NATIVE-COMPILER.md`. That is a past observation, not a bid.

## Appendix E. First implementation prompt (do not run in this planning chat)

On an explicit operator GO after 8PM EST 2026-11-07, open a new agent on branch `cursor/ml1-detector-beb3` from current `origin/native-compiler`. Read this plan and `docs/fcg-source-inventory.md`. Implement only ML1. Do not edit sibling branches. Do not raise caps. Do not start `cl.exe`, `tsc`, `rustc`, or `gcc`. Do not merge. Do not deploy. Do not install tools on the operator's machines. Do not loop. Stop at a draft or ready PR as the operator names. Re-read `NATIVE-COMPILER.md` and PRs 31 to 36 before touching emit files. If self-host is still unproven, keep ML1 on the interpreter and `.vc` path.
