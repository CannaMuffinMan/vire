# VIRE 4-hour rollup (proof-only)

This branch is not a merge unit. Land the source PRs, then this rollup only as an integration check.

## Base

`cursor/vire-cleanup-integration` at `6693e0e5d78c9df775d0531a39a14a574239cfac`.

## Merged (normal merge, no rebase)

| PR | head | notes |
|---|---|---|
| #144 | `4b618c2d` | clean |
| #145 | `29ba1ef1` | clean |
| #146 | `3add41ce` | clean |
| #147 | `67603360` | conflict `docs/FINISH-LIST.md`. Kept 144-146 row deletions. Dropped tools-ci rows 147 implements. |
| #148 | `880ec761` (`cursor/pg-scram-plus-e596`) | `65fc7692` then `73ad94ab` (fail-closed no bind / MITM cert). Re-merged `880ec761` clean: handshake leaf export + `tls_end_point` RFC 5929. Fail-closed kept (`channel binding` when no bind). Did not fold #159. |
| #149 | `16f7f4f8` (`cursor/windows-tls-0630`) | first merge `ed926c6a`, then re-merged `16f7f4f8` (no PersistKeySet on ephemeral PFX). Clean both times. |
| #150 | `8f460c49` (`cursor/pe-dns-json-chain-567f`) | conflict `tools/couchstation-windows-all.ps1`. Kept `native-forms`. Dropped MZ-only proxy block. Writes `data/couchstation-windows-all-results.md`. |
| #151 | `36d2e644` (`cursor/native-405-proxy-ws-33ca`) | conflict `docs/FINISH-LIST.md` only. Packed blobs did not conflict in git. See below. |
| #152 | `d1d72b4a` (`cursor/vireapk-finish-e5fe`) | clean. Closes `VireApk.Pack` FINISH-LIST row. No guest builtin. |
| #153 | `cf7cdd07` (`cursor/fcgbds-worker-port-efbf`) | clean. JSON heartbeat `sessionId` on 4-param route plus worker env cases. |
| #154 | `6780fa07` (`cursor/serve-builtin-drop-54a7`) | conflict `docs/FINISH-LIST.md` and `CHANGELOG.md`. Dropped serve rows. Kept VireApk closed note. Did not restore sha256/VireApk rows from 154's stale list. |
| #155 | `0fc7aeae` (`cursor/finish-list-closer-6bc4`) | `rt_for_more` list.buf + native-forms fixtures + `tools/native-forms-linux.sh`. Overlaps: see below. |
| #156 | `8ae2e4a5` (`cursor/portal-edge-contracts-11a0`, later than `8bc84095`) | in-tree rpc-portal/edge/dev-portal/fcgbds-dashboard goldens host==native, `docs/fcg-contracts-missing.md`, unauth sidecar argv0 fix. Clean merge. |
| #157 | `90a770fd` (`cursor/win-pe-pg-redis-tls-c046`) | VireProof `pg-tls-stub` / `redis-tls-stub` + Windows prove scripts. `src/rt-pg.vire` unchanged: kept #148 PLUS fail-closed (`pg_scram_select`). CouchStation already invoked `pg-tls-prove-windows.ps1` / `redis-tls-prove-windows.ps1`. Combined `vire-proof` usage with #155 `http-echo`/`ws-prove`. |
| #160 | `a36edcf6` (`cursor/vire-4h-tls-segv`) | ELF `rt_tls_wrap`: hostname box at `[rbp-48]`, C string at `tls_nameptr` (was TCP handle). Clean on top of #148 `880ec761` `rt-tls` (`tls_end_point` kept). `tools/pg-tls-stub-elf.sh`. Did not fold #159. |

## Overlaps (#155 vs #146 / #147)

One implementation each. No double-include.

- **Windows csproj glob.** #146 and #155 both use `<Compile Include="..\*.cs" />`. Kept **#146**. Identical glob; #146 already on the rollup with `VireApk.cs` in the Windows compile set.
- **CouchStation host-vs-PE scripts** (`rebuild-proxy-windows.ps1`, `rebuild-proxy-ws-windows.ps1`, `apigo-ws-windows.ps1`, `rebuild-obs-listen-windows.ps1`, `rebuild-sop-proxy-windows.ps1`, `native-forms.ps1`). Kept **#147**. Shared `native-loopback-proof.ps1`, FAIL_BEFORE at `6693e0e5`, host-vs-native compile. #155 rewrote the same files around `vire-proof http-echo` / `ws-upstream` from the cleanup base; weaker than the #147 harness already merged. Took #155 `tools/VireProof/ProofNet.cs` as extra helper, not as the CouchStation proof path.
- **native-forms fixtures.** Took **#155** `data/native-forms/try-miss.vire` and `for-list.vire`, `src/rt.vire` `rt_for_more`, `NativeFormsTests`, `tools/native-forms-linux.sh`. Harness stays #147.
- **couchstation-windows-all.ps1.** Kept rollup one-shot (markdown results, gaps check, native-forms once). Dropped #155 duplicate `native-forms` invocation and MZ-only proxy compile block.
- **FINISH-LIST residuals #155 marked blocked.** On this tip they are **done** by earlier PRs: fractional lexer **#145**, guest `sha256_bytes` pad+compress+IV **#144**, packed JSON regen `tools/pack-rt-net-json.py` **#144**.

## Packed rt-net / listen blobs (#150 vs #151)

Git auto-merged `src/rt-net.vire`. No conflict markers. Byte check after the merge:

- `src/rt-net-r4-blob.txt` matches #150 (`8f460c4`), not #151. DNS rbx/share-7 pack kept.
- `src/rt-net-json-blob.txt` matches #144 (`4b618c2`), not the stale #151 copy.
- `src/rt-net-blob.txt` is identical on #150 and #151.
- `src/rt-net.vire` is #144 park comments plus #151 `land_st_405`, POST body overlay at blob+2728, and in-process WS echo overlay.

Re-run on this tip:

```
python3 tools/pe-windows-gaps-check.py
bash tools/native-405-proxy-ws-check.sh
```

## Not merged yet

- #143 (`51de3c2f`) host/native POST `/block` deny-by-default is already on `6693e0e5`. Do not merge the `native-compiler` branch. It would delete native listen.
- `cursor/vire-4h-auth-compare` is not on origin yet. Merge it when the branch exists.
- #148 is `880ec761` on this tip (leaf export + RFC 5929 `tls_end_point`). Re-merge if `cursor/pg-scram-plus-e596` moves again. Do not fold #159.

## CouchStation one-shot (Windows PC only)

Linux ELF is not PE proof. Do not touch Defender. Do not reboot. Unset `VIRE_BUDGET` (the script does this).

```
git fetch origin cursor/vire-4h-rollup
git checkout cursor/vire-4h-rollup
Remove-Item Env:VIRE_BUDGET -ErrorAction SilentlyContinue
$env:VIRE_HEADLESS = "1"
powershell -NoProfile -File tools/couchstation-windows-all.ps1
```

Results: `data/couchstation-windows-all-results.md` and `data/couchstation-windows-all.log`.

## Linux proof commands (this rollup)

```
python3 tools/pe-windows-gaps-check.py
bash tools/native-405-proxy-ws-check.sh
bash tools/rebuild-fcgbds-worker-diff.sh
bash tools/rebuild-fcgbds-heartbeat-diff.sh
bash tools/rebuild-unauth-sidecar-diff.sh
bash tools/prove-fcg-portal-contracts.sh
bash tools/rebuild-portal-diff.sh
bash tools/pg-scram-plus-prove.sh
bash tools/pg-tls-stub-elf.sh
bash tools/windows-tls-lane-check.sh
bash tools/native-elf-selfhost.sh
dotnet test tests/Vire.Tests/Vire.Tests.csproj -c Release --nologo --filter FullyQualifiedName~ServeTests
dotnet test tests/Vire.Tests/Vire.Tests.csproj -c Release --nologo --filter FullyQualifiedName~NativeFormsTests
dotnet test tests/Vire.Tests/Vire.Tests.csproj -c Release --nologo
```

#151 keeps POST bodies on packed 3-param listen. #153 heartbeat uses 4-param `route`. Re-run both FCGBDS scripts after both PRs are in.

## Proof on tip `4ea94564` (Linux agent)

Caps unchanged: arena 33554432, list 100000, steps 5000000, itemCap 1e6.

- `python3 tools/pe-windows-gaps-check.py` PASS (r4 rbx, share-7, json map).
- `bash tools/native-forms-linux.sh` PASS. Host==native `try-miss` and `for-list` (6).
- ServeTests + NativeFormsTests: 5 passed, 0 skipped.
- `bash tools/pg-scram-plus-prove.sh` PASS at `880ec761` fold (`plus-only no bind REJECT` / `tls plus no bind REJECT` / handshake leaf cbind).
- `bash tools/windows-tls-lane-check.sh` PASS (no PersistKeySet). Linux ELF is not PE proof.
- `bash tools/native-405-proxy-ws-check.sh` PASS (host/native 405, POST `from-listen`, apigo-ws).
- Aggregated dashboard GET 405: `tools/rebuild-portal-diff.sh` `== dashboard (no dist) == match fcgbds-dashboard-go.json` (GET `/api/challenge-verify` and `/api/reviewers-heartbeat` HTTP 405 on host and native). #156's own base still 200; this tip includes #151 packed `"status":405` overlay.
- `bash tools/native-elf-selfhost.sh` at `ac2c29d` (post-#148 `880ec761`, pre-#160): gen1=gen2 x3 `e93e868d0a00cf43f3f090fe5d62a955347f0f7ad9d092eb881ff8f086ba048b`.

## ELF `tls_wrap` hostname box (#160)

**SEGV fixed.** Pre-#160 ELF `rt_tls_wrap` stored the TCP handle at `[rbp-48]`; `SSL_set1_host` read handle+8 and SIGSEGV'd (exit 139) after SSLRequest. #160 stores the hostname box there (`76,137,77,208` / `lea rax,[r9+8]` into `tls_nameptr`) like PE wrap.

`bash tools/pg-tls-stub-elf.sh` on this tip: **host** `PG TLS PROVE pass` (auth trust). **ELF no longer 139**; wrap handshake proceeds, then **`FAIL channel binding`** (exit 1). That is #148 fail-closed when ELF `tls_peer_cert` / `tls_end_point` does not yield a cbind vs the .NET stub. Do not skip. Not PE proof.

## Native rpc-portal “missing header terminator” (Lane K)

Not a small rollup merge of the wrong packed blob. `tools/rebuild-unauth-sidecar-diff.sh` `http_call` raises `missing header terminator` when `recv` has no `\r\n\r\n`.

Reproduced on this tip with the sidecar compile path (`listen with 0`, `compile-native` ELF of `tests/rebuild/guests/rpc-portal-go.vire`):

- Host GET `/api/health`: 159 bytes `HTTP/1.1 200 OK` … `\r\n\r\n{"ok":true}`.
- Native ELF: **SIGSEGV (139)** on the first GET; **raw_len 0**; no header terminator because the process died, not because it sent a body-only JSON 200.

Same class as FCGBDS worker/heartbeat native HTTP. Packed 1-param `listen` guest vs host `VireListen`. Do not skip. Do not treat as a 3-param POST overlay mix-up.

Caps stay arena 33554432, list 100000, steps 5000000, itemCap 1e6.

## Env-only xUnit failures (this Linux agent)

Do not skip or xfail these. They fail closed when tools are missing.

- `DriverImageTests.LinkedDriverImageIsPe` (`the C compiler is not installed`)
- `ToolchainTests.BuildCompilesCAndroidAndDriver` (`ANDROID_NDK_HOME` / `ANDROID_NDK_ROOT`)
- `ApkTests.PackWritesApkWithManifest` (`ANDROID_SDK_ROOT` / `ANDROID_HOME` / `JAVA_HOME`)
- `AndroidSoTests.AndroidBuildEmitsElfSharedLibrary` (`ANDROID_NDK_HOME` / `ANDROID_NDK_ROOT`)

Machines with SDK/NDK and a C compiler must pass those tests. Linux ELF is not Windows PE proof. GitHub Actions billing-lock is ignored.
