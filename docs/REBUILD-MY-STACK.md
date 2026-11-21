# Rebuild my stack

AI-guided port of an existing service stack into Vire: inventory, capture a contract, port one service, run old vs new until they match, and flag anything that cannot be proven.

This is a method, not a claim that Forever Couch Gang (FCG) already runs on native Vire. Caps stay 32 MB arena, list 100000, 5M steps. No production `fcgcpa-prod` or FCGBC changes. No secrets.

Earlier docs that this file does not replace:

- PR #39 (`docs/fcg-source-inventory.md` on `cursor/multilingual-compile-plan-beb3`): what this token could read in-tree; `fcgcpa-prod` was unread.
- PR #43 (`docs/finish-line-plan.md` on `cursor/finish-line-plan-0b9c`): Nov 10–13 plan. Native `listen` was **not** on that HEAD. It is on this tree (`src/rt-net.vire`, Linux ELF + Windows PE).
- L5 inventory (fcgcpa-prod `main` `5cc11020`): native HTTP listen/TLS named as the #1 blocker; native `/health` on Windows PE was the first slice (`guest-health.vire`, `tools/native-net-windows.ps1`).
- `NATIVE-COMPILER.md` status: gen1 = gen2 self-host is closed on PE and ELF. Do not reopen that work here.
- PR #92: method doc, health contract, fail-before/pass-after harness. This lane stacks on that work.

## Method

Work one service, then one endpoint, until a named SHA proves match. Do not rewrite the whole stack in one PR.

### 1. Inventory

List processes, languages, listen ports, stores, and outbound calls from **source you can read**. If a repo is private, record that and stop. Do not invent routes.

Outputs: service name, language, endpoints, native capabilities required, missing capabilities, human-review flags.

### 2. Contract capture

For each endpoint, freeze a recorded contract (this repo, not a live prod hit):

- method, path, query (if any)
- request headers that the reference requires
- status code
- response headers that matter (`Content-Type`, `Connection`, `X-Content-Type-Options`, `Cache-Control`; not `Date`)
- body (exact bytes when the reference is deterministic; JSON object equality when field order is unspecified)

Contracts live in `tests/rebuild/contracts/`:

- `fcg-health.json` — `GET /health`, `GET /api/health`, `GET /nope`
- `fcg-info.json` — `GET /info`
- `fcg-connect.json` — `GET /connect`

Source of the JSON bodies is in-tree `api/fcgcpa.vire` plus L5 note that Node `GET /health` and `GET /api/health` are unauthenticated. This token still cannot re-open the private Node handler.

### 3. Vire port

Write a `.vire` guest that implements only the captured endpoints. Compile with `compile-native.vire` to a native binary (ELF here, PE on Windows). Do not wrap Node/Go. Do not present a stub as the port.

`guest-health.vire` serves `GET /health`, `GET /api/health`, `GET /info`, `GET /connect`, `GET /payments`, `GET /mine`. Native `rt_net_statusof` maps JSON `"status":N` to the HTTP status line the same way host `VireListen.StatusOf` does.

`guest-chain.vire` serves `GET /chain` and `POST /block` against committed genesis fixtures in `data/rebuild/chain` (copied to `data/chain` by the harness). Proof is `hash` of the same bytes host `json` would emit for `[index, previous, text]` (`"[" + text(index) + "," + json(previous) + "," + json(text) + "]"`). Native listen+`parse` and json-of-list currently crash, so the guest does not call those in `route`.

### 4. Side-by-side differential harness

`tools/rebuild-health-diff.sh`:

1. Compile a **fail-before** guest that violates the contract and require a mismatch.
2. Compile the Vire port to ELF (`listen with 0`).
3. Run the same guest on the **host** interpreter (`listen with 0`).
4. Replay each recorded request against native and host.
5. Diff status, the headers named in the contract, and body. Also require host vs native equality on those fields.
6. Print `PASS_AFTER at <sha>` only when every required case matches.

Reference side is the **recorded contract** plus a live host listen of the same guest. Not a live `fcgcpa-prod` process.

### 5. Proof

A slice is proven when:

- fail-before exits non-zero on a contract miss
- pass-after matches on the ported cases (including `GET /nope` HTTP 404)
- host vs native match on status, key headers, and body
- existing tests still run (none skipped or deleted)
- compiler sources (`compile-native.vire` / emitters) were not edited in this lane; gen1 = gen2 is unchanged from the last closed proof. Re-run `tools/native-elf-selfhost.sh` only if those files change.

### 6. Human-review flags

Flag, do not paper over:

- TLS (no native TLS server)
- WebSocket (guest emit exists only as `tests/native/fixtures/gc-tagged-walk/rt-ws.vire`, not in production `compile-native.vire`)
- unread production Node/Go services
- nondeterministic bodies (timestamps, ids)
- auth tokens (`FCG_API_TOKEN` must never be printed; `/health` stays unauthenticated)

HTTP status from JSON `"status":N` is implemented on native (`rt_net_statusof`, same needles as `VireListen.StatusOf`). Reason phrases stay `OK` vs `Error` on native (host uses `Not Found` / `Forbidden`). Contracts compare numeric status, not the reason phrase.

### Rank 4–5 security property (this PR)

- **Property:** a native listen guest may read `body` only as a heap text whose length is the parsed `Content-Length`, at most `HttpWire.MaxRequestBody` (1_000_000). The object header is marked leaf so GC does not walk payload bytes as pointers. POST/PUT without `Content-Length` is 411 `{"error":"content length required"}`. Oversize CL is 413 `{"error":"body too large"}`. Duplicate/malformed CL stays 400 via the existing parser. The route `body` argument is never a leftover GPR or a `.data` park.
- **Regression:** `tests/rebuild/guests/body-echo.vire` + `tools/rebuild-body-token-diff.sh`; chain goldens in `tools/rebuild-chain-diff.sh`.
- **Platforms:** ELF (proven here). PE uses the same blob; `GetEnvironmentVariableA` is on the net kernel32 IAT. CouchStation must re-run the PE commands below.
- **Residual:** token compare pads 256-byte buffers and XOR-folds (constant-time on the padded copy, not on header parsing). Env token length &lt; 16 means the gate is off (same as host). Arena 32MB / list 100000 / steps 5M unchanged. Header names are scanned in any order; the last header before `\\r\\n\\r\\n` is included.

## Native capabilities (this HEAD)

| Capability | Native status | Evidence |
| --- | --- | --- |
| HTTP listen (loopback) | **Present** PE + ELF | `src/rt-net.vire`, `tools/native-net-windows.ps1`, `tools/native-elf-tcp.sh` |
| HTTP status from JSON `"status"` | **Present** | `rt_net_statusof`; harness `GET /nope` → 404 |
| Content-Type JSON vs text/plain vs HTML | **Present** | JSON is `application/json` (no charset). HTML is `text/html; charset=utf-8`. `rt_net_ctype` + host `ContentTypeOf` |
| JSON encode/parse | **Present** | `rt_json` / `rt_parse`, `json-prove.vire` |
| Schema check | **Present** (guest Vire, host+PE prove) | `src/rt-schema.vire`, `schema_health` |
| TCP client | **Present** loopback only | `tests/native/tcp-client.vire` |
| Files `data/` / `site/` | **Present** | `rt_read` / `rt_write`; Linux `openat` + `O_NOFOLLOW` |
| SHA-256 `hash` | **Present** | `crypto-prove.vire`, million-hash |
| PostgreSQL v3 loopback | **Present, no TLS** | `src/rt-pg.vire`, `tools/pg-prove-linux.sh` |
| Redis loopback | **Present, no TLS** | `src/rt-redis.vire` |
| WebSocket listen | **Not in production compiler** | fixture only |
| TLS server or client | **Missing** | no `tls`/`ssl` in runtime |
| DNS | **Missing** | connect is numeric / loopback |
| Public bind | Host only with `VIRE_BIND=public` and a 16+ char token; native guests print `127.0.0.1` | `GUIDE.md`, `txt_listen` |

Do not call a fixture or a JSON 403 body a TLS or auth implementation.

## Ranked FCG port order

Sources: in-tree `api/`, `sites/`, `guest-health.vire`, PR39 inventory, L5 note on `5cc11020`. Go services `api-go` / `cpa-go` are **not in this repository**.

| Rank | Service / slice | Needs | Native today | Port now? |
| --- | --- | --- | --- | --- |
| 1 | `GET /health` and `GET /api/health` JSON | HTTP, JSON | Both present | **Done (PR #92 + this lane).** |
| 2 | Other unauth JSON on `api/fcgcpa.vire` (`/info`, `/connect`) | HTTP, JSON | Present | Done (PR #93). |
| 3 | `fcgbds-go` `GET /health` | HTTP, JSON | Present | **This PR.** Field match; `ts` omitted (no guest clock). |
| 3a | `fcgbc-go` `GET /pending-transactions` | HTTP, JSON | Present | **This PR.** Body `[]`. |
| 3b | `cpa-go` `GET /health` | HTTP, text/plain | Present | **This PR.** `ok\\n` + native/host text/plain Content-Type. |
| 3c | `rpc-portal-go` `GET /api/health` | HTTP, JSON | Present | **This PR.** `{"ok":true}`. Not Node/fcgcpa health. |
| 3d | `api-go` `GET /healthz` | HTTP, JSON | Present | **This PR.** `{"status":"ok","live":true}`. Not `api-go` `/api/health`. |
| 3e | `api/fcgcpa.vire` `/payments` and `/mine` 403 | HTTP, JSON, status from `"status"` | Mapping present | **Done (this PR).** GET 403 bodies match `api/fcgcpa.vire`; payments stay off. |
| 4 | `GET /chain`, `POST /block` | HTTP, JSON, `data/` files, `hash` | GET + POST on native (bounded body, Content-Length required) | **Done (this PR).** Native `rt-net` request body is a leaf heap text capped at 1_000_000, fail-closed 411/413/400. Host vs native `/block` vs `tests/rebuild/contracts/fcg-chain.json`. |
| 5 | `FCG_API_TOKEN` on non-health paths | HTTP, constant-time header compare | Host `VireListen` and native guest | **Done (this PR).** Native `X-FCG-Token` vs env `FCG_API_TOKEN` (16+ chars); GET/HEAD `/health` exempt; 401 `{"error":"unauthorized"}`. Fixture token only. |
| 6 | `landing-go` unauth fixtures (healthz, JSON APIs, 307s, held-503, fixture HTML) | HTTP, JSON, text/html, Location / WWW-Authenticate | Present on this PR (Linux ELF harness) | **This PR.** Rank 6 static HTML is in-tree strings. Host vs native `tools/rebuild-landing-diff.sh`. |
| 6a | `landing-go` SOP HMAC cookie auth | cookies, HMAC-SHA256 | Missing | **Blocked.** No stubs. |
| 6b | `landing-go` reverse-proxy (`LANDING_UPSTREAM` / `LANDING_API_UPSTREAM`) | outbound HTTP proxy | Loopback client only; no Host rewrite | **Blocked.** No stubs. |
| 6c | `landing-go` Shopify / media-lab APIs | held 503 in Go; out of scope here | — | **Blocked.** No stubs. |
| 7 | Node landing/API from `fcgcpa-prod` | HTTP, JSON, likely TLS, likely more routes | TLS missing; prod unread here | Blocked on recorded contracts from a local-only read |
| 8 | Rest of Go `api-go` / `cpa-go` | JWT, cookies, proxy, … | Health GETs only | Remaining routes blocked on missing native features |
| 8a | `rpc-portal-go` unauth beyond `/api/health` | HTTP, JSON, 403/404/503 | Present | **This PR.** capabilities `node:false`, rpc-off 503, transfer 403, dist_missing, 404. JWT/vault/holdings/static/405 mux blocked. |
| 8b | `edge-go` `/healthz` + maintenance JSON | HTTP, text/plain, 503 | Present | **This PR.** `/healthz` `ok`; unknown path 404; maintenance-on JSON. Reverse-proxy Host map blocked. |
| 8c | `dev-portal-go` dist_missing | HTTP, JSON 503 | Present | **This PR.** GET `/` and `/login` 503 `dist_missing` before cookie gate. JWT/307/proxy/static blocked. |
| 8d | `fcgbds-dashboard-go` Upstream-nil APIs | HTTP, JSON, 404/503 | Present | **This PR.** health/challenge/stats/heartbeat/stream-wall + dist_missing + `/api/*` 404. 405/502, static/307/upstream blocked. |
| 9 | Loopback Postgres/Redis if those Go services use them | DB client, no TLS | Clients exist; not wired to FCG | After a recorded SQL/RESP contract |
| 10 | WebSocket chat / live | WS, maybe TLS | Fixture only | Blocked |
| 11 | Public TLS terminator | TLS | Missing | Reverse proxy in front of loopback, or a later TLS lane. Not a stub. |
| 12 | Skinned browser, Proof of Rot miner, shop, OAuth clients | unknown | none | Blocked on missing source (PR39) |

### Rank 3 sidecar goldens (this PR)

Minimal fixtures only (derived from source, not live). No auth, internal hostnames, env lists, or maintenance-bypass.

- `fcgbds-go GET /health` → 200 JSON; fields `ok=true`, `service=fcgbds-core`, `dbConfigured=false`, `paymentsEnabled=false`. Go also sends `ts=now()`; this guest omits `ts`.
- `fcgbc-go GET /pending-transactions` → 200, body `[]`
- `cpa-go GET /health` → 200, `Content-Type: text/plain; charset=utf-8`, body `ok\n`
- `rpc-portal-go GET /api/health` → 200, `{"ok":true}`
- `api-go GET /healthz` → 200, `{"status":"ok","live":true}` (Go listen is `API_GO_ADDR`; guest still loopback `listen`)

Harness: `tools/rebuild-sidecar-diff.sh` (fail-before / pass-after / host vs native per slice). Unauth Go sidecars: `tools/rebuild-unauth-sidecar-diff.sh` (also invoked from the sidecar harness). Goldens in `tests/rebuild/contracts/<service>/`.

### Rank 1–2 contracts (proven on Linux ELF in prior lanes)

Recorded in `tests/rebuild/contracts/`:

- `GET /health` → 200, `Content-Type: application/json` (no charset; Go `writeJSON` in fcgbds-go `server.go`), `Connection: close`, `nosniff`, `Cache-Control: no-store`, body `{"ok":true,"service":"fcgcpa","payments":false}`
- `GET /api/health` → same
- `GET /info` → 200, same headers, body from `api/fcgcpa.vire` `/info`
- `GET /connect` → 200, same headers, body `{"twitch":"https://www.twitch.tv","youtube":"https://www.youtube.com"}`
- `GET /nope` → HTTP **404**, body `{"ok":false,"status":404,"error":"not found"}` (host `StatusOf` and native `rt_net_statusof`)
- `GET /payments` → HTTP **403**, body `{"ok":false,"status":403,"error":"payments are off"}`
- `GET /mine` → HTTP **403**, body `{"ok":false,"status":403,"error":"mining stays inside the app"}`
- `GET /chain` (genesis fixture) → 200, body one genesis block whose `proof` is host `hash` of `[0,"0",""]`
- `POST /block` malformed → HTTP **400** (`bad block` / `text is required` / `text is not allowed` / `proof does not match`)
- `POST /block {"text":"fixture-one"}` → 200, proof `hash` of `[1,<genesis proof>,"fixture-one"]`

Harnesses: `tools/rebuild-health-diff.sh`, `tools/rebuild-sidecar-diff.sh`, `tools/rebuild-chain-diff.sh`, `tools/rebuild-landing-diff.sh`. Windows PE steps (CouchStation only): `tools/rebuild-fcgcpa-windows.ps1` — this Linux lane does not claim PE proof.

### What this PR does not prove

- Byte-identical Node handler vs Vire (private repo unread)
- Native POST `/block` body read is proven on this branch (bounded leaf heap text). Remaining chain rotate/507/503/migrate is not.
- Remaining `api/fcgcpa.vire` chain behavior: segment rotate at 512 KB, 507 when full, 503 on tamper, old `data/chain.json` migrate, concurrent posts, `previousHash` alias beyond `previous`/`proof`
- Remaining sidecar routes beyond the five GET goldens plus unauth rpc-portal-go / edge-go / dev-portal-go / fcgbds-dashboard-go JSON (JWT, reverse-proxy, static files, holdings outbound still blocked)
- Native listen does not emit Go extra security headers (`X-Frame-Options`, `Referrer-Policy`, `Permissions-Policy`) or per-route Cache-Control / charset=utf-8; contracts match the native header set (`application/json` without charset, `nosniff`, `no-store`)
- HTTP 405 and 502: `StatusOf` / `rt_net_statusof` needles do not include those codes. Guest JSON may still carry `"status":405` / `"status":502` at HTTP 200.
- `landing-go` SOP HMAC cookies, reverse-proxy upstreams, Shopify/media-lab (blocked; no stubs)
- Go `Cache-Control: public` on `/api/capabilities` (Vire listen stays `no-store`)
- `api-go GET /api/health` (`status`/`version`/`ready`) — keep separate from Node/fcgcpa health and from `/healthz`
- Guest clock / RFC3339 `ts` on `fcgbds-go` health
- TLS, WebSocket, DNS, public bind
- Go microservices
- Payments on, mining network, testnet
- Compiler self-host identity is re-proved after `parkNet` `txt_hdrs` (JSON Content-Type without charset), `rt_net_statusof` blob pins, and the body/token blob. `compile-native.vire` was not edited.

## Commands

```text
bash tools/rebuild-health-diff.sh
bash tools/rebuild-sidecar-diff.sh
bash tools/rebuild-unauth-sidecar-diff.sh
bash tools/rebuild-chain-diff.sh
bash tools/rebuild-landing-diff.sh
dotnet test tests/Vire.Tests/Vire.Tests.csproj -c Release --nologo
```

Windows PE health remains `tools/native-net-windows.ps1` (needs gen1 PE). Rank 3e/4 PE steps are `tools/rebuild-fcgcpa-windows.ps1`. This Linux lane does not replace that proof.
