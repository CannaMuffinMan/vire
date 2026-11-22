# Rewrite unit. fcgbc-go and the JS chain

Inventory SHA `5cc110206f8f42ee25c127f2bfbe0f8bcd6067f4`. This agent did not re-open the files. Do not copy FCGBC testnet into Vire.

## Source paths

- `fcgbc-go/cmd/fcgbc-go/main.go`. Refuses `PAYMENTS_ENABLED` on. Refuses staging DB. Listen default 3011, not 7099 or 8778.
- `fcgbc-go` 503s mine and 404s `/contract`. That mine 503 is not api-go `node_retired`.
- JS node `api/src/blockchain/node.js` plus `copy-blockchain-runtime.js`. In-memory. `/mine`, `/mine-engagement`.
- `wallet.js`, `fcgbcChainDb.js` with no caller.
- Client posts to `/por/mine`, `/contract/.../register-wallet`, `/governance/anchor` that no in-tree process implements.

## Behavior to preserve

Refuse payments. Refuse staging DB. Stay off reserved ports. Do not mine on the Go node.

Do not treat the JS in-memory chain as production FCGBC. Do not dump chain JSON into this repo.

Vire `api/fcgcpa.vire` disk JSON chain is a different design. Do not merge it with this unit without an operator call.

## Acceptance tests

1. Input process start with `PAYMENTS_ENABLED=true`. Expected refuse to listen.
2. Input `POST` mine on `fcgbc-go`. Expected 503. Do not assert the body `node_retired` or `chain invalid`.
3. Input `GET` or `POST` `/contract` on `fcgbc-go`. Expected 404.
4. Input listen port. Expected 3011 default. Expected fail if asked to bind 7099 or 8778.
5. Input JS node `/por/mine`. Expected miss. Document the hole. Do not invent a miner to make the test green.

## Vire capability

HTTP listen. SHA-256 `hash` can clone the toy JS miner. That would still be the wrong product if live RPC is elsewhere. Native HTTP still missing on this branch.

Friday. A toy SHA-256 chain in VIR is possible after listen. It is not the FCG stack. Do not do it in this PR.

## Security

Payments refuse is load-bearing. Staging DB refuse is load-bearing. Client/server PoR algorithm mismatch. `ethers.verifyMessage` versus SHA-256 wallet signatures.

## Size and order

After operator names live RPC. Never import testnet. Not on Friday critical path for "entire stack".
