# VIRE finish list (integration, 2026-11-28)

Every row has a `TODO(VIRE-FINISH-NOW):` marker in the named file unless this table says the marker was closed. Caps stay arena 33554432, list 100000, steps 5000000, compiler itemCap 1e6.

Status keys: **done** (named PR on this rollup), **in-flight** (other lane still open), **closed** (not a product / no guest builtin).

| file | symbol | what's missing | priority | owning area | status |
|---|---|---|---|---|---|
| windows/vire.windows.csproj | Compile ItemGroup | WINDOWS project compiles only `Vire.cs` and `Compiled.cs`; remaining host `.cs` files are not included | high | host-cs | **done** PR #146: `<Compile Include="..\*.cs" />`. Same glob as #155. Rollup keeps #146. |
| tests/rebuild/contracts/fcgbds-dashboard-go/BLOCKED.md | dashboard-go contracts | Remaining dashboard-go routes/headers still blocked | high | tests-docs | **done** PR #156 in-tree goldens host==native (`docs/fcg-contracts-missing.md`). Residual: Dist HTML, Upstream, extra headers, WS/TLS/DB. GET 405 HTTP status is PR #151 packed overlay, not #156's own base. |
| tests/rebuild/contracts/rpc-portal-go/BLOCKED.md | rpc-portal-go contracts | Remaining outbound/auth/static routes still blocked | high | tests-docs | **done** PR #156 in-tree JSON host==native. Residual listed in `docs/fcg-contracts-missing.md`. |
| tests/rebuild/contracts/edge-go/BLOCKED.md | edge-go contracts | Host-map/maintenance/payments behaviors still blocked | high | tests-docs | **done** PR #156 healthz/not-found/maintenance goldens. Residual: Host map, maintenance HTML, public bind. |
| tests/rebuild/contracts/dev-portal-go/BLOCKED.md | dev-portal-go contracts | Cookie/JWT/proxy/static routes still blocked | high | tests-docs | **done** PR #156 dist-missing + portal JWT/307/405. Residual: real dist, Allow headers, HTTPS API. |
| tests/rebuild/FCGBDS-WORKER.md | FCGBDS worker | Native POST body, reviewer TTL, bind, PE proof still open | high | tests-docs | **in-flight** PR #153 JSON heartbeat `sessionId` + worker env cases. Residual: native HTTP header terminator on worker guest, PE proof. |
| tools/rebuild-proxy-windows.ps1 | PE proxy proof | Host-vs-PE proxy modes against a loopback upstream (not MZ-only) | high | tools-ci | **done** PR #147 `native-loopback-proof.ps1` host-vs-native, FAIL_BEFORE `6693e0e5`. Not #155 `vire-proof http-echo`. |
| tools/rebuild-proxy-ws-windows.ps1 | PE proxy-ws proof | Host-vs-PE proxy-ws 101 / bad 400 / refuse 403 vs loopback echo | high | tools-ci | **done** PR #147. Not #155. |
| tools/apigo-ws-windows.ps1 | PE apigo-ws | Compile apigo-ws to PE and match ELF 101/echo/fail-closed frames | high | tools-ci | **done** PR #147. Not #155. Linux ELF `tools/apigo-ws-linux.sh`. |
| tools/rebuild-portal-windows.ps1 | PE portal twins | Compile rpc/dev/dashboard guests to PE and match Linux portal contracts | high | tools-ci | **in-flight** portal contracts (stub still `exit 1`) |
| tools/rebuild-sop-proxy-windows.ps1 | PE landing SOP | Host-vs-PE landing-sop issue/verify/header and listen contracts | high | tools-ci | **done** PR #147. Not #155. |
| src/rt-net.vire | rt-net-json-blob | Regen packed JSON encode/parse so parked helper roots match GPR/rbp | high | rt-net | **done** PR #144 `tools/pack-rt-net-json.py` + packed `src/rt-net-json-blob.txt`. Must patch packed blob; do not inline unpacked JSON. |
| tools/rebuild-obs-listen-windows.ps1 | PE obs/listen | Host-vs-PE GET /obs 307 and listen GET/POST /proxy 200 on loopback | medium | tools-ci | **done** PR #147. Not #155. |
| tools/native-forms.ps1 | native-forms fixtures | Tracked `data/native-forms` try-miss.vire and for-list.vire | medium | tools-ci | **done** PR #155 fixtures + `rt_for_more` `list.buf`. Harness stays PR #147. Linux ELF: `bash tools/native-forms-linux.sh`. |
| compile-native.vire | tokenize | Native lexer must accept fractional number literals | medium | rt-core | **done** PR #145. |
| src/rt-pg.vire | pg_auth / SCRAM | Guest SCRAM-SHA-256-PLUS using tls-unique / server-end-point | medium | rt-net | **done** PR #148 `880ec761`: `tls_end_point` RFC 5929 leaf export. Fail-closed kept: no bind and MITM cert → `channel binding`. Residual: live `tls-unique` when conn.cbind_name is already set. Did not fold #159. |
| tools/tls-schannel-windows.ps1 | PE tls_listen | CouchStation 50f01259 18:11-18:42 ET: `PE tls_listen exited 1`. Packed PE SChannel tls_listen, present at pre-cleanup c813695. Harness now kills tls-echo process trees and reads child logs with FileShare.ReadWrite. | high | tools-ci | **in-flight** PRs #147 / #149. Linux ELF is not PE proof. |
| tools/pg-redis-tls-windows.ps1 | PE tls_wrap ping | CouchStation 50f01259 18:11-18:42 ET: `PE tls_wrap ping missing PONG`. Packed PE tls_wrap. | high | tools-ci | **in-flight** PRs #147 / #149 / #157 stubs. #160 ELF wrap hostname box: SSL_set1_host SEGV gone. Residual: ELF `FAIL channel binding` vs stub; PE execute CouchStation. |
| src/rt-crypto.vire | sha256_bytes | Wire guest SHA-256 pad+compress+IV into this wrapper instead of digest | medium | rt-crypto | **done** PR #144. Guest `sha256_bytes` is pad+compress+IV. Packed native FIPS 180-4 stays in `rt_sha256`. |
| Vire.cs | Builtin serve | Drop the serve name from Builtins once guests no longer call it | low | host-cs | **done** PR #154. Leftover `serve with …` is `there is no definition named serve`. |
| Compiled.cs | Builtin serve | Drop the serve name once guests no longer call it | low | host-cs | **done** PR #154. |
| VireApk.cs | VireApk.Pack | Expose Pack as a guest builtin only if APK from .vire is still a product goal | low | host-cs | **closed** PR #152. Host-only. APK from `.vire` is not a product. Named env fail (`ANDROID_SDK_ROOT` / `ANDROID_HOME` / `JAVA_HOME`, `ANDROID_NDK_HOME` / `ANDROID_NDK_ROOT`). |

Closed 2026-11-28: `VireApk.Pack` stays host-only. Missing Android SDK/NDK is a named env failure, not a silent pass. Residual: no signed `data/app.apk` or aarch64 `.so` on this Linux agent. `windows/vire.windows.csproj` globs `..\*.cs` (PR #146).

Closed 2026-11-28: host `serve` is not a builtin. Guests already call `listen`.
