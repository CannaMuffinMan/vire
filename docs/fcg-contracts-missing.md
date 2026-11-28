# FCG portal and edge contracts missing from this tree

This public repo has JSON goldens under `tests/rebuild/contracts/` for some rpc-portal-go, edge-go, dev-portal-go, and fcgbds-dashboard-go routes. Routes below have **no** in-tree request/response fixture. They stay unimplemented here. Do not invent bodies.

Private contract text for the goldens that **are** in tree came from `fcgcpa-prod` draft PR #147 `docs/vire-contracts/*.md` (same pattern as `docs/fcgbc-native.md`). The Go sources that would fill the gaps are not in this repository.

Caps stay arena 33554432, list 100000, steps 5000000, itemCap 1e6.

## rpc-portal-go

| route | missing in this tree | private file that would supply it |
|---|---|---|
| GET `/api/holdings` | status, body, 429 headers, outbound node URL | `fcgcpa-prod` `docs/vire-contracts/rpc-portal-go.md`; Go handler for holdings |
| GET `/api/rpc` with `FCGBC_BASE_URL` set | outbound JSON-RPC body | `fcgcpa-prod` `docs/vire-contracts/rpc-portal-go.md` |
| POST `/api/dev/auth` success (admin password) | password check, Set-Cookie bytes | `fcgcpa-prod` rpc-portal-go auth handler (secret material must stay out of this repo) |
| `/api/dev/*` AES-GCM vault, Origin CSRF, Postgres | ciphertext fixtures, CSRF header table, SQL | `fcgcpa-prod` rpc-portal-go vault/CSRF/pool code |
| GET `/` when `RPC_PORTAL_DIST` is a real directory | HTML bytes of the portal dist | private dist build; only `data/rebuild-dist` sandbox HTML is here |
| `X-Frame-Options`, `Referrer-Policy`, `Permissions-Policy` | extra Go header table | `fcgcpa-prod` rpc-portal-go middleware; native listen headers are fixed |
| GET `/api/capabilities` `Cache-Control: private, max-age=5` | that Cache-Control value | same; native listen emits `no-store` |
| POST `/api/health` Go ServeMux empty 405 body | empty body bytes | Go 1.22 ServeMux; Vire maps 405 via JSON `"status":405` in `rpc-portal-go/method-not-allowed.json` |

In-tree JSON that **is** proven on host and native: `tests/rebuild/contracts/rpc-portal-go/*.json` except this list.

## edge-go

| route | missing in this tree | private file that would supply it |
|---|---|---|
| reverse-proxy `Host` map to `*.railway.internal` | target table, TLS, DNS | `fcgcpa-prod` `docs/vire-contracts/edge-go.md`; edge-go Host map |
| `Location` rewrite, `X-Forwarded-Host`, `X-Forwarded-Proto` | exact rewrite cases | same; loopback proxy cases stay in `edge-go.json` (owned by the proxy lane) |
| SHA-256 `X-FCG-Maintenance-Bypass`, CIDR `MAINTENANCE_ALLOW_IPS` | bypass token and CIDR fixtures | `fcgcpa-prod` edge-go maintenance gate |
| `PAYMENTS_ENABLED` startup refuse | process-exit contract (no HTTP body) | `fcgcpa-prod` edge-go main |
| maintenance HTML, `Retry-After`, `X-Robots-Tag` | HTML bytes and extra headers | `fcgcpa-prod` edge-go maintenanceHTML; JSON-only golden is `edge-go/maintenance.json` |
| public `0.0.0.0` bind | bind address proof | Vire listen is loopback only |

In-tree JSON that **is** proven: `edge-go/healthz.json`, `edge-go/not-found.json`, `edge-go/maintenance.json`. `edge-go.json` loopback proxy cases are not changed here.

## dev-portal-go

| route | missing in this tree | private file that would supply it |
|---|---|---|
| GET `/` HTML when `DEV_PORTAL_DIST` exists | real dist bytes | private Next dist; sandbox is `data/rebuild-dist` |
| static 405 Allow GET, HEAD after dist exists | Allow header table | `fcgcpa-prod` `docs/vire-contracts/dev-portal-go.md` |
| GET `/api/auth/session` 503 `not_configured` with auth cookie present | cookie plus missing secret body | same; unauth 503 without cookie is not that case |
| HTTPS `FCG_API` proxy target | TLS upstream goldens | public HTTPS target stays blocked |
| POST `/api/auth/session` Set-Cookie wire bytes | exact `Set-Cookie` string | `fcgcpa-prod` dev-portal-go session writer |

In-tree JSON that **is** proven: `dev-portal-go/dist-missing.json`. Cookie 307 and JWT listen cases live in `dev-portal-go-auth.json` / `dev-portal-go.json` and `tools/rebuild-portal-diff.sh`. `/fcg-api/` proxy body is owned by another agent.

## fcgbds-dashboard-go

| route | missing in this tree | private file that would supply it |
|---|---|---|
| static HTML and 307 `/obs` `Location` when Dist is set | HTML bytes, Location target | `fcgcpa-prod` `docs/vire-contracts/fcgbds-dashboard-go.md`; Go dist + `/obs` redirect |
| optional Upstream HTTP (main leaves nil) | live upstream goldens | Go dashboard Upstream client; main is nil |
| `X-FCGBDS-Fallback`, `X-FCGBDS-Wall` | those header values | Go dashboard header writer |
| stream `Cache-Control: public, max-age=3` | that Cache-Control value | same; native listen is `no-store` |
| `Content-Type: application/json; charset=utf-8` | charset on JSON | Go Encoder; native JSON is `application/json` without charset |
| GET 405 empty or Go-shaped bodies for mux miss | dashboard 405 mapping | **out of scope** (another agent). Per-route JSON here has POST success cases only for challenge-verify and heartbeat |
| GET/POST `/api/stream-wall/tilt` 429 from upstream | 429 body | Go tilt upstream; nil-Upstream 502 is `api-stream-wall-tilt.json` |
| WebSockets, TLS, Postgres, Redis, Railway, Stripe | those protocols | private dashboard services |

In-tree JSON that **is** proven: every `fcgbds-dashboard-go/*.json` file except this list. Dashboard GET 405 cases in the aggregated `fcgbds-dashboard-go.json` are unchanged.

## How to add a missing row

Copy a fixture-only JSON next to the existing files. Derive it from the private contract markdown, not from a live host. Keep secrets out of this public repo.
