# Security model (Phase 0, this branch)

This page is a description of **enforced** behavior in the current runner, plus items that are **planned** and must not be treated as present.

## Reporting

Use GitHub private vulnerability reporting. See [SECURITY.md](../SECURITY.md).

## Enforced today

### Resource caps

Default 1,000,000 steps and the same number of while passes, 64 call depth, 8 nested `run`, 1,000,000 character text, 100,000 list/map items. `VIRE_BUDGET` (1…5,000,000) is the only supported way to raise the step/while cap. Programs cannot raise it from source.

### Paths

All file builtins, `run`, `use`, and `need` go through `VirePaths` (`SafeName`):

- No rooted paths, `..`, empty middle segments, NTFS ADS (`:`), control characters, `<>"|?*`
- No segment ending in `.` or space
- Windows device names (`CON`, `COM1`, …) refused on every OS
- Reparse points (symlinks/junctions) refused
- Writes cannot create `.vire`, `.vc` is written only as a sealed pack through `write` of sealed bytes, and executable/script extensions are refused (`.js` under `site/` is still allowed for generated pages)
- `run` / `use` stay out of `data/` and `site/`
- `read` / `write` / `append` / `copy` / `erase` / `files` / `folders` stay in `data/` or `site/`

### Network client (`fetch`, `post`)

`http`/`https` only, no userinfo, at most three redirects with every hop re-checked, connect to a resolved **public** address (loopback, RFC1918, link-local, CGNAT, docs prefixes, NAT64, 6to4, multicast, etc. refused), 5 second wait, 1,000,000 byte streamed body cap. `post` payload cap 1,000,000 characters.

### `listen`

- Bind `127.0.0.1` unless `VIRE_BIND=public` **and** `FCG_API_TOKEN` is at least 16 characters
- Reserved ports refused: 7099, 8778, 7071, 7072, 7093, 17841, 17843; otherwise 0 or 1024–65535
- 64 in-flight connections (extra: 503)
- Header block 16 KiB, request line 8 KiB, body 1 MiB with `Content-Length` required, chunked encoding refused
- Per-request fresh budget and 5 second deadline
- Static GET/HEAD of `site/`: allowlisted extensions, no directory listing, no symlinks, no `.vire`, videos up to 512 MiB with Range; other files 1 MiB
- Responses: `X-Content-Type-Options: nosniff`, CSP `default-src 'self'` on static, `Connection: close`
- Token header compared without leaking length via SHA-256 of both sides

There is **no** TLS server. `POST /block` has **no** authorization story on this branch.

### Sealed `.vc` (`VC2`)

Magic `VIRE-VC2`, version 2, 12-byte random nonce, AES-256-GCM, 16-byte tag, 32-byte key required. Key is never printed; fingerprint is 8 hex chars of SHA-256(key). Old XOR seals refused.

A person who has the runner **and** the key can still recover the payload (`payload-write`). The seal is not an obfuscator.

### Process hardening

Unexpected exceptions become exit 3 without a stack trace (`VIRE_DEBUG=1` to see one). JSON/`say` refuse cyclic structures and cap depth. Crash fixtures are required not to kill the process (exit 0–2, not 3).

## Non-guarantees

Caps stop runaway programs; they do not make a program safe on the public internet. Windows desktop UI, `compile-native.vire`, and live `fetch` samples are outside the Phase 0 guarantee list in [SECURITY.md](../SECURITY.md).

## Planned (not implemented — do not write programs as if they exist)

These are **undecided or future** (see open questions on types and capability syntax). They are **not** in the grammar or runtime today:

- **Type checker** — there is no static type system. Values are tagged at run time (`kind`).
- **Taint tracking** — there is no taint lattice, no sanitizer API, and no rejection of tainted data at sinks.
- **Capability syntax** — there are no capability types or grant expressions in source. Isolation is the path/`listen`/`fetch` gates above, not a language-level capability calculus.

Phase 1 security work may add some of the above. Until it ships, treat this page’s “enforced today” list as the whole model.
