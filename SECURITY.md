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
- `.vc` files are AES-256-GCM `VC2` seals. A key is required (`VIRE_SEAL_KEY` or `--seal-key-file`). The key is never printed; only an 8-hex fingerprint of SHA-256 of the key may be shown. Old XOR seals are refused. After unsealing, the loader rejects unknown opcodes, bad operand types, out-of-range jumps, and missing operands (`compiled stack underflow`) as `VireError` instead of letting CLR exceptions take the process.
- JSON read/write is depth-capped (256) and size-capped (1,000,000 characters of input; 100,000 items per list or map). `parse with text, schema` refuses the wrong type, a missing required key, and an extra key when the schema is closed. Seeded fuzz of mutated JSON must fail as a Vire error, not a process crash. `say` of a cyclic list or map does not hang the process. `Main` turns unexpected exceptions into exit 3 without a stack trace unless `VIRE_DEBUG=1`.
- Safe-stdlib crypto (interpreter and compiled `.vc` share `VireCrypto`): CSPRNG `random`/`token` (bounded length), HMAC-SHA256, `samebytes` (`CryptographicOperations.FixedTimeEquals`), AES-256-GCM encrypt/decrypt with a required 32-byte key. Encrypt always draws a new 12-byte nonce from `RandomNumberGenerator`; the language API does not accept a caller nonce. Decrypt of a tampered packing returns `could not decrypt that message` and never unwraps `CryptographicException`. No new crypto NuGet packages. **Left:** Ed25519 sign/verify — .NET 10's BCL does not provide a standalone Ed25519 class (only `CompositeMLDsa` hybrids that include Ed25519). Hand-rolled Edwards math is refused.
- Static `listen` GET of `site/` is allowlisted, GET-only, no directory listing, no symlinks, no `.vire` sources.

## Non-guarantees

- There is no TLS server, no authorization on `POST /block`, and no public internet hardening beyond loopback-by-default plus an optional token when `VIRE_BIND` is `public`.
- A person who has the runner and the seal key can still read a compiled program. The seal stops casual reading and casual patches. It does not stop every attack.
- Windows desktop, the native compiler, and live network samples are outside this guarantee list.
- Caps stop runaway programs; they do not make a program safe to expose to the internet.
