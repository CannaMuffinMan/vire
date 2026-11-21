# Vire, rebuild my stack

Caps are unchanged: arena 32MB, list 100000, steps 5M. Sandbox is not weakened.

## Capabilities (this PR)

| Item | Status | Proof |
|---|---|---|
| Guest AES-256-GCM seal/open (`src/rt-aes.vire`) | yes | `aes-gcm-prove.vire` NIST SP 800-38D empty + 16-byte PT; AAD vector; host interpreter |
| Nonce length 12 bytes | yes | 11- and 13-byte nonce REJECT |
| Tag 16 bytes; truncated tag refused | yes | Wycheproof-style truncated-tag REJECT |
| Auth failure returns error, never plaintext | yes | tag-tamper and AAD-tamper REJECT; return length 2 (`bad`, reason) |
| Constant-time *S-box / xtime / GHASH* | source-level | no `sbox at`, no `xtime` high-bit branch, no GHASH bit skip; `AesGcmKatTests.GuestAes256GcmSourceHasNoSecretDependentSboxOrGhashSkip` |
| Constant-time *tag walk* | source-level | `gcm_ct_eq` XORs every byte with no value early-exit; not a CPU timing barrier |
| Host = native ELF stdout | Linux | `tools/aes-gcm-linux.sh` / `AesGcmKatTests.GuestAes256GcmHostMatchesNativeElfOnLinux` |
| Host = native PE stdout | Windows only | `tools/aes-gcm-windows.ps1` for Couchy/CouchStation; **not run in this Linux agent** |
| Compiler/runtime blob (`src/rt.vire`, `compile-native.vire`) | unchanged | AES is a guest library file |

## Side-channel residual risk (honest)

| Surface | What it is | Residual |
|---|---|---|
| AES S-box | Boyar–Peralta bit circuit via `aesBitAnd` / `aesBitXor` / `aesBitOr` / `aesBitNot` (no `sbox at secret`) | Source-level: no secret-dependent list index. Vire `*` `/` `%` and native emit are not a CPU/cache barrier. Compiler and CPU may still leak. |
| MixColumns `xtime` | `hi = idiv b, 128`; reduce with `27 * hi` (no `if d >= 256`) | Branch-free at source. Interpreter/CPU residual remains. |
| GHASH | every multiplier bit: always `gcmXorMasked` then `gcmShr1`; reduction `225 * lsb` | No data-dependent skip/early-exit in the mul loop. Operand values still flow through arithmetic. |
| `gcm_ct_eq` | walks `max(len(left), len(right))`; accumulates XOR of bytes | Length mismatch still distinguishable (length is public for 16-byte tags). Final `if d == 0` is one data-dependent branch on the OR of diffs. **Not** a CPU constant-time barrier. |
| Failed open | does not return plaintext | Ciphertext is still decrypted into a local list after a successful tag check only. Failed tag returns `["bad", "authentication failed"]` without a payload slot. Guest GC does not wipe the computed tag. |

"Constant-time" here means: Vire source for S-box, `xtime`, GHASH mul, and tag walk uses **fixed iteration counts** and **no secret-dependent `at` index or skipped XOR**. It does **not** mean the host interpreter, gen1 native ELF/PE, or the CPU execute those ops in data-independent wall-clock time. Residual: compiler, GC, cache, bignum/`idiv` of secret bytes, and microarchitecture. This is not a lab-measured (TVLA) primitive.

## What this PR does not prove

- Windows PE execute of `aes-gcm-prove` (script exists; this agent is Linux).
- AES-128-GCM, AES-192-GCM, non-96-bit IVs, truncated tags as an *allowed* mode.
- Key wrapping, password KDF binding, disk vault format, or `.vc` seal replacement.
- CPU / cache / TVLA measurements of the bitsliced S-box (source-level only).
- Hardware AES-NI or a verified constant-time compiler.
- Production keys, deployment, payments, or network other than loopback.
- GitHub Actions (account billing-locked; failures there are not code failures).
- gen1=gen2 compiler SHA (runtime blob was not modified; self-host hashes are unchanged by this library).

## Vectors (fixture keys only)

- NIST SP 800-38D / CAVP: 256-bit zero key, 96-bit zero IV, empty PT/AAD → tag `530f8afbc74536b9a963b4f1c4cb738b`.
- Same key/IV, 16 zero PT, empty AAD → CT `cea7403d4d606b6e074ec5d3baf39d18`, tag `d0d1c8a799996bf0265b98b5d48ab919`.
- Same with 16 zero AAD → tag `ae9b1771dba9cf62b39be017940330b4` (same CT; AAD only changes the tag).
- Tamper cases follow Wycheproof AES-GCM invalid-tag / AAD / truncated-tag classes on those fixtures.
