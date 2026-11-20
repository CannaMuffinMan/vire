# fcgbc-go native port

Public-repo port of the FCG blockchain sidecar (`fcgbc-go`) onto native Vire. Source of the contract: private `fcgcpa-prod` draft PR #147 (`docs/vire-contracts/fcgbc-go.md`). This tree copies **fixtures only** (wallet JSON, fixture block hash). No secrets, no live hosts, no key custody.

## SHA-256

Already in `src/rt-crypto.vire` / `hash`. NIST vectors:

| Input | Hex | Guest |
| --- | --- | --- |
| empty | `e3b0c442…855` | `crypto-prove.vire` |
| `abc` | `ba7816bf…15ad` | `crypto-prove.vire` |
| 448-bit (`abcdbcde…nopq`) | `248d6a61…06c1` | `crypto-prove.vire` |
| 1M `a` | `cdc76e5c…2cd0` | `tests/native/million-hash.vire` (string, not a 1M-byte list; list cap stays 100000) |

`crypto-prove.vire` still skips a 1M **byte-list** hash because the list cap is 100000.

## What the guest does

`guest-fcgbc.vire` (compile with `compile-native.vire`):

- Fixture chain (genesis + one transfer Alice→Bob). Block hash preimage matches Go `BlockHashInput` then SHA-256.
- JSON reads: `/blockchain`, `/block/{index}` (`parseInt` prefix like Go), `/pending-transactions`, `/peers`, `/info`, wallet balance/couchcred.
- 503 stubs with the same Go strings: `/transaction`, `/mine`, `/mine-engagement`, `/wallet/create`, `/wallet/import`, `/peers/broadcast`, `/bridge/out`, `/bridge/in`.
- `/contract/…` 404 body.
- In-memory **file** fixed window 180/60s (`data/fcgbc-state.json`). Loopback is one bucket (no `X-Forwarded-For` in native `route`).
- Wallet create/import stay refused. No signing.

## CORS

Go default (no `Origin`, `NODE_ENV` not production): `Access-Control-Allow-Origin: *` plus the methods/headers strings from `fcgbc-go/server.go`. Native parked those on every `sendhttp` (`src/rt-net.vire` `txt_hdr2`). Host interpreter emits the same when `VIRE_FCGBC_HTTP=1`, and reflects listed origins.

## HTTP status

Native `rt_net_statusof` is the PR #93 JSON `"status":N` scan (needles include 429). fcgbc Go bodies do not carry that field, so a small extra scan maps the same error strings host `FcgbcStatus` uses to 400/404/429/503. Empty `route` bodies (OPTIONS) become **204**. Overlap with #93: merge **#92 → #93 → #98**.

Parser allowlist is GET/POST/HEAD/PUT plus **OPTIONS** (`rt_net_optchk`). Any other method still goes to `cl_501`.

## retryAfterMs

Go: remaining milliseconds in the 60s IP window (`time.Until`). Native: no wall clock in the guest (`now` is reserved), so the JSON always uses integer `1`. Harness checks **field shape** (`error` string + `retryAfterMs` number), not the millisecond value.

`GET /info` `port` is the bind port on Go and 3011 in the fixture guest; JSON compare ignores `port`.

## Prove

```text
# local copy of fcgbc-go (not in this public repo)
export FCGBC_GO_DIR=/tmp/fcgbc-go
bash tools/rebuild-fcgbc-diff.sh
```

Windows PE listen for this guest is **not** run here.

Caps unchanged: arena 32MB, list 100000, steps 5M.
