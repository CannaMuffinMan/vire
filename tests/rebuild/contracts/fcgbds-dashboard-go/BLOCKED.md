# fcgbds-dashboard-go blocked (no stubs)

- static HTML and 307 `/obs` when Dist is set
- optional Upstream HTTP (main leaves nil; no live fetch)
- `X-FCGBDS-Fallback` / `X-FCGBDS-Wall` headers
- stream `Cache-Control: public, max-age=3`
- Go `Content-Type: application/json; charset=utf-8`
- HTTP 405 / 502 (`StatusOf` needles are 507,503,500,431,413,411,408,404,403,401,400). `/api/events` 502 and method-not-allowed stay unproven.
- GET/POST `/api/stream-wall/tilt` 502
- upstream 429 on tilt
- WebSockets, TLS, Postgres, Redis, Railway, Stripe
