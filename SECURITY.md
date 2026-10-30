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
- JSON read/write is depth-capped (256) and size-capped (1,000,000 characters of input; 100,000 items per list or map). `parse with text, schema` refuses the wrong type, a missing required key, and an extra key when the schema is closed. Seeded fuzz of mutated JSON must fail as a Vire error, not a process crash. `say` of a cyclic list or map does not hang the process. `Main` turns unexpected exceptions into exit 3 without a stack trace unless `VIRE_DEBUG=1`.
- Safe-stdlib crypto (interpreter and compiled `.vc` share `VireCrypto`): CSPRNG `random`/`token` (bounded length), HMAC-SHA256, `samebytes` (`CryptographicOperations.FixedTimeEquals`), AES-256-GCM encrypt/decrypt with a required 32-byte key. Encrypt always draws a new 12-byte nonce from `RandomNumberGenerator`; the language API does not accept a caller nonce. Decrypt of a tampered packing returns `could not decrypt that message` and never unwraps `CryptographicException`. No new crypto NuGet packages. **Left:** Ed25519 sign/verify — .NET 10's BCL does not provide a standalone Ed25519 class (only `CompositeMLDsa` hybrids that include Ed25519). Hand-rolled Edwards math is refused.
- Static `listen` GET of `site/` is allowlisted, GET-only, no directory listing, no symlinks, no `.vire` sources.
- Writes of `.js` are allowed only under `site/` (static pages). `.js` under `data/` or any other folder is refused, same as other script extensions.

## Phase 1 attack corpus (runtime half)

`tests/corpus/` is a library of Vire programs that try SQL injection, HTML/script injection, shell injection, path traversal, SSRF (including decimal/hex/octal/mapped IPs, userinfo, and redirect *targets*), JSON bombs / schema abuse, secret leakage through `say`/`json`/error text, resource exhaustion, and malformed `.vc` files.

Each program has a sibling `*.expect.json` (machine-readable):

- `class` — vulnerability class
- `kind` — `source` (`.vire`) or `vc` (sealed bytecode)
- `exit` — required process exit code (1 for a clean Vire error; 0 only when the program itself catches a sanitized error)
- `stderr_contains` / `stdout_contains` — needles that must appear (checked against stderr+stdout so compiler `say` and runner `vire:` errors both count)
- `stderr_forbids` / `stdout_forbids` — needles that must not appear (stack traces, planted secrets, URL passwords)
- `compile_reject` — tags only (`taint`, `types`, `capabilities`). Once Q7/Q8 land, these programs are expected to fail at compile time. **Do not implement that here.**
- `budget` — optional `VIRE_BUDGET` for exhaustion cases

CI (`AttackCorpusTests`) copies each program into a temp folder under `data/corpus-run/`, runs it in the interpreter and as compiled `.vc` (malformed `.vc` files use `vire run` twice), asserts the expect file, asserts exit 3 never happens, and asserts a sentinel file outside the sandbox is unchanged. Tests do not open the public network: SSRF cases use IP literals, `localhost`, or schemes/userinfo that fail before DNS.

### Adding a program

1. Write `tests/corpus/<class>/<name>.vire` (or a `.vc` under `malformed/`).
2. Write `tests/corpus/<class>/<name>.vire.expect.json` (or `.vc.expect.json`) with the fields above.
3. The attack must fail closed *today*: clean error, no crash, no write outside the sandbox.
4. If the program still succeeds at the attack and the fix needs types or capabilities, do not add it to the corpus. List it under **Left** instead.
5. Run `dotnet test tests/Vire.Tests/Vire.Tests.csproj -c Release --filter AttackCorpusTests`.
6. Regenerating the checked-in set: `python3 tools/write-attack-corpus.py`.

## Left

- `site/*.html` (or `site/*.js`) written from concatenated untrusted text still succeeds. That is how `vault.vire` builds pages. Blocking it needs taint or a required `escape` (Q7/Q8). Example that is **not** in the corpus because it currently succeeds: `write with "site/index.html", "<script>" + ask with "x" + "</script>"`.
- Type checker, taint, and capability syntax are not implemented on this branch.

## Non-guarantees

- There is no TLS server, no authorization on `POST /block`, and no public internet hardening beyond loopback-by-default plus an optional token when `VIRE_BIND` is `public`.
- A person who has the runner and the seal key can still read a compiled program. The seal stops casual reading and casual patches. It does not stop every attack.
- Windows desktop, the native compiler, and live network samples are outside this guarantee list.
- Caps stop runaway programs; they do not make a program safe to expose to the internet.
