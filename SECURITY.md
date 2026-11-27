# Security

## Reporting a vulnerability

Use GitHub private vulnerability reporting: on this repository, open **Security → Report a vulnerability**. Do not open a public issue for a security report.

This file does not list an email contact. Whether one should be added is Canna's call.

## Supported version

The supported line is the current Phase 0 runner: .NET 10, this repository's `vire.csproj` / published single-file artifacts from CI. Older XOR `VIRE1` `.vc` files are not supported.

## Guarantees (Phase 0)

These are the current strengths, not a claim that the process cannot be abused:

- Interpreter caps: 1,000,000 steps by default (the starter may set `VIRE_BUDGET` up to 5,000,000), 100,000 `while` passes, 64 call depth, 1,000,000 character text, 100,000 list items, 8 nested `run`s.
- `listen` gives each request a fresh budget and a 5 second wall-clock deadline. Header block 16 KB, request line 8 KB, body 1 MB with `Content-Length` required. At most 64 in-flight connections. Binds `127.0.0.1` by default.
- Paths go through one `SafeName` gate. Rooted paths, `..`, NTFS ADS, device names, trailing dots/spaces, and reparse points are refused. `run` / `use` stay out of `data/` and `site/`. Program and script extensions cannot be written.
- `fetch` and `post` use `http`/`https` only, no userinfo, no automatic redirects (each hop is re-checked), connect to a resolved public address, and cap the body while streaming.
- `.vc` files are AES-256-GCM `VC2` seals. A key is required (`VIRE_SEAL_KEY` or `--seal-key-file`). The key is never printed; only an 8-hex fingerprint of SHA-256 of the key may be shown. Old XOR seals are refused.
- JSON read/write is depth-capped. `say` of a cyclic list or map does not hang the process. `Main` turns unexpected exceptions into exit 3 without a stack trace unless `VIRE_DEBUG=1`.
- Static `listen` GET of `site/` is allowlisted, GET-only, no directory listing, no symlinks, no `.vire` sources.

Native Windows x64 PE (this tree, proven in `native-security.yml` / Windows jobs — not a substitute for the host interpreter list above):

- Emitted `.text` is execute+read, `.data`/`.idata` read+write (W^X section characteristics). Entry calls `VirtualQuery`; `rt_wx_check` is advisory. CI `VirtualQuery` on a `SEC_IMAGE` map is the OS proof.
- Guest `write` of compiler output under `data/` uses a sibling `.tmp` plus `MoveFileExA(REPLACE_EXISTING)` after dest nlink==1 (hardlinks still refuse). Host `VireFiles.WriteAllText` already used tmp+`File.Move`.
- Native faults go to stdout as `crash code=` / `crash rip=` / `crash off=` (RIP minus `0x140000000`). At startup `rt_crash_prepare` GetFileAttributesA-rejects a reparse `data` directory, `rt_bind_path`s the real directory, and stores an absolute `crash_abs`. VEH CreateFile uses only that buffer (`CREATE_NEW` + `FILE_FLAG_OPEN_REPARSE_POINT`). A junctioned `data\` does not receive the log. `crash-rip.txt` is not created.
- Seeded HTTP (`HttpWire`), JSON (`parse` / `src/rt-schema`), and Postgres row/error parsers (`src/rt-pg.vire` `pg_rows_parse` / `pg_err`): host and PE must not AV/hang. Native RFC 6455 is `src/rt-ws.vire` (fail-closed frames); host `listen` uses the same upgrade peek (`VireWs`) on 127.0.0.1. Guest Redis client is separate.

## Non-guarantees

- Host, native ELF, and native PE outbound TLS (`tls_connect` / `tls_wrap`): cert validation on, TLS 1.2 minimum, no skip-verify flag. `sslmode=require` still refuses a server `'N'` SSLRequest reply (no plaintext fallback). `verify-full` also checks the certificate hostname. Native CA/cert/key files go through the same `data/` / `site/` gate as `read` (empty CA = system store). `tls_listen` terminates TLS on the loopback HTTP listener (host `SslStream`, Linux ELF OpenSSL, Windows PE SChannel PFX). Handshake failure, plaintext on the TLS port, and TLS 1.0/1.1 fail closed. Windows PE uses SChannel (`secur32.dll`); prove execute on CouchStation. `POST /block` is deny-by-default: it needs `Authorization: Bearer` matching `FCG_BLOCK_TOKEN` (or `FCG_API_TOKEN` if the block token is unset), length at least 16. A missing or short write secret returns 401 and does not append. `GET /health`, `GET /info`, and `GET /chain` stay unauthenticated. `VIRE_BIND=public` still needs `FCG_API_TOKEN` of at least 16 characters for other paths.
- A person who has the runner and the seal key can still read a compiled program. The seal stops casual reading and casual patches. It does not stop every attack.
- Windows desktop, the native compiler, and live network samples are outside this guarantee list.
- Caps stop runaway programs; they do not make a program safe to expose to the internet.
