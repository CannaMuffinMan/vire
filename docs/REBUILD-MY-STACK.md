# Rebuild-my-stack port order (FCG on Vire)

Proven side-by-side: host interpreter vs native Linux ELF (Windows PE where a `tools/*-windows.ps1` exists). Caps stay **arena 32MB / list 100000 / steps 5M**. Loopback `127.0.0.1` only in tests. Payments off. No production hosts.

| Rank | Lane | Host | Native ELF | Windows proof | Status |
|---|---|---|---|---|---|
| 1 | Compiler / self-host | `compile-native.vire` | gen1=gen2 ELF | `tools/native-selfhost-handoff` family | prior |
| 2 | Hello / strings | interpreter | static ELF | PE hello | prior |
| 3 | Files + path gate | `SafePath` | `rt_check_path` + `openat` `O_NOFOLLOW` | prior | prior |
| 4 | TCP client | `connect` | loopback sockets | `tools/native-tcp-windows.ps1` | prior |
| 5 | HTTP listener | `listen` + `VireListen` | `rt_listen` blob | prior | prior |
| 6 | JSON | `json` / `parse` | `rt_json` | prior | prior |
| 7 | Health contract | `guest-health.vire` `GET /health` | same guest | prior | prior |
| 8 | Redis | loopback RESP + `rediss://` | `rt-redis` + `tls_wrap` | `tools/redis-prove-windows.ps1`, `tools/pg-redis-tls-windows.ps1` | PE TLS PENDING CouchStation |
| 9 | Postgres client | trust/cleartext + `sslmode=verify-full` | `rt-pg` + `tls_wrap` | `tools/pg-prove-windows.ps1`, `tools/pg-redis-tls-windows.ps1` | PE TLS PENDING CouchStation |
| 10 | TLS client | `SslStream` `tls_connect` / `tls_wrap` | OpenSSL 3 `libssl.so.3` | PE SChannel (`tools/tls-schannel-windows.ps1`, PENDING CouchStation) | prior (#126) |
| 11 | **TLS server / HTTPS listener** | `tls_listen` + `SslStream` on `VireListen` | OpenSSL `TLS_server_method` + `SSL_accept` wrapping `rt_listen` | PE SChannel PFX `tls_listen`; host `tools/tls-server-windows.ps1` | prior (#126) |
| 12 | Edge / public TLS | Railway / reverse proxy | not in-guest | n/a | out of scope (Go sidecars never terminate TLS) |

## Rank 11 contract

`tests/rebuild/contracts/health.json` — `GET /health` → `200` body `{"ok":true,"service":"fcgcpa","payments":false}`.

Host and native ELF must both serve that JSON over **HTTPS** on `127.0.0.1` with a test-generated self-signed cert under `data/` (never committed). Handshake failure, plaintext on the TLS port, TLS 1.0/1.1, and truncated ClientHello **fail closed** (no HTTP response). Missing or traversal cert/key paths fail closed through the data/site gate.

Native Windows PE uses SChannel (IAT allowlist). Linux ELF remains the native proof on this VM. PE execute proofs are `tools/tls-schannel-windows.ps1` and `tools/pg-redis-tls-windows.ps1` on CouchStation.

`rediss://` uses the existing TLS client. Certificate chain and hostname checks are on (verify-full). A `redis://` URL is refused by `redis_open_rediss` (no plaintext downgrade). Handshake against a plaintext Redis port, a wrong CA, a wrong name, or an expired server certificate fail closed.
