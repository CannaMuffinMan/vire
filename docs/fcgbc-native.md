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

## HTTP status (native gap)

Host `VireListen` with `VIRE_FCGBC_HTTP=1` maps the Go error strings to 204/400/404/429/503. Native `rt_net_sendhttp` still sends `HTTP/1.1 200` for a successful `route` return. The Linux harness treats body+CORS match on stub routes as proven **with a native-status gap**.

Native request parsing only allows GET/POST/HEAD/PUT, so `OPTIONS` is **not proven** (Go 204, native 400). Rate limit 181st body `error=Rate limit exceeded` is proven; `retryAfterMs` is not byte-identical (native ticks are not Go wall ms). `GET /info` `port` is the bind port on Go and 3011 in the fixture guest; JSON compare ignores `port`.

## Prove

```text
# local copy of fcgbc-go (not in this public repo)
export FCGBC_GO_DIR=/tmp/fcgbc-go
bash tools/rebuild-fcgbc-diff.sh
```

Windows PE listen for this guest is **not** run here.

Caps unchanged: arena 32MB, list 100000, steps 5M.
