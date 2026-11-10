# Rewrite unit. api-go/

Inventory SHA `5cc110206f8f42ee25c127f2bfbe0f8bcd6067f4`. This agent did not re-open the files.

## Source paths

- `api-go/` README still says non-deployed. No `api-go/railway.toml`.
- `api-go/internal/httpx/native.go`. Exact GET list that is native in Go. Payments proxy unless `GO_NATIVE_PAYMENTS` / `GO_NATIVE_BILLING`, default off.
- Reserved closed paths return 503 `node_retired` instead of proxy. `/api/profile/theme`, `/api/profile/entitlements`, `GET /api/auth/owner/complete`, `POST /api/auth/email/register`.
- Listen default `:8080`. Default `NODE_API_URL` `http://127.0.0.1:3001`. Node default listen is 4001. Those defaults do not match.
- Upgrade `/ws/kick` forwards to Node.

## Behavior to preserve

Optional front door. Product writes stay in Node `api/` until a Vire write path exists. Do not treat Go native GETs as the source of truth for mutations.

If you compile this unit at all, keep 503 on the reserved closed paths. Keep payments proxy off.

## Acceptance tests

1. Input `GET` of a path on the Go native list with Node down. Expected the Go handler status, not a proxy error. Re-read `native.go` before coding. Do not invent the list here.
2. Input `GET /api/profile/theme`. Expected 503 and body marking `node_retired`.
3. Input billing path with `GO_NATIVE_BILLING` unset. Expected proxy or fail, not a Go charge.
4. Default listen 8080. Upstream default 3001 disagrees with Node 4001. A Vire port of the door must document the upstream port it uses. Prefer 4001 to match Node.

## Vire capability

HTTP listen plus still the Node write path. Wrapping `go` fails the native claim. Skip this unit until `api/` health exists. Friday skip.

## Security

Strangler can 503 auth register. Do not silently drop account creation. Proxy to Node is an extra trust hop.

## Size and order

Small relative to `api/`. Not on the Friday critical path. After `api/` health, not before.
