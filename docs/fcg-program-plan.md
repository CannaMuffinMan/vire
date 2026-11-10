# FCG in Vire rewrite program

This program rebuilds Forever Couch Gang in Vire after readiness gates pass. It is for later owners. This PR only lands the map. Payments stay off. Testnet stays out. Wrapping Node or Go does not count.

## How to read this

One box is one unit of work. Every box names the evidence that checks it. A nested box is a sub-step of the box above it. Check a box only when its evidence exists, a file, a log line, a screenshot, a test run, or a SHA. The body is a how-to. The appendices explain and record.

The program runs `pstack/skills/poteto-mode/playbooks/autopilot-stack.md`. The operator lands every PR. FCG-P1, FCG-P2, and FCG-P3 stop at merge-ready. Nothing merges in this program.

Tests alone are not sufficient verification. A PR is verified only when its unit, live, and perf boxes are all checked.

## Program checklist

### Arm the program

- [ ] State the protocol and this plan to the operator, then stop. Start execution only on the operator's explicit go.
- [ ] Read these from trunk at program start. Re-read them at every tick.
  - [ ] `git show origin/main:pstack/skills/poteto-mode/playbooks/autopilot-stack.md`
  - [ ] `git show origin/main:pstack/skills/swarm/SKILL.md`
  - [ ] `git show origin/main:pstack/skills/control-cli/SKILL.md`
  - [ ] `git show origin/main:pstack/skills/poteto-mode/playbooks/opening-a-pr.md`
  - [ ] `git show origin/main:pstack/skills/poteto-mode/SKILL.md`
- [ ] On the operator's go, arm the audit tick as `/loop 1h` with the tick prompt below. Never leave the cadence to memory.
- [ ] Use this tick prompt, verbatim. "Re-read the execution playbook from trunk. Audit the operation against it and fix drift in this tick. Probe every active lane and judge progress by side effects only. Stand down a stuck lane and dispatch its replacement now. Then post a short status message to the operator in chat only when the audit found a tracked change that no earlier status message reported, such as a PR opened, a code-ready head, a round launched or closed, a verdict, a merge, a stuck agent and the action taken, a blocker added or cleared, or a decision only the operator can make. Name every such change and nothing else. Do not repeat a table, the merged list, or an unchanged blocker. If the audit found none, end the turn with no reply text. Either way, log this tick's row in your decision trail. The row names the items reported, or none."
- [ ] On the operator's hold or stand-down, send every owner a zero-writes order at once.

### Spawn owners

- [ ] Spawn one owner per PR with the full lifecycle the execution playbook names.
- [ ] Follow this dependency graph. Start dependent work only after its parent merges, or base it on the parent branch when the execution playbook stacks.
  - [ ] FCG-P1 is first. Branch from `native-compiler`. It waits until draft PR 47 is proven or replaced.
  - [ ] FCG-P2 after FCG-P1.
  - [ ] FCG-P3 after FCG-P2. Then stop and re-estimate. Do not spawn landing, CPA, BDS, portals, or Couchy owners in this program.
- [ ] Hold the file boundaries. FCG-P1 touches only native runtime and `guest-health.vire`. FCG-P2 touches only a new VIR health guest plus tests. FCG-P3 touches only docs under `docs/fcg-*.md`.
- [ ] Hold the review gate. FCG-P1 and FCG-P2 change an interaction. They wait for the operator's review in chat with screenshots and a video before merge. FCG-P3 is not review-gated.

### PR mechanics, for every PR

- [ ] Resolve the forge once. Default to `gh`; if `command -v origin` succeeds and Origin can resolve the repository, use `origin pr` for every PR operation. Record any fallback to `gh`. Never require `gt`.
- [ ] Open the PR ready, never draft, per **Opening a PR**. This map PR is an operator-requested draft and is outside the execution playbook. Execution PRs open ready.
- [ ] Run the repo's lint and typecheck once before the PR-facing push. Push with hooks on.
- [ ] Run `/deslop` before each commit and `/no-comments` before review.
- [ ] Triage every Bugbot and security-reviewer comment per `../references/bugbot-triage.md`.
- [ ] Rebase onto current trunk before the code-ready report and babysit. Keep that merge base in fix rounds. Rebase again only at merge prep, on a `git merge-tree` conflict with trunk, on a CI failure that comes from a change on trunk, or when a known concurrent change to the same files lands.

### Verdict and merge, for every PR

- [ ] A full swarm runs once, at the code-ready head. Another full swarm runs only for new behavior, a redesign, or a large new diff. A rebase, a merge-conflict resolution, or a minor fix gets a single verifier at the new head, and a wording-only change gets none. Run each full swarm per `pstack/skills/swarm/SKILL.md`. One gates lane. The ten live lanes from the PR's **Verify, live** block. The perf lane from its **Verify, perf** block. Two or more audit lanes, each with its own focus, that read the diff and the receipts and distrust the PR body. The root audits the receipts in the merge-ready report before the verdict.
- [ ] Judge every finding by the execution playbook's blocking rule. The verdict is clean when none blocks. A failure on trunk behavior in a lane marked `Regression lane against trunk.` is recorded against trunk and does not block the PR. A new head gets a fresh verdict, except for results that stay valid under the patch-id rule in `playbooks/shipping.md`.
- [ ] The owner does not merge. The root appends the PR to the base-branch stack and the operator lands it bottom-up.

### Boot recipe, for every live lane

Each live lane runs on its own cloud VM at the PR head. Drive through `control-cli` from `cursor-team-kit`. HTTP guests also use `control-cli`. Do not wrap Node.

- [ ] `git fetch origin <head-branch> && git checkout <head SHA>`.
- [ ] Start the native guest or the C# host only when the PR names it. Wait for the listen log line. Never start `node dist/index.js`.
- [ ] Deliver input only through the control skill's commands. Name the read-only diagnostics.
- [ ] Save every screenshot to `/tmp/swarm-<pr-id>/worker-<n>/<slug>.png` and return the paths with the report.

## Prove native HTTP health (FCG-P1)

**Depends on.** Proven native sockets. Draft PR 47 at `b650932307ffce7efe887c6cac67098e7f406822` is the candidate and is not proven.

**Files.**

- [ ] Edit `src/rt-net.vire` only if the proven design lives there.
- [ ] Create `guest-health.vire` if PR 47 did not land it.
- [ ] Delete nothing in `api/` of fcgcpa-prod. This repo must not gain Node.

**Build.**

- [ ] Emit a gen1 Windows PE that answers `GET /health` without the C# `TcpListener` in `VireListen.cs`.

**You see.**

- [ ] A PE process prints a listen line, and `GET /health` returns HTTP 200 with `Content-Length`.

**Verify, unit.** Tests alone are not sufficient verification. A PR is verified only when its unit, live, and perf boxes are all checked.

- [ ] `tests/Vire.Tests/NativeNetTests.cs` covers `GET /health`. Run `dotnet test tests/Vire.Tests/Vire.Tests.csproj --filter NativeNet`.

**Verify, live.** Tests alone are not sufficient verification. A PR is verified only when its unit, live, and perf boxes are all checked. Ten lanes on `grok-4.7-xhigh-fast` at the PR head, per the boot recipe.

- [ ] Lane 1. Regression lane against trunk. Run `GET /health` against a gen1 PE at trunk and head. If trunk lacks the feature, record that and gate a 200 from the new PE plus a listen log line. Save `p1-trunk-health.png`. Pass when head returns 200 and trunk is recorded as lacking native listen.
- [ ] Lane 2. `GET /health` with no token on loopback. Save `p1-health.png`. Pass when the status is 200.
- [ ] Lane 3. `GET /missing`. Save `p1-missing.png`. Pass when the status is 404.
- [ ] Lane 4. Chunked POST. Save `p1-chunked.png`. Pass when the status is 400 or 501.
- [ ] Lane 5. Body over 1 MB. Save `p1-huge.png`. Pass when the status is 413.
- [ ] Lane 6. Path with `..`. Save `p1-dotdot.png`. Pass when the status is 404.
- [ ] Lane 7. Bind default is loopback. Save `p1-bind.png`. Pass when netstat shows 127.0.0.1 and not 0.0.0.0.
- [ ] Lane 8. Reserved port 7099. Save `p1-reserved.png`. Pass when the process refuses to listen.
- [ ] Lane 9. IAT has no `LoadLibraryA`. Save `p1-iat.png`. Pass when dumpbin or the emu log lists only the allowlisted `ws2_32` set named in PR 47.
- [ ] Lane 10. Interpreter `dotnet` `listen` still works for `serve.vire`. Save `p1-host.png`. Pass when C# host health still returns 200 so native work did not delete the host.

**Verify, perf.** Tests alone are not sufficient verification. A PR is verified only when its unit, live, and perf boxes are all checked.

- [ ] Metric. Time from accept to `GET /health` complete, plus RSS of the PE. Trunk lacks the feature, so also name the listen syscall path the diff adds and the end-to-end wait until 200.
- [ ] Probe. Drive 32 serial `GET /health` calls at trunk (record missing) and at the head, interleaved.
- [ ] Baseline. Record the trunk result first. Expect trunk cannot connect.
- [ ] Rule. Head p99 under 50 ms on loopback and RSS under 32 MB. Fail if either budget breaks. Do not invent a ratio against unlike trunk.

**Review gate.** The operator reviews before merge.

- [ ] Copy lane 2 screenshots into `/tmp/media/FCG-P1-review-health.png`.
- [ ] Record a 30 to 60 second video of the change on a lane VM. Save it as `/tmp/media/FCG-P1-review.mp4`.
- [ ] Post the screenshots and the video in chat. Stop at merge-ready. Wait for the operator's click.

**Merge.**

- [ ] Root's clean verdict at the exact head SHA.
- [ ] Bugbot triage done.
- [ ] Rebased onto current trunk after the verdict, patch-id unchanged.
- [ ] The root appends it to the base-branch stack and the operator lands it bottom-up.

## Clone Node health contracts (FCG-P2)

**Depends on.** FCG-P1.

**Files.**

- [ ] Create `guest-fcg-health.vire`.
- [ ] Edit tests under `tests/Vire.Tests/` for the contract.
- [ ] Delete nothing in fcgcpa-prod.

**Build.**

- [ ] Serve `GET /health` and `GET /api/health` from one VIR guest with payments env ignored.

**You see.**

- [ ] Both paths return 200 JSON on loopback.

**Verify, unit.** Tests alone are not sufficient verification. A PR is verified only when its unit, live, and perf boxes are all checked.

- [ ] New test names both paths. Run `dotnet test` for that class.

**Verify, live.** Tests alone are not sufficient verification. A PR is verified only when its unit, live, and perf boxes are all checked. Ten lanes on `grok-4.7-xhigh-fast` at the PR head, per the boot recipe.

- [ ] Lane 1. Regression lane against trunk. Run both health paths at trunk and head. If trunk lacks the guest, record that and gate 200 JSON on both paths. Save `p2-trunk.png`. Pass when head returns 200 JSON for both.
- [ ] Lane 2. `GET /health`. Save `p2-health.png`. Pass when status is 200 and the body parses as JSON.
- [ ] Lane 3. `GET /api/health`. Save `p2-api-health.png`. Pass when status is 200 and the body parses as JSON.
- [ ] Lane 4. `PAYMENTS_ENABLED=true` accidentally set. Save `p2-pay.png`. Pass when the process still does not call Stripe and health still 200.
- [ ] Lane 5. `GET /api/payment`. Save `p2-payment.png`. Pass when status is fail-closed, not 200 charge.
- [ ] Lane 6. Non-loopback bind without token. Save `p2-public.png`. Pass when bind is refused.
- [ ] Lane 7. Header `X-FCG-Token` wrong. Save `p2-token.png`. Pass when `/health` stays 200 and other paths 401 if a token is configured.
- [ ] Lane 8. Compare JSON keys to Node once `fcgcpa-prod` is readable. Save `p2-parity.png`. Pass when keys match or the lane records that the private repo is still 404.
- [ ] Lane 9. Process is a PE, not `node`. Save `p2-pe.png`. Pass when the image path ends in `.exe` or a native ELF the program names.
- [ ] Lane 10. Reserved ports still forbidden. Save `p2-ports.png`. Pass when 7099 is refused.

**Verify, perf.** Tests alone are not sufficient verification. A PR is verified only when its unit, live, and perf boxes are all checked.

- [ ] Metric. Both health paths p99, plus JSON parse errors at 0.
- [ ] Probe. 32 serial GETs on each path at trunk and head. Trunk may lack the guest.
- [ ] Baseline. Record trunk first.
- [ ] Rule. Head p99 under 50 ms. Fail on any parse error. No ratio against missing trunk.

**Review gate.** The operator reviews before merge.

- [ ] Copy lane 2 screenshots into `/tmp/media/FCG-P2-review-health.png`.
- [ ] Record a 30 to 60 second video of the change on a lane VM. Save it as `/tmp/media/FCG-P2-review.mp4`.
- [ ] Post the screenshots and the video in chat. Stop at merge-ready. Wait for the operator's click.

**Merge.**

- [ ] Root's clean verdict at the exact head SHA.
- [ ] Bugbot triage done.
- [ ] Rebased onto current trunk after the verdict, patch-id unchanged.
- [ ] The root appends it to the base-branch stack and the operator lands it bottom-up.

## Re-estimate after health (FCG-P3)

**Depends on.** FCG-P2.

**Files.**

- [ ] Edit `docs/fcg-rewrite-map.md`.
- [ ] Edit `docs/fcg-vire-capabilities.md`.
- [ ] Edit `docs/fcg-program-plan.md` only to check boxes with evidence.

**Build.**

- [ ] Write the measured health PE SHA and a go or no-go for Prisma.

**You see.**

- [ ] The map names a new Friday-class verdict with a SHA, not a hope.

**Verify, unit.** Tests alone are not sufficient verification. A PR is verified only when its unit, live, and perf boxes are all checked.

- [ ] `node` on `check-plan.mjs` against this file still exits 0. Run `node /home/ubuntu/.cursor/plugins/cache/cursor-public/9717366/de8ee15dd1194627d21eb5fcd41cb1873208dabb/skills/poteto-mode/scripts/check-plan.mjs docs/fcg-program-plan.md`.

**Verify, live.** Tests alone are not sufficient verification. A PR is verified only when its unit, live, and perf boxes are all checked. Ten lanes on `grok-4.7-xhigh-fast` at the PR head, per the boot recipe.

- [ ] Lane 1. Regression lane against trunk. Diff `docs/fcg-*.md` at trunk and head. Trunk before this program lacks the map. Record that and gate that head still contains the five ranked gaps. Save `p3-trunk.png`. Pass when the ranked list remains.
- [ ] Lane 2. Open `docs/fcg-rewrite-map.md`. Save `p3-map.png`. Pass when Friday infeasible remains unless FCG-P2 proved otherwise.
- [ ] Lane 3. Open `docs/fcg-access.md`. Save `p3-access.png`. Pass when missing Shopify theme and Tauri stay listed.
- [ ] Lane 4. Confirm no product `.vire` API rewrite landed. Save `p3-no-api.png`. Pass when `git diff --name-only` has only `docs/fcg-*.md`.
- [ ] Lane 5. Confirm payments still off. Save `p3-pay.png`. Pass when no file sets `PAYMENTS_ENABLED` to `true`.
- [ ] Lane 6. Confirm no testnet JSON. Save `p3-chain.png`. Pass when no chain fixture is added.
- [ ] Lane 7. `gh api` `fcgcpa-prod` once more. Save `p3-gh.png`. Pass when the SHA is recorded as readable or 404.
- [ ] Lane 8. PR 47 or successor SHA recorded. Save `p3-47.png`. Pass when the capabilities doc cites a proven SHA or still says unproven.
- [ ] Lane 9. Critical path still starts at native listen. Save `p3-path.png`. Pass when no owner is spawned for Next.
- [ ] Lane 10. Operator go required before Prisma. Save `p3-stop.png`. Pass when the doc says stop.

**Verify, perf.** Tests alone are not sufficient verification. A PR is verified only when its unit, live, and perf boxes are all checked.

- [ ] Metric. Word count of `docs/fcg-*.md` and time to render the map in `gh`.
- [ ] Probe. `wc -w docs/fcg-*.md` at trunk and head.
- [ ] Baseline. Record trunk first. Trunk may be zero files.
- [ ] Rule. Head stays docs-only. Fail if any non-docs path appears. No runtime budget beyond that.

**Review gate.** None. FCG-P3 is not review-gated.

**Merge.**

- [ ] Root's clean verdict at the exact head SHA.
- [ ] Bugbot triage done.
- [ ] Rebased onto current trunk after the verdict, patch-id unchanged.
- [ ] The root appends it to the base-branch stack and the operator lands it bottom-up.

## Close the program

- [ ] Every box above is checked with its evidence.
- [ ] Reply to the operator with the report the execution playbook names.

## Appendix A. Prototype evidence

No prototype ran. The operator forbade product code, payments, and testnet. Native HTTP remains unproven on PR 47. Private `fcgcpa-prod` returned 404 to this token, so route bodies were not re-read.

## Appendix B. Alternatives rejected

Wrap Node with a VIR supervisor. Rejected because wrapping is not built by Vire.

Port Next 16 this week. Rejected because the compiler has no React runtime.

Use C# `VireListen.cs` as the Friday demo and call it native. Rejected because the host is .NET.

Copy `api/fcgcpa.vire` as the product API. Rejected because the inventory showed it is the wrong codebase.

## Appendix C. Risks

Native sockets never land. FCG-P1 stays blocked. Watch PR 47 CI.

This token never reads `fcgcpa-prod`. FCG-P2 parity lane records 404 forever. Watch `gh repo list`.

Someone enables Stripe to "finish" billing. Watch env and this plan's fail-closed boxes.

Someone imports testnet to make explorer tests green. Watch FCG-P3 lane 6.

Arena 32 MB and step caps get raised to compile Next. Watch `NATIVE-COMPILER.md`.

`pstack/` skills are not in this repo. Arm boxes that `git show origin/main:pstack/...` will fail until those files exist. Use the plugin copies under `~/.cursor/plugins` and record the fallback.

HTTP live lanes have no true GUI. `control-ui` does not apply. `control-cli` plus curl is the drive path. That is a surface risk.

## Appendix D. Links and reading list

Read `docs/fcg-rewrite-map.md` and every unit file before FCG-P2.

Read `GUIDE.md`, `SECURITY.md`, `NATIVE-COMPILER.md`, `VireListen.cs`, and PR 47 before FCG-P1.

FCG-P1 gets `pstack/skills/how/SKILL.md` and `pstack/skills/interrogate/SKILL.md` if those files exist on trunk. FCG-P3 does not.

Trail per `pstack/skills/show-me-your-work/SKILL.md` when execution starts. This map PR keeps the trail in the docs themselves.
