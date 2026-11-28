# rpc-portal-go blocked (no stubs)

TODO(VIRE-FINISH-NOW): prove remaining rpc-portal-go outbound/auth/static routes listed below on host and native without raising caps.

- GET `/api/holdings` (outbound HTTP, 429 rate limit)
- GET `/api/rpc` with a node (outbound)
- `/api/dev/*` JWT cookie, Origin CSRF, AES-GCM vault, Postgres pool
- static files when `RPC_PORTAL_DIST` is a directory
- `X-Frame-Options`, `Referrer-Policy`, `Permissions-Policy` (native listen headers are fixed)
- capabilities `Cache-Control: private, max-age=5` (native is `no-store`)
- Go mux 405 empty body (Vire JSON `"status":405` is `method-not-allowed.json`)
- GET `/api/rpc` with a configured node (outbound)

See `docs/fcg-contracts-missing.md`.
