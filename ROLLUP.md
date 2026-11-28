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
| #148 | `880ec761` (`cursor/pg-scram-plus-e596`) | `65fc7692` then `73ad94ab` (fail-closed no bind / MITM cert). Re-merged `880ec761` clean: handshake leaf export + `tls_end_point` RFC 5929. Fail-closed kept (`channel binding` when no bind). |
| #149 | `16f7f4f8` (`cursor/windows-tls-0630`) | first merge `ed926c6a`, then re-merged `16f7f4f8` (no PersistKeySet on ephemeral PFX). Clean both times. |
| #150 | `8f460c49` (`cursor/pe-dns-json-chain-567f`) | conflict `tools/couchstation-windows-all.ps1`. Kept `native-forms`. Dropped MZ-only proxy block. Writes `data/couchstation-windows-all-results.md`. |
| #151 | `36d2e644` (`cursor/native-405-proxy-ws-33ca`) | conflict `docs/FINISH-LIST.md` only. Packed blobs did not conflict in git. See below. |
| #152 | `d1d72b4a` (`cursor/vireapk-finish-e5fe`) | clean. Closes `VireApk.Pack` FINISH-LIST row. No guest builtin. |
| #153 | `cf7cdd07` (`cursor/fcgbds-worker-port-efbf`) | clean. JSON heartbeat `sessionId` on 4-param route plus worker env cases. |
| #154 | `6780fa07` (`cursor/serve-builtin-drop-54a7`) | conflict `docs/FINISH-LIST.md` and `CHANGELOG.md`. Dropped serve rows. Kept VireApk closed note. Did not restore sha256/VireApk rows from 154's stale list. |
| #155 | `0fc7aeae` (`cursor/finish-list-closer-6bc4`) | `rt_for_more` list.buf + native-forms fixtures + `tools/native-forms-linux.sh`. Overlaps: see below. |
| #156 | `8ae2e4a5` (`cursor/portal-edge-contracts-11a0`, later than `8bc84095`) | in-tree rpc-portal/edge/dev-portal/fcgbds-dashboard goldens host==native, `docs/fcg-contracts-missing.md`, unauth sidecar argv0 fix. Clean merge. |
| #157 | `90a770fd` (`cursor/win-pe-pg-redis-tls-c046`) | VireProof `pg-tls-stub` / `redis-tls-stub` + Windows prove scripts. `src/rt-pg.vire` unchanged: kept #148 PLUS fail-closed (`pg_scram_select`). CouchStation already invoked `pg-tls-prove-windows.ps1` / `redis-tls-prove-windows.ps1`. Combined `vire-proof` usage with #155 `http-echo`/`ws-prove`. |
| #160 | `a36edcf6` (`cursor/vire-4h-tls-segv`) | ELF `rt_tls_wrap`: hostname box at `[rbp-48]`, C string at `tls_nameptr` (was TCP handle). Clean on top of #148 `880ec761` `rt-tls` (`tls_end_point` kept). `tools/pg-tls-stub-elf.sh`. |
| #159 | `9277ce8` (`cursor/vire-4h-auth-compare-946f`) | Folded after #160. Byte-range reconcile vs packed #150/#151/#155; see below. |
| #162 | `a657a63d` (`cursor/vire-4h-elf-cbind`) | After #159. ELF `rt_tls_peer_cert` stores `i2d_X509` length (`mov [rdx],rcx` after second i2d). MITM guest + `pg-tls-cbind-dump.sh`. Clean merge. |

## Overlaps (#155 vs #146 / #147)

One implementation each. No double-include.

- **Windows csproj glob.** #146 and #155 both use `<Compile Include="..\*.cs" />`. Kept **#146**. Identical glob; #146 already on the rollup with `VireApk.cs` in the Windows compile set.
- **CouchStation host-vs-PE scripts** (`rebuild-proxy-windows.ps1`, `rebuild-proxy-ws-windows.ps1`, `apigo-ws-windows.ps1`, `rebuild-obs-listen-windows.ps1`, `rebuild-sop-proxy-windows.ps1`, `native-forms.ps1`). Kept **#147**. Shared `native-loopback-proof.ps1`, FAIL_BEFORE at `6693e0e5`, host-vs-native compile. #155 rewrote the same files around `vire-proof http-echo` / `ws-upstream` from the cleanup base; weaker than the #147 harness already merged. Took #155 `tools/VireProof/ProofNet.cs` as extra helper, not as the CouchStation proof path.
- **native-forms fixtures.** Took **#155** `data/native-forms/try-miss.vire` and `for-list.vire`, `src/rt.vire` `rt_for_more`, `NativeFormsTests`, `tools/native-forms-linux.sh`. Harness stays #147.
- **couchstation-windows-all.ps1.** Kept rollup one-shot (markdown results, gaps check, native-forms once). Dropped #155 duplicate `native-forms` invocation and MZ-only proxy compile block.
- **FINISH-LIST residuals #155 marked blocked.** On this tip they are **done** by earlier PRs: fractional lexer **#145**, guest `sha256_bytes` pad+compress+IV **#144**, packed JSON regen `tools/pack-rt-net-json.py` **#144**.

## Packed rt-net / listen blobs (#150 vs #151 vs #159)

Git auto-merged `src/rt-net.vire`. No conflict markers. Byte-range reconcile after folding #159 `9277ce8` (do not take #159's cleanup r4 wholesale):

- **3-param `src/rt-net-blob.txt`:** take #159 (11519 bytes). Cleanup was 11420. Insertion is the body-park jmp at blob+0xAA8 (`e9` to the appended trampoline) plus 99 appended bytes. #151 overlay still jmps 0xAA8 to `pr_body_fix` / `land_st_405` / WS echo; 0xAA8 was already `e9` on #159.
- **r4 `src/rt-net-r4-blob.txt`:** keep #150 length 18855 (DNS rbx/share-7), not #159's cleanup 18843. Apply #159's fail-closed cap only: `cmp r8,0x1000` and `jbe +6` → `jae cl_401` (`0f83…` to pin `cl_401` 0x1bb4) plus `mov r8d,0x1000` at the 256→4096 immediate sites. Prefix through blob+8159 (listen/client) matches cleanup; DNS starts at `dns_hostok` 0x1fd4.
- **`src/rt-net-json-blob.txt`:** still #144, not #151.
- **`guest-chain.vire`:** #159 4-param `route with method, path, body, head` so compile uses r4.

#159 on cleanup r4: authorized native POST `/block` 200. This rollup's #150 r4 4-param listen SIGSEGV on first HTTP (rcx=0 in `rt_net_afterroute`). Isolated compile of the same 4-param guest against #159's 18843 blob returns 200. Do not drop DNS to recover POST. Lane N (`cursor/vire-4h-listen-recv0`) also patches packed listen and must be range-reconciled with this #159 3-param park + r4 4096 when it lands. Lane M is folded as #162.

Re-run on this tip:

```
python3 tools/pe-windows-gaps-check.py
bash tools/native-405-proxy-ws-check.sh
bash tools/post-block-auth-native.sh
```

## Not merged yet

- #143 (`51de3c2f`) host/native POST `/block` deny-by-default is already on `6693e0e5`. Do not merge the `native-compiler` branch. It would delete native listen.
- Lane N `cursor/vire-4h-listen-recv0` (from `e4f2b1a`) will PR into this rollup. It patches packed listen; rebase onto the #159 r4/3-param reconcile.
- #161 `cursor/vire-4h-pe-peercert` (into #148). Waiting for the follow-up head. With #162+#161 together, `tools/pg-tls-stub-elf.sh` and `PgRedisTlsStubTests` should pass real PLUS cbind and the ELF MITM guest should fail closed. Do not fold the current `2d4b85e8` until that head is named.
- #148 is `880ec761` on this tip (leaf export + RFC 5929 `tls_end_point`). Re-merge if `cursor/pg-scram-plus-e596` moves again.

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
bash tools/post-block-auth-native.sh
dotnet test tests/Vire.Tests/Vire.Tests.csproj -c Release --nologo --filter "FullyQualifiedName~HeaderSecretCompareTests|FullyQualifiedName~BlockAuthTests"
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
- `bash tools/native-elf-selfhost.sh` at `481c865` (post-#148 `880ec761` + #160): gen1=gen2 x3 `d38b4a9b38f91e8a00bd54eda5c7aebb467bfd69f5a9e31eff0cd1afe768245f`.

## ELF `tls_wrap` hostname box (#160)

**SEGV fixed.** Pre-#160 ELF `rt_tls_wrap` stored the TCP handle at `[rbp-48]`; `SSL_set1_host` read handle+8 and SIGSEGV'd (exit 139) after SSLRequest. #160 stores the hostname box there (`76,137,77,208` / `lea rax,[r9+8]` into `tls_nameptr`) like PE wrap.

`bash tools/pg-tls-stub-elf.sh` after #162 (`3c00595`): **host** `PG TLS PROVE pass` including `cbind tls-server-end-point`. **ELF** still **`FAIL channel binding`** (exit 1). #162 stored i2d length; RFC 5929 SHA-384/512 `tls_end_point` is #161. MITM ELF did not run because the script exits on PLUS fail. Do not skip. Not PE proof.

## Native rpc-portal “missing header terminator” (Lane K)

Not a small rollup merge of the wrong packed blob. `tools/rebuild-unauth-sidecar-diff.sh` `http_call` raises `missing header terminator` when `recv` has no `\r\n\r\n`.

Reproduced on this tip with the sidecar compile path (`listen with 0`, `compile-native` ELF of `tests/rebuild/guests/rpc-portal-go.vire`):

- Host GET `/api/health`: 159 bytes `HTTP/1.1 200 OK` … `\r\n\r\n{"ok":true}`.
- Native ELF: **SIGSEGV (139)** on the first GET; **raw_len 0**; no header terminator because the process died, not because it sent a body-only JSON 200.

Same class as FCGBDS worker/heartbeat native HTTP. Packed 1-param `listen` guest vs host `VireListen`. Do not skip. Do not treat as a 3-param POST overlay mix-up.

## #159 fold proof (`52f9849`)

Host: `HeaderSecretCompareTests` + `BlockAuthTests` **11 passed** (full-length compare, fail-closed ≥4096). Caps unchanged.

Native `tools/post-block-auth-native.sh`: ELF listens then **SIGSEGV 139** on the first GET `/chain` (empty recv). Same #150 r4 4-param listen fault as a minimal 4-param guest. #159's own r4 blob (18843) on this compiler returns `HTTP/1.1 200` for that guest. Recorded, not skipped.

- `bash tools/rebuild-unauth-sidecar-diff.sh`: FAIL_BEFORE contract mismatch as required; PASS_AFTER native **missing header terminator** (SIGSEGV).
- `bash tools/native-elf-selfhost.sh` at `52f9849`: gen1=gen2 x3 `a59ea7ffb945dde7d48988a337f47c71dba984749934d9e7aa7d4caa787da055`.
- Full xUnit on `52f9849`: env-only AndroidSo / DriverImage; `PgRedisTlsStubTests` ELF **FAIL channel binding** (pre-#162 length + missing #161 hash).

## #162 fold proof (`3c00595`)

`rt_tls_peer_cert` second `i2d_X509` now writes DER length into the box (`72,139,85,232,72,137,10`). Host PLUS vs stub prints `cbind tls-server-end-point`. ELF PLUS still `FAIL channel binding` until #161. `PgRedisTlsStubTests.LinuxElfPgTlsWrapAndRedisTlsConnectAgainstStubs` same ELF fail (3 other cases passed). Waiting on named #161 head.

Caps stay arena 33554432, list 100000, steps 5000000, itemCap 1e6.

## Env-only xUnit failures (this Linux agent)

Do not skip or xfail these. They fail closed when tools are missing.

- `DriverImageTests.LinkedDriverImageIsPe` (`the C compiler is not installed`)
- `ToolchainTests.BuildCompilesCAndroidAndDriver` (`ANDROID_NDK_HOME` / `ANDROID_NDK_ROOT`)
- `ApkTests.PackWritesApkWithManifest` (`ANDROID_SDK_ROOT` / `ANDROID_HOME` / `JAVA_HOME`)
- `AndroidSoTests.AndroidBuildEmitsElfSharedLibrary` (`ANDROID_NDK_HOME` / `ANDROID_NDK_ROOT`)

Machines with SDK/NDK and a C compiler must pass those tests. Linux ELF is not Windows PE proof. GitHub Actions billing-lock is ignored.
