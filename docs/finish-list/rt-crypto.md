# rt-crypto / KDF / AES finish list

Lane: `cursor/cleanup-rt-crypto`. Only `src/rt-crypto.vire`, `src/rt-kdf.vire`, `src/rt-aes.vire`, root `crypto-*.vire`, `kdf-prove.vire`, `pbkdf2-*.vire`, `aes-gcm-prove.vire`, `hex-range.vire`, and this file.

## Placeholders (kept)

| File | Symbol | What's missing | Priority |
| --- | --- | --- | --- |
| `src/rt-crypto.vire` | `sha256_bytes` | Guest SHA-256 (`cryptoPad` / `cryptoCompress` / `cryptoK` / `cryptoIv`) was unused; wrapper still calls builtin `digest`. Re-implement guest pad+compress+IV if builtins must not be the only path. | P2 |

Marker in source: `TODO(VIRE-FINISH-NOW): wire guest SHA-256 pad+compress+IV into this wrapper instead of digest`

## Removals this lane

| Path / symbol | Why dead | Evidence |
| --- | --- | --- |
| `src/rt-crypto.vire` `cryptoCopy32_into` … `cryptoPad`, `cryptoWord`, `times2`, `times8`, `times256`, `cryptoAnd16`/`Xor16`/`Not16`, 32-bit SHA helpers, `cryptoK`, `cryptoIv`, `cryptoCompress` | Superseded guest SHA-256; `sha256_bytes` / `hmac_sha256` call `digest` / `hmac`. No other `.vire` call sites. | repo grep: only `src/rt-crypto.vire` (pre-cut) and `data/src/rt-crypto.vire` copy |
| `src/rt-kdf.vire` `bcryptXor8` | Unused; `bcryptMakeXorTab` inlines the same 8-bit XOR | grep: only the removed `define` |
| `pbkdf2-budget.vire` | Stale scratch (round-count printer). Not in CI, tests, tools, `.github`, docs | grep `pbkdf2-budget`: no hits |

`times4` kept (b64url). Public wrappers `bcrypt_hash` / `bcrypt_verify` / `pbkdf2_sha256` kept. All KAT prove files except `pbkdf2-budget.vire` kept. Constant-time `ct_eq` / `bcrypt_ct_eq` / `gcm_ct_eq` kept.

## Cross-lane notes (untouched)

- `data/src/rt-crypto.vire` still holds the old guest SHA-256 copy until `CompilerStage.CopyToData` / `tools/stage-compiler-src.sh` refresh it. Out of this lane's edit paths.
- `session-prove.vire` uses `src/rt-crypto.vire` HMAC helpers; not in this lane.
- `tests/native/million-hash.vire` duplicates `crypto-mb.vire` `millionA`.
- `src/sop-cookie.vire` / `src/portal-jwt.vire` use live JWT/cookie/HMAC APIs; not dead.
- `hex-range.vire` is wired by `tests/Vire.Tests/HexOfTests.cs` (`hexOf` / `src/asm.vire`); not crypto dead code.
