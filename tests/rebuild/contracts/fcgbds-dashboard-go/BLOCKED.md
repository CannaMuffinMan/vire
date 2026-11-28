# fcgbds-dashboard-go blocked (no stubs)

TODO(VIRE-FINISH-NOW): prove remaining dashboard-go routes/headers listed below on host and native without raising caps.

- static HTML and 307 `/obs` when Dist is set
- optional Upstream HTTP (main leaves nil; no live fetch)
- `X-FCGBDS-Fallback` / `X-FCGBDS-Wall` headers
- stream `Cache-Control: public, max-age=3`
- Go `Content-Type: application/json; charset=utf-8`
- HTTP 405 mapping (another agent). Per-route JSON does not include GET 405 cases.
- upstream 429 on tilt (nil-Upstream 502 is `api-stream-wall-tilt.json`)
- WebSockets, TLS, Postgres, Redis, Railway, Stripe
