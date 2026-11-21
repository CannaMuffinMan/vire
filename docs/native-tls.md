# Native TLS (Linux ELF + host)

## Goal

Outbound TLS for the FCG stack: HTTPS upstream calls and (with the Postgres lane) `sslmode=require`. Go sidecars never listen TLS; edge/Railway terminates inbound TLS. Guest APIs: `tls_connect`, `tls_send`, `tls_recv`, `tls_close`. `tls_listen` stays **fail-closed** on native ELF (unproven; host interpreter still serves TLS). Existing TCP `connect` / `listen` / `send` / `recv` / `close` are unchanged.

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

Windows native PE: APIs exist; the PE path fail-closes until SChannel is proven. Host `SslStream` runs on both OS.

## Guest API

```
tls_connect with host, port, name, ca
tls_send with handle, text
tls_recv with handle, size
tls_close with handle
tls_listen with port, cert, key   ~ native ELF fail-closed; host interpreter only
```

- `tls_connect` is loopback `127.0.0.1` only (same gate as `connect`). `name` is SNI and the name checked on the certificate.
- `ca` empty (`""`) uses the system trust store (`SSL_CTX_set_default_verify_paths` / OS roots). A non-empty `ca` must pass the same **data/ / site/** sandbox as `read` (`rt_check_path` on ELF, `SafePath` on the host). Traversal and paths outside that gate fail closed. OpenSSL never sees a path that skipped the gate.
- Validation is on. There is no skip-verify flag.
- Recv cap 1_000_000 bytes, same as TCP.

## Security review

| Rule | Status |
|---|---|
| Certificate validation on by default | Host: `SslClientAuthenticationOptions` with custom root or system roots. Native ELF: `SSL_CTX_set_verify(SSL_VERIFY_PEER)`, `SSL_set1_host`, `SSL_get_verify_result == 0`. |
| No protocol downgrade | Host: `Tls12 \| Tls13`. Native: min TLS1.2 / max TLS1.3 via `SSL_CTX_ctrl`. |
| No insecure flags by default | No skip-verify, no `SSL_VERIFY_NONE`. |
| Path sandbox | CA/cert files: `data/` or `site/` only. Empty CA = system store, not an arbitrary libc `open`. |
| Caps | Arena 32MB, list 100000, steps 5M unchanged. Native `connect` still refuses non-loopback. |
| Dynamic ELF only for TLS guests | TCP/hello/selfhost images stay static. |

## Postgres / HTTPS (coordinate with #95)

Do not implement SQL on this branch. `#95` owns the native database client. Design only:

- `sslmode=require` should call the same `tls_connect` (or a thin wrapper) after the TCP `connect`, with `name` = server hostname and `ca` empty (system store) or a PEM under `data/`.
- HTTPS upstream: `tls_connect` + `tls_send` of an HTTP/1.1 request + `tls_recv`. Still loopback-only on native until the net sandbox grows.

## Tests

- Host: `tests/Vire.Tests/TlsTests.cs` (handshake vs `openssl s_server`; DualMode refuses `../` and `/etc/...` CA paths).
- Native ELF: `tools/native-elf-tls.sh` (`tls_connect` ping round-trip vs a TLS 1.2+ peer).

## Shared files

`compile-native.vire`, `src/elf.vire`, `Vire.cs`, `Compiled.cs`, `VireNet.cs`, `VireListen.cs`, `tools/stage-compiler-src.sh`. New: `src/rt-tls.vire`, `VireTls.cs`, this doc, tests, prove script. `src/rt-net.vire` was not modified.
