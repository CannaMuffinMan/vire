# Rewrite unit. rpc-portal/

Inventory SHA `5cc110206f8f42ee25c127f2bfbe0f8bcd6067f4`. This agent did not re-open the files.

## Source paths

- `rpc-portal/` Next 16.3.5, jose, pg. Block explorer UI.
- Slice API `slice1-api/server.js`.
- `rpc-portal-go/`.
- Tests named for passphrase hash, zoom, protected wallets.

## Behavior to preserve

Read-only explorer against a chain the operator names. Do not import testnet fixtures into Vire.

`edge-go` maps rpc host to service `fcgbc` port 3001. That name is a Railway service, not a Vire testnet dump.

## Acceptance tests

1. Input passphrase hash test from this package. Expected pass on the Node app. Vire must match the hash function once re-read.
2. Input protected wallet routes without auth. Expected deny.
3. Input any fixture load of testnet blocks. Expected refuse.

## Vire capability

HTTP plus SQL plus chain read. jose JWT is not in Vire. Postgres is not in Vire.

Friday skip.

## Security

Explorer leak of protected wallets. jose token confusion. Read-only by default.

## Size and order

After a chain read API that is not a testnet copy. After native HTTP. Not Friday.
