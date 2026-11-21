# Vire, rebuild my stack

Caps are unchanged: arena 32MB, list 100000, steps 5M. Sandbox is not weakened.

## Capabilities (this PR)

| Item | Status | Proof |
|---|---|---|
| Guest AES-256-GCM seal/open (`src/rt-aes.vire`) | yes | `aes-gcm-prove.vire` NIST SP 800-38D empty + 16-byte PT; AAD vector; host interpreter |
| Nonce length 12 bytes | yes | 11- and 13-byte nonce REJECT |
| Tag 16 bytes; truncated tag refused | yes | Wycheproof-style truncated-tag REJECT |
| Auth failure returns error, never plaintext | yes | tag-tamper and AAD-tamper REJECT; return length 2 (`bad`, reason) |
| Constant-time *tag walk* | partial | `gcm_ct_eq` visits every byte; not a CPU timing barrier |
| Host = native ELF stdout | Linux | `tools/aes-gcm-linux.sh` / `AesGcmKatTests.GuestAes256GcmHostMatchesNativeElfOnLinux` |
| Host = native PE stdout | Windows only | `tools/aes-gcm-windows.ps1` for Couchy/CouchStation; **not run in this Linux agent** |
| Compiler/runtime blob (`src/rt.vire`, `compile-native.vire`) | unchanged | AES is a guest library file |

## Side-channel residual risk (honest)

| Surface | What it is | Residual |
|---|---|---|
| AES S-box | 256-byte table lookup `sbox at (s at i)` | Cache-timing / table-lookup leakage of round state. Not bitsliced, not T-table-free, not hardware AES-NI. |
| MixColumns `xtime` | data-dependent branch `if d >= 256` | Timing may correlate with high bit of bytes. |
| GHASH | skips `xor` when the multiplier bit is 0 | Operand-dependent GHASH timing. |
| `gcm_ct_eq` | walks `max(len(left), len(right))` and ORs diffs | Length mismatch still distinguishable; byte values are not early-exited. **Not** a CPU constant-time barrier (interpreter / native IR still branch on `if a != b` to set the flag). |
| Failed open | does not return plaintext | Ciphertext is still decrypted into a local list after a successful tag check only. Failed tag returns `["bad", "authentication failed"]` without a payload slot. Guest GC does not wipe the computed tag. |

This is a correctness primitive for fixture KATs, not a hardened vault against microarchitectural attackers.

## What this PR does not prove

- Windows PE execute of `aes-gcm-prove` (script exists; this agent is Linux).
- AES-128-GCM, AES-192-GCM, non-96-bit IVs, truncated tags as an *allowed* mode.
- Key wrapping, password KDF binding, disk vault format, or `.vc` seal replacement.
- Constant-time AES (no table lookups).
- Side-channel lab measurements (cache, PMU, or TVLA).
- Production keys, deployment, payments, or network other than loopback.
- GitHub Actions (account billing-locked; failures there are not code failures).
- gen1=gen2 compiler SHA (runtime blob was not modified; self-host hashes are unchanged by this library).

## Vectors (fixture keys only)

- NIST SP 800-38D / CAVP: 256-bit zero key, 96-bit zero IV, empty PT/AAD → tag `530f8afbc74536b9a963b4f1c4cb738b`.
- Same key/IV, 16 zero PT, empty AAD → CT `cea7403d4d606b6e074ec5d3baf39d18`, tag `d0d1c8a799996bf0265b98b5d48ab919`.
- Same with 16 zero AAD → tag `ae9b1771dba9cf62b39be017940330b4` (same CT; AAD only changes the tag).
- Tamper cases follow Wycheproof AES-GCM invalid-tag / AAD / truncated-tag classes on those fixtures.
