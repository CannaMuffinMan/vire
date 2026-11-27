# VIRE finish list (integration, 2026-11-21)

Every row has a `TODO(VIRE-FINISH-NOW):` marker in the named file. Every such marker in the tree is listed. Caps stay arena 33554432, list 100000, steps 5000000, compiler itemCap 1e6.

| file | symbol | what's missing | priority | owning area |
|---|---|---|---|---|
| windows/vire.windows.csproj | Compile ItemGroup | WINDOWS project compiles only `Vire.cs` and `Compiled.cs`; remaining host `.cs` files are not included | high | host-cs |
| tests/rebuild/contracts/fcgbds-dashboard-go/BLOCKED.md | dashboard-go contracts | Remaining dashboard-go routes/headers still blocked | high | tests-docs |
| tests/rebuild/contracts/rpc-portal-go/BLOCKED.md | rpc-portal-go contracts | Remaining outbound/auth/static routes still blocked | high | tests-docs |
| tests/rebuild/contracts/edge-go/BLOCKED.md | edge-go contracts | Host-map/maintenance/payments behaviors still blocked | high | tests-docs |
| tests/rebuild/contracts/dev-portal-go/BLOCKED.md | dev-portal-go contracts | Cookie/JWT/proxy/static routes still blocked | high | tests-docs |
| tests/rebuild/FCGBDS-WORKER.md | FCGBDS worker | Native POST body, reviewer TTL, bind, PE proof still open | high | tests-docs |
| tools/rebuild-proxy-windows.ps1 | PE proxy proof | Host-vs-PE proxy modes against a loopback upstream (not MZ-only) | high | tools-ci |
| tools/rebuild-proxy-ws-windows.ps1 | PE proxy-ws proof | Host-vs-PE proxy-ws 101 / bad 400 / refuse 403 vs loopback echo | high | tools-ci |
| tools/apigo-ws-windows.ps1 | PE apigo-ws | Compile apigo-ws to PE and match ELF 101/echo/fail-closed frames | high | tools-ci |
| tools/rebuild-portal-windows.ps1 | PE portal twins | Compile rpc/dev/dashboard guests to PE and match Linux portal contracts | high | tools-ci |
| tools/rebuild-sop-proxy-windows.ps1 | PE landing SOP | Host-vs-PE landing-sop issue/verify/header and listen contracts | high | tools-ci |
| src/rt-net.vire | rt-net-json-blob | Regen packed JSON encode/parse so parked helper roots match GPR/rbp | high | rt-net |
| tools/rebuild-obs-listen-windows.ps1 | PE obs/listen | Host-vs-PE GET /obs 307 and listen GET/POST /proxy 200 on loopback | medium | tools-ci |
| tools/native-forms.ps1 | native-forms fixtures | Tracked `data/native-forms` try-miss.vire and for-list.vire | medium | tools-ci |
| src/rt-pg.vire | pg_auth / SCRAM | Guest SCRAM-SHA-256-PLUS using tls-unique / server-end-point | medium | rt-net |
| tools/tls-schannel-windows.ps1 | PE tls_listen | CouchStation 50f01259 18:11-18:42 ET: `PE tls_listen exited 1`. Packed PE SChannel tls_listen, present at pre-cleanup c813695. Harness now kills tls-echo process trees and reads child logs with FileShare.ReadWrite. | high | tools-ci |
| tools/pg-redis-tls-windows.ps1 | PE tls_wrap ping | CouchStation 50f01259 18:11-18:42 ET: `PE tls_wrap ping missing PONG`. Packed PE tls_wrap, present at pre-cleanup c813695. Leftover `vire-proof tls-echo` held the child log; finally + FileShare.ReadWrite. | high | tools-ci |
| Vire.cs | Builtin serve | Drop the serve name from Builtins once guests no longer call it | low | host-cs |
| Compiled.cs | Builtin serve | Drop the serve name once guests no longer call it | low | host-cs |
| VireApk.cs | VireApk.Pack | Expose Pack as a guest builtin only if APK from .vire is still a product goal | low | host-cs |
