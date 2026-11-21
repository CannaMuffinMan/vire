# Native TLS (Linux ELF + host)

## Goal

Outbound TLS for the FCG stack: HTTPS upstream calls and (with the Postgres lane) `sslmode=require`. Inbound TLS for a loopback FCG service is `tls_listen` on the existing HTTP listener (rank 11 in `docs/REBUILD-MY-STACK.md`) so a separate proxy is not required on CouchStation. Public/edge TLS stays at Railway. Guest APIs: `tls_connect`, `tls_send`, `tls_recv`, `tls_close`, `tls_listen`. Existing TCP `connect` / `listen` / `send` / `recv` / `close` are unchanged.

## Linux choice (OS TLS stack)

Linux has no SChannel. The kernel does not perform the handshake.

**Only TLS guests** are dynamically linked (`PT_INTERP` `/lib64/ld-linux-x86-64.so.2`, `DT_NEEDED` `libssl.so.3` and `libcrypto.so.3`). Hello, TCP-only, and selfhost ELFs stay **static** syscall images (no libc, no OpenSSL).

### Supply chain / version

| Point | Choice |
|---|---|
| Why OpenSSL 3, not a from-scratch TLS 1.3 | Handshake and PKI are not something this lane can fully test against known vectors in Vire. |
| Why `.so.3` not bundled | Distro OpenSSL gets CVE patches; we do not vendor a copy. Tradeoff: the guest trusts the host's `libssl.so.3` / `libcrypto.so.3` (same as any dynamically linked Linux binary). |
| Minimum version | `OpenSSL_version_num() >= 0x30000000` (3.0.0). Below that, `tls_connect` fail-closes. Loading `libssl.so.3` already requires the OPENSSL_3.0 ELF version. |
| Not used for non-TLS | If a program never calls `tls_*`, the image has no INTERP and no DT_NEEDED. |

Windows native PE: `openTlsPeImage` SChannel via a fixed `secur32.dll` + `crypt32.dll` IAT (`AcquireCredentialsHandleA`, `InitializeSecurityContextA` / `AcceptSecurityContext`, `EncryptMessage` / `DecryptMessage`). TLS 1.2|1.3 only (`SP_PROT_TLS1_2_* | SP_PROT_TLS1_3_*`). Client verification is on (`SCH_CRED_AUTO_CRED_VALIDATION`, `pszTargetName` = `name`). No `SCH_CRED_NO_SERVERNAME_CHECK`, no `SCH_CRED_MANUAL_CRED_VALIDATION`, no `SCH_CRED_IGNORE_NO_REVOCATION_CHECK`. Empty `ca` uses the system store; a non-empty `ca` is a sandboxed PEM loaded into an in-memory root store. Server cert is a sandboxed PFX (`tls_listen` cert path); `key` is the PFX password (empty allowed). Host `SslStream` still runs on both OS. Windows PE execute proofs: `tools/tls-schannel-windows.ps1` and `tools/pg-redis-tls-windows.ps1` (PENDING unless CouchStation ran them).

## Guest API

```
tls_connect with host, port, name, ca
tls_wrap with handle, name, ca, checkHost
tls_send with handle, text
tls_recv with handle, size
tls_close with handle
tls_listen with port, cert, key   ~ host SslStream; Linux ELF PEM; Windows PE sandboxed PFX + password
```

- `tls_connect` is loopback `127.0.0.1` only (same gate as `connect`). `name` is SNI and the name checked on the certificate.
- `tls_wrap` runs the same handshake on an existing TCP handle (`checkHost` 1 = verify-full hostname, 0 = require: encrypt + chain, no hostname). Used after Postgres SSLRequest `'S'`.
- `ca` empty (`""`) uses the system trust store (`SSL_CTX_set_default_verify_paths` / OS roots). A non-empty `ca` must pass the same **data/ / site/** sandbox as `read` (`rt_check_path` on ELF, `SafePath` on the host). Traversal and paths outside that gate fail closed. OpenSSL never sees a path that skipped the gate.
- Validation is on. There is no skip-verify flag.
- Recv cap 1_000_000 bytes, same as TCP.

## Security review

| Rule | Status |
|---|---|
| Certificate validation on by default | Host: `SslClientAuthenticationOptions` with custom root or system roots. Native ELF: `SSL_CTX_set_verify(SSL_VERIFY_PEER)`, `SSL_set1_host`, `SSL_get_verify_result == 0`. Native PE: SChannel auto validation + `pszTargetName`. |
| No protocol downgrade | Host: `Tls12 \| Tls13`. Native: min TLS1.2 / max TLS1.3 via `SSL_CTX_ctrl`. |
| No insecure flags by default | No skip-verify, no `SSL_VERIFY_NONE`. |
| Path sandbox | CA/cert/key files: `data/` or `site/` only. Empty CA = system store, not an arbitrary libc `open`. |
| TLS server | Host: `Tls12 \| Tls13`, `RequireEncryption`, Linux `CipherSuitesPolicy` AEAD suites. ELF: `TLS_server_method`, min TLS 1.2 / max TLS 1.3, `SSL_OP_NO_COMPRESSION \| SSL_OP_NO_TLSv1 \| SSL_OP_NO_TLSv1_1`. PE: SChannel inbound cred + PFX, same protocol bits. Handshake / plaintext / truncated ClientHello fail closed (no HTTP). Tests bind `127.0.0.1` only. |
| Caps | Arena 32MB, list 100000, steps 5M unchanged. Native `connect` still refuses non-loopback. |
| Dynamic ELF only for TLS guests | TCP/hello/selfhost images stay static. |

## Postgres / HTTPS (coordinate with #95)

Do not implement SQL on this branch. `#95` owns the native database client. Design only:

- `sslmode=require` should call the same `tls_connect` (or a thin wrapper) after the TCP `connect`, with `name` = server hostname and `ca` empty (system store) or a PEM under `data/`.
- HTTPS upstream: `tls_connect` + `tls_send` of an HTTP/1.1 request + `tls_recv`. Still loopback-only on native until the net sandbox grows.

## Tests

- Host: `tests/Vire.Tests/TlsTests.cs` (handshake vs `openssl s_server`; DualMode refuses `../` and `/etc/...` CA paths).
- Host TLS server: `tests/Vire.Tests/TlsServerTests.cs` (`GET /health` vs `tests/rebuild/contracts/health.json`; plaintext, TLS 1.0, truncated handshake, bad cert path).
- Native ELF: `tools/native-elf-tls.sh` (`tls_connect` ping; `tls_listen` `/health`; negatives fail-closed).
- Windows host: `tools/tls-server-windows.ps1` (SslStream `/health`).
- Windows PE SChannel: `tools/tls-schannel-windows.ps1` (PENDING CouchStation).
- Windows PE Postgres/Redis TLS: `tools/pg-redis-tls-windows.ps1` (PENDING CouchStation; loopback test servers only).

## Shared files

`compile-native.vire`, `src/elf.vire`, `Vire.cs`, `Compiled.cs`, `VireNet.cs`, `VireListen.cs`, `tools/stage-compiler-src.sh`. New: `src/rt-tls.vire`, `VireTls.cs`, this doc, tests, prove script. `src/rt-net.vire` was not modified.
