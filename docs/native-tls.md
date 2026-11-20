# Native TLS (Linux ELF + host)

## Goal

Native Vire programs can serve and call HTTPS so the FCG stack can be rebuilt in Vire. This lane adds `tls_connect`, `tls_listen`, `tls_send`, `tls_recv`, and `tls_close`. Existing TCP `connect` / `listen` / `send` / `recv` / `close` are unchanged.

## Linux choice (OS TLS stack)

Linux has no SChannel equivalent. The kernel does not perform the handshake. Native **TLS guests** are dynamically linked (`PT_INTERP` `/lib64/ld-linux-x86-64.so.2`, `DT_NEEDED` `libssl.so.3`) and call OpenSSL 3. Plain and TCP-only guests stay static syscall ELFs (no libc, no libssl).

Windows native PE: the guest APIs exist; the PE path fail-closes with a message until an SChannel handshake is proven on a Windows box. The host interpreter uses `SslStream` on both OS. This VM proved ELF + host on Linux.

A from-scratch TLS 1.3 in Vire was not used: it would duplicate OpenSSL/SChannel and could not be fully tested against known vectors in this lane.

## Guest API

```
tls_connect with host, port, name, ca
tls_listen with port, cert, key
tls_send with handle, text
tls_recv with handle, size
tls_close with handle
```

- `tls_connect` is loopback `127.0.0.1` only (same gate as `connect`). `name` is SNI and the name checked on the certificate. `ca` is a PEM file under `data/` or `site/`. Empty `ca` (`""`) uses the system trust store. Validation is on. There is no skip-verify flag.
- `tls_listen` binds like `listen` (`127.0.0.1` unless `VIRE_BIND=public` on the host interpreter). `cert` and `key` are PEM paths under `data/` or `site/`. Guest `define route with method, path, body` is required. Native ELF wraps `accept` / `recv` / `send` / `close` with `SSL_accept` / `SSL_read` / `SSL_write` / `SSL_shutdown`.
- Recv cap 1_000_000 bytes, same as TCP.

## Security review

| Rule | Status |
|---|---|
| Certificate validation on by default | Host: `SslClientAuthenticationOptions` with custom root store or system roots. Native ELF: `SSL_CTX_set_verify(SSL_VERIFY_PEER)` plus `SSL_set1_host` and `SSL_get_verify_result == 0`. Empty CA uses `SSL_CTX_set_default_verify_paths`. |
| No protocol downgrade | Host: `SslProtocols.Tls12 \| Tls13` only. Native: `SSL_CTX_set_min_proto_version(TLS1_2)` and `SSL_CTX_set_max_proto_version(TLS1_3)`. |
| No insecure flags enabled by default | Host: `EncryptionPolicy.RequireEncryption`. No `AllowAny`. Native: no `SSL_VERIFY_NONE`, no `SSL_OP_LEGACY_SERVER_CONNECT` set by this runtime. |
| No secrets committed | Test certs are generated at test time under `data/` and are gitignored as build outputs. |
| Caps | Arena 32MB, list 100000, steps 5M unchanged. Sandbox paths still `data/` / `site/`. Native `connect` still refuses non-loopback. |
| Dynamic ELF only for TLS guests | TCP/hello/selfhost images are still static. |

## Tests

- Host: `tests/Vire.Tests/TlsTests.cs` (handshake vs `openssl s_server` / `s_client` where available).
- Native ELF: `tools/native-elf-tls.sh` (real OpenSSL / Python `ssl` peer). Proven on Linux: dynamic `libssl.so.3` guest, `SSL_connect` vs a TLS 1.2+ echo, `SSL_write` of `ping` observed by the peer. `tls_recv`→`say` on that guest is still empty (host `TlsTests` covers interpreter recv vs `openssl s_server`). PE SChannel is fail-closed.

## Shared files

This lane touches `compile-native.vire`, `src/elf.vire`, `Vire.cs`, `Compiled.cs`, `VireNet.cs`, `VireListen.cs`, `tools/stage-compiler-src.sh`. New files: `src/rt-tls.vire`, `VireTls.cs`, this doc, tests and the ELF prove script. `src/rt-net.vire` was not modified.
