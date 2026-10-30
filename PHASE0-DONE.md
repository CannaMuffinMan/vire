# Phase 0 done-criteria: proof map

Base: `phase0/c8-c9`. Close-out on `phase0/closeout`. Each line is a Phase 0 done-criterion from `VIRE-ROADMAP.md` and the check that proves it.

Sealed `.vc` envelopes use a random AES-256-GCM nonce, so two seals of the same payload are not identical files. The compiler artifact that must match is the **unsealed payload**. CI dumps that payload and compares it byte-for-byte.

| Criterion | Proof |
|---|---|
| CI green on `net10.0` | `vire.csproj`, `tests/Vire.Tests/Vire.Tests.csproj` target `net10.0`; `windows/vire.windows.csproj` targets `net10.0-windows`. `global.json` pins SDK `10.0.403`. Workflow `.github/workflows/check.yml` sets `dotnet-version: 10.0.x` on build, test, selfhost, selfhost-windows, native-windows, and publish. Tests: `HarnessTests.ProjectsTargetNet10AndWarningsAreErrors`, `HarnessTests.SdkAndProjectsAreNet10`, `HarnessTests.WorkflowPinsActionsToFullShas`. |
| Stage-1 `.vc` == stage-2 `.vc` byte-for-byte | `tools/selfhost-check.sh` and `tools/selfhost-check.ps1` compile stage 1, 2, and 3, compare `payload-sha256`, then `payload-write` each `.vc` and `cmp -s` / `Compare-Object` the unsealed bytes. Mismatch exits 1. CI jobs `selfhost` and `selfhost-windows` run those scripts. Tests: `HarnessTests.SelfhostChecksCompareUnsealedPayloadBytes`, `SealTests.PayloadWriteDumpsUnsealedBytes`. |
| No binaries in git | `.gitignore` excludes `bin/`, `obj/`, `dist/`, `publish/`, `*.exe`, `*.dll`, `*.pdb`, `*.hex`. CI job `tracked-binaries` runs `tools/check-tracked-binaries.sh`, which fails on tracked `exe`/`dll`/`pdb`/`hex`, on `.vc` outside `tests/fixtures/`, and on `bin/` `obj/` `dist/` `publish/` paths. Tests: `HarnessTests.GitTracksNoBinaries`, `HarnessTests.GitIndexHasNoBuildBinaries`. Allowed fixture: `tests/fixtures/old-xor.vc` (refused at open by `SealTests.OldXorSealIsRefused`). |
| Docker images pinned by digest; Actions pinned by full commit SHA | `Dockerfile` `FROM` lines use `@sha256:` 64-hex digests. Every `uses:` in `check.yml` is `owner/action@` plus a 40-hex SHA. Tests: `HarnessTests.DockerfileBasesArePinnedByDigest`, `HarnessTests.WorkflowPinsActionsToFullShas`. |
| Crash suite never kills the process | `CrashTests.CrashCorpusRunsInOneProcess` runs every `tests/crash/*.vire` plus generated depth/width/huge/while fixtures through `Program.Execute` in the test process (not `Process.Start`). Exit code must be 0–2, never 3 (`internal error`). `Environment.ProcessId` is unchanged. `CrashTests.CrashFixturesStayAlive` uses the same in-process `Run`. `JsonAndShowRefuseAdversarialValuesInProcess` covers JSON/`say` without leaving the process. |
| Every Phase 0 item has a passing test | C1–C9 coverage remains in `HarnessTests`, `CrashTests`, `ExprDepthTests`, `PathSsrfTests`, `SealTests`, `ListenTests`, `ChainTests`, `ServeTests`, `SuiteTests`. This file maps the Phase 0 **done-line** (roadmap §5) to the checks above. |

## What this close-out does not claim

- Stage-1 and stage-2 **sealed files** on disk are not byte-identical: GCM nonces are random by design (`SealTests.RoundTripAndNonceDiffer`). The **payload** is identical.
- Authorization for `POST /block` is still open (C7 carry-forward).
- No FCGBC/testnet code was added here.
