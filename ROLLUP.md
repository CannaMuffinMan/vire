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
| #161 | `b449ffe7` (`cursor/vire-4h-pe-peercert`) | After #162. PE `tls_peer_cert` DER export; ELF/PE `tls_end_point` SHA-256/384/512 via OID (PE `CryptHashCertificate`). Packed SChannel blob **5161**, changed `[4481,5161)`. Kept #162 i2d length. Kept PE wrap `76,137,13` from #160. Conflicts in VireProof: PLUS/MITM stub from #161 plus expired PFX / redis / `pg-tls-n` / SELECT loop from the rollup. |
| #163 | `d664343` (`cursor/vire-4h-listen-recv0`) | Fast-forward onto the rollup. Recv0 `je` at 0x5DE → in-blob `leave;ret` (r4 0x36DF / 3-param 0x510). r4 length **18843** (#159), not #150's 18855. `cl_blockgate` e9 already at 0xA78. |
| #164 | `4f9a337e` (`cursor/vire-4h-selfhost-listcap`) | Normal merge after #163. Packs ELF `emitTlsGuest` into a 2403-byte blob (`src/rt-tls-elf.vire` + `tools/pack-tls-elf.py`). Listen/r4 blobs untouched. |

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
- **r4 `src/rt-net-r4-blob.txt`:** after #163, length **18843** (#159), not #150's 18855. See #163 12-byte DNS check below. Same-length `FILE_SHARE` `41 b8 01` → `41 b8 07` kept at 0x27AB.
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
- #148 is `880ec761` on this tip (leaf export + RFC 5929 `tls_end_point`). Re-merge if `cursor/pg-scram-plus-e596` moves again.
- Packed PE `dns_hostok` `push rbx` (the 12-byte #150 insert). Restoring 18855 SIGSEGVs 4-param listen (empty recv, rc -11) even with #163 recv0 and `cl_blockgate` e9 → 0xA78 or pin `rt_net_pushroute` 0x3F85. Not hidden.

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

`bash tools/pg-tls-stub-elf.sh` after #161+#162: **host and ELF** `PG TLS PROVE pass` with `auth scram-sha-256-plus` and `cbind tls-server-end-point`. ELF MITM guest **`PG TLS MITM pass`** (`mitm-cert tls handshake failed`). Hostname/CA verify fail-closed. Redis TLS host+ELF pass. Do not skip. Not PE proof.

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

`rt_tls_peer_cert` second `i2d_X509` writes DER length into the box (`72,139,85,232,72,137,10`). Kept through the #161 merge.

## #161 fold proof (`83354e3` + VireProof reconcile)

Packed PE blob 5161. `TlsEndPointTests` 3 passed. `PgRedisTlsStubTests` 4 passed. `tools/pg-tls-stub-elf.sh` **exit 0**: host+ELF PLUS cbind, ELF MITM reject, redis stub.

`native-elf-selfhost.sh` before #164: host compile of `compile-native.vire` **`list is too large`** at parseClimb (line 274). Caps not raised.

Caps stay arena 33554432, list 100000, steps 5000000, itemCap 1e6.

## #163 fold — 12-byte r4 DNS check

Diff of #150-era 18855 (`4ac9dc8`) vs #163 18843 (`d664343`) after `dns_hostok` 0x1FD4: **exactly 12 inserted bytes**, all `push rbx` (`53`) or `pop rbx` (`5b`):

| 18855 offset | byte | vs 18843 |
|---|---|---|
| 0x1FDF | `53` push rbx | 0x1FDF |
| 0x20AD | `5B` pop rbx | 0x20AC |
| 0x20B2 | `5B` pop rbx | 0x20B0 |
| 0x20C0 | `53` push rbx | 0x20BD |
| 0x21BC | `5B` pop rbx | 0x21B8 |
| 0x23E2 | `53` push rbx | 0x23DD |
| 0x259A | `5B` pop rbx | 0x2594 |
| 0x259F | `5B` pop rbx | 0x2598 |
| 0x273C | `53` push rbx | 0x2734 |
| 0x28A6 | `5B` pop rbx | 0x289D |
| 0x2902 | `5B` pop rbx | 0x28F8 |
| 0x290F | `5B` pop rbx | 0x2904 |

Not part of those 12: same-length `FILE_SHARE` `41 B8 01` → `41 B8 07` at 18843 **0x27AB** (18855 0x27B4). Kept on this tip.

Re-adding the 12 bytes (restore 18855, run `tools/patch-rt-net-listen-recv0.py`, `cl_blockgate` e9 at 0xA78, and a second try e9 → `rt_net_pushroute` 0x3F85): packed DNS gaps-check **PASS** (`r4_hostok_push_rbx True`, `r4_file_share_7 True`) but 4-param ELF **GET /api/health SIGSEGV** (`recv b''`, rc -11). Unmodified 18843 (+ share-7 only) **HTTP 200**. #163 dropped the 12 bytes so listen works. The live `push rbx` in `dns_hostok` is therefore **lost** on this tip; do not hide it.

## #163 listen / 401 / POST proofs (18843 + share-7)

- `NativeListenRecv0Tests` 2 passed (packed e9→0xA78; Linux GET /api/health, empty connect, split headers host==native).
- `tools/post-block-auth-native.sh` **ok**: 401 matrix (none/short/wrong/oversize on `FCG_API_TOKEN` and `FCG_BLOCK_TOKEN`) and authorized POST `/block` **200** (`accepted:true`).
- `tools/rebuild-unauth-sidecar-diff.sh` **ok** (FAIL_BEFORE contract mismatch; PASS_AFTER host==native including GET /api/health).
- `tools/rebuild-fcgbds-heartbeat-diff.sh` **ok** (FAIL_BEFORE sessionId; PASS_AFTER host==native).

## #164 fold proof (selfhost list cap)

`tools/native-elf-selfhost.sh` **PASS_AFTER** gen1=gen2 x3 `27dad454a16dc7af47dc28ee121053f57a7e2b0aa8a17aef3141a9643da98661`.

- **gen1_exe_bytes 966656**. Compiler `itemCap` 1000000. Headroom **33344** bytes (3.3%).
- `tools/pg-tls-stub-elf.sh` **exit 0**: host+ELF PLUS (`auth scram-sha-256-plus`, `cbind tls-server-end-point`), ELF MITM `PG TLS MITM pass`, redis host+ELF pass.

## Full xUnit on this tip

296 executed, **0 skipped**, 290 passed, **6 failed**. Do not skip or xfail.

Env-only (missing tools on this Linux agent):

- `ApkTests.PackWritesApkWithManifest` — `ANDROID_SDK_ROOT` / `ANDROID_HOME` / `JAVA_HOME`; aapt not installed
- `DriverImageTests.LinkedDriverImageIsPe` — `the C compiler is not installed`
- `AndroidSoTests.AndroidBuildEmitsElfSharedLibrary` — `ANDROID_NDK_HOME` / `ANDROID_NDK_ROOT`
- `ToolchainTests.BuildCompilesCAndroidAndDriver` — `ANDROID_NDK_HOME` / `ANDROID_NDK_ROOT`

Real (not missing tools) — #150 packed DNS `push rbx` dropped with #163 18843:

- `WindowsPeProofTests.PackedR4DnsPreservesRbxAndFileShare` — hex missing `5348894df8` (`push rbx; mov [rbp-8],rcx`)
- `NativeNetTests.DnsResolveGuestPeShapeParksStubAndKeepsLinuxFlagOutsideR4Blob` — `PE dns_hostok must push rbx`

Machines with SDK/NDK and a C compiler must pass the four env tests. Linux ELF is not Windows PE proof. GitHub Actions billing-lock is ignored. Do not merge this rollup to `native-compiler` or `main`.
