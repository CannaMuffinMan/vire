# VIRE finish list (integration, 2026-11-28)

Every row has a `TODO(VIRE-FINISH-NOW):` marker in the named file unless this table says the marker was closed. Caps stay arena 33554432, list 100000, steps 5000000, compiler itemCap 1e6.

Status keys: **done** (this PR or named PR), **in-flight** (other lane), **blocked** (missing source/contract named).

| file | symbol | what's missing | priority | owning area | status |
|---|---|---|---|---|---|
| windows/vire.windows.csproj | Compile ItemGroup | WINDOWS project compiles only `Vire.cs` and `Compiled.cs`; remaining host `.cs` files are not included | high | host-cs | **done** this PR: `<Compile Include="..\*.cs" />` matches linux root `.cs`. Windows `net10.0-windows` build not run here. |
| tests/rebuild/contracts/fcgbds-dashboard-go/BLOCKED.md | dashboard-go contracts | Remaining dashboard-go routes/headers still blocked | high | tests-docs | **in-flight** portal/edge/dev/dashboard contracts lane |
| tests/rebuild/contracts/rpc-portal-go/BLOCKED.md | rpc-portal-go contracts | Remaining outbound/auth/static routes still blocked | high | tests-docs | **in-flight** portal/edge/dev/dashboard contracts lane |
| tests/rebuild/contracts/edge-go/BLOCKED.md | edge-go contracts | Host-map/maintenance/payments behaviors still blocked | high | tests-docs | **in-flight** portal/edge/dev/dashboard contracts lane |
| tests/rebuild/contracts/dev-portal-go/BLOCKED.md | dev-portal-go contracts | Cookie/JWT/proxy/static routes still blocked | high | tests-docs | **in-flight** portal/edge/dev/dashboard contracts lane |
| tests/rebuild/FCGBDS-WORKER.md | FCGBDS worker | Native POST body, reviewer TTL, bind, PE proof still open | high | tests-docs | **in-flight** FCGBDS worker lane |
| tools/rebuild-proxy-windows.ps1 | PE proxy proof | Host-vs-PE proxy modes against a loopback upstream (not MZ-only) | high | tools-ci | **done** this PR: `vire-proof http-echo` + host=PE modes. CouchStation only. Linux ELF already `tools/rebuild-proxy-diff.sh`. |
| tools/rebuild-proxy-ws-windows.ps1 | PE proxy-ws proof | Host-vs-PE proxy-ws 101 / bad 400 / refuse 403 vs loopback echo | high | tools-ci | **done** this PR: `vire-proof ws-upstream` + host=PE. CouchStation only. |
| tools/apigo-ws-windows.ps1 | PE apigo-ws | Compile apigo-ws to PE and match ELF 101/echo/fail-closed frames | high | tools-ci | **done** this PR: compile PE + `vire-proof ws-prove`. CouchStation only. Linux ELF `tools/apigo-ws-linux.sh`. |
| tools/rebuild-portal-windows.ps1 | PE portal twins | Compile rpc/dev/dashboard guests to PE and match Linux portal contracts | high | tools-ci | **in-flight** portal/edge/dev/dashboard contracts lane (stub still `exit 1`) |
| tools/rebuild-sop-proxy-windows.ps1 | PE landing SOP | Host-vs-PE landing-sop issue/verify/header and listen contracts | high | tools-ci | **done** this PR: PE issue/verify/header + GET /healthz. CouchStation only. |
| src/rt-net.vire | rt-net-json-blob | Regen packed JSON encode/parse so parked helper roots match GPR/rbp | high | rt-net | **blocked** no regen tool. Packed `src/rt-net-json-blob.txt` + pins/fixes. Must patch packed blob; inlining unpacked JSON blows list cap 100000. Missing: a tracked regenerator that emits blob/pins/fixes from `src/rt-net-unpacked.vire` without raising the list cap. |
| tools/rebuild-obs-listen-windows.ps1 | PE obs/listen | Host-vs-PE GET /obs 307 and listen GET/POST /proxy 200 on loopback | medium | tools-ci | **done** this PR: dashboard `/obs` + `proxy-reply` GET/POST `/proxy`. CouchStation only. Dashboard 405/proxy-body/WS-upgrade runtime still in-flight (`bc-4a83202b`). |
| tools/native-forms.ps1 | native-forms fixtures | Tracked `data/native-forms` try-miss.vire and for-list.vire | medium | tools-ci | **done** this PR. `rt_for_more` now indexes `list.buf` (`src/rt.vire`). Linux ELF: `bash tools/native-forms-linux.sh`. |
| compile-native.vire | tokenize | Native lexer must accept fractional number literals | medium | rt-core | **blocked** native values are kind 1 int (`rt_push_int` in `src/rt.vire`). Host lexer already parses `2.5` as double (`Vire.cs` Tokenize). Missing: `rt_push_real` plus arithmetic/compare/say on IEEE doubles in `src/rt.vire` / `src/rt-more.vire`. Emitting `emitU64` of a host double is not a fractional literal. |
| src/rt-pg.vire | pg_auth / SCRAM | Guest SCRAM-SHA-256-PLUS using tls-unique / server-end-point | medium | rt-net | **in-flight** pg/redis TLS PE lane |
| tools/tls-schannel-windows.ps1 | PE tls_listen | CouchStation 50f01259 18:11-18:42 ET: `PE tls_listen exited 1`. Packed PE SChannel tls_listen, present at pre-cleanup c813695. | high | tools-ci | **in-flight** pg/redis TLS PE lane |
| tools/pg-redis-tls-windows.ps1 | PE tls_wrap ping | CouchStation 50f01259 18:11-18:42 ET: `PE tls_wrap ping missing PONG`. Packed PE tls_wrap. | high | tools-ci | **in-flight** pg/redis TLS PE lane |
| src/rt-crypto.vire | sha256_bytes | Wire guest SHA-256 pad+compress+IV into this wrapper instead of digest | medium | rt-crypto | **blocked** wrapper still `return digest with buf` (host builtin / native `rt_digest`). Missing: guest pad+compress+IV in `src/rt-crypto.vire` that stays under steps 5000000 for `pbkdf2-80k.vire` (80000 rounds). Native FIPS 180-4 already lives in packed `rt_sha256` (`src/rt-more.vire`); do not inline that into the guest compiler. |
| Vire.cs | Builtin serve | Drop the serve name from Builtins once guests no longer call it | low | host-cs | **in-flight** serve builtin drop lane |
| Compiled.cs | Builtin serve | Drop the serve name once guests no longer call it | low | host-cs | **in-flight** serve builtin drop lane |
| VireApk.cs | VireApk.Pack | Expose Pack as a guest builtin only if APK from .vire is still a product goal | low | host-cs | **in-flight** VireApk lane |
