# Rebuild my stack — native capabilities

Loopback `127.0.0.1` only. Arena 32MB, list 100000, steps 5M. Sandbox paths stay `data/` and `site/`.

## Capabilities

| Lane | Status | Proof |
|---|---|---|
| Native ELF / PE compiler | Proven on this tree | `tools/native-elf-hello.sh`, `tools/native-elf-selfhost.sh`, Windows handoff scripts |
| Native TLS client (`tls_connect` / `tls_wrap`) | Proven | `#95`/`#99`, `tools/native-elf-tls.sh`, host `SslStream` |
| Postgres v3 + SCRAM-SHA-256 | Proven | `#95`, `tools/pg-prove-linux.sh` |
| Postgres over TLS (`sslmode=require` / `verify-full`) | Proven | PR #109, `tools/pg-tls-prove-linux.sh` |
| RESP2 Redis plaintext | Proven | `#64`, `tools/redis-prove-windows.ps1` |
| RESP2 Redis `rediss://` (TLS, verify-full, AUTH) | This PR | `tools/redis-tls-prove-linux.sh`; Windows: `tools/redis-tls-prove-windows.ps1` when Redis 6+ `tls-port` is installed |
| HTTPS upstream / DNS / non-loopback | Not this PR | Native `connect` still refuses non-loopback |
| RESP3, pub/sub, Redis ACL username | Not this PR | Guest speaks RESP2 `AUTH password` only |
| SCRAM-SHA-256-PLUS channel binding | Not this PR | Residual on Postgres TLS |
| Native `tls_listen` on ELF | Fail-closed | Host interpreter can still listen TLS |

`rediss://` uses the existing TLS client. Certificate chain and hostname checks are on (verify-full). A `redis://` URL is refused by `redis_open_rediss` (no plaintext downgrade). Handshake against a plaintext Redis port, a wrong CA, a wrong name, or an expired server certificate fail closed.

## What this PR does not prove

- GitHub Actions on this account is billing-locked; CI job red X is not a code result. Linux proofs are local.
- Windows PE live `rediss://` against Redis `tls-port` is **not** claimed from this Linux agent. Couchy can run `tools/redis-tls-prove-windows.ps1` on CouchStation when Redis 6+ with TLS is present. The checked-in Redis 5 zip used by `redis-prove-windows.ps1` has no `tls-port`.
- Production Redis, non-loopback, DNS names, client certificates (`tls-auth-clients yes`), Redis ACL `AUTH user pass`, RESP3, Cluster, Sentinel, and stunnel-in-front-of-Redis-5.
- Compiler/runtime blob changes: this PR is a guest library (`src/rt-redis.vire`) plus tests/docs/scripts. It does not restage `data/src/` or `compile-native.vire`.
- Expired-certificate coverage uses a second loopback `redis-server` whose server cert is already expired; it does not mutate the happy-path listener.
