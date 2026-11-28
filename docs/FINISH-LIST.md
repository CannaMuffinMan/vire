# VIRE finish list (integration, 2026-11-21)

Every row has a `TODO(VIRE-FINISH-NOW):` marker in the named file. Every such marker in the tree is listed. Caps stay arena 33554432, list 100000, steps 5000000, compiler itemCap 1e6.

| file | symbol | what's missing | priority | owning area |
|---|---|---|---|---|
| tests/rebuild/contracts/fcgbds-dashboard-go/BLOCKED.md | dashboard-go contracts | Remaining dashboard-go routes/headers still blocked | high | tests-docs |
| tests/rebuild/contracts/rpc-portal-go/BLOCKED.md | rpc-portal-go contracts | Remaining outbound/auth/static routes still blocked | high | tests-docs |
| tests/rebuild/contracts/edge-go/BLOCKED.md | edge-go contracts | Host-map/maintenance/payments behaviors still blocked | high | tests-docs |
| tests/rebuild/contracts/dev-portal-go/BLOCKED.md | dev-portal-go contracts | Cookie/JWT/proxy/static routes still blocked | high | tests-docs |
| tests/rebuild/FCGBDS-WORKER.md | FCGBDS worker | Native POST body, reviewer TTL, bind, PE proof still open | high | tests-docs |
| tools/tls-schannel-windows.ps1 | PE tls_listen | CouchStation 50f01259 18:11-18:42 ET: `PE tls_listen exited 1`. Packed PE SChannel tls_listen, present at pre-cleanup c813695. Harness now kills tls-echo process trees and reads child logs with FileShare.ReadWrite. | high | tools-ci |
| tools/pg-redis-tls-windows.ps1 | PE tls_wrap ping | CouchStation 50f01259 18:11-18:42 ET: `PE tls_wrap ping missing PONG`. Packed PE tls_wrap, present at pre-cleanup c813695. Leftover `vire-proof tls-echo` held the child log; finally + FileShare.ReadWrite. | high | tools-ci |
| Vire.cs | Builtin serve | Drop the serve name from Builtins once guests no longer call it | low | host-cs |
| Compiled.cs | Builtin serve | Drop the serve name once guests no longer call it | low | host-cs |

Closed 2026-11-28: `VireApk.Pack` stays host-only. APK from `.vire` is not a product (`docs/history.md` Do not resume). No guest builtin. Missing Android SDK/NDK is a named env failure (`ANDROID_SDK_ROOT` / `ANDROID_HOME` / `JAVA_HOME`, `ANDROID_NDK_HOME` / `ANDROID_NDK_ROOT`), not a silent pass. Residual: no signed `data/app.apk` or aarch64 `.so` on this Linux agent (SDK/NDK absent). `windows/vire.windows.csproj` still omits `VireApk.cs` (separate row).
