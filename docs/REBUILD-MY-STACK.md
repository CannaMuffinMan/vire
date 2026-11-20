# Rebuild my stack

AI-guided port of an existing service stack into Vire: inventory, capture a contract, port one service, run old vs new until they match, and flag anything that cannot be proven.

This is a method, not a claim that Forever Couch Gang (FCG) already runs on native Vire. Caps stay 32 MB arena, list 100000, 5M steps. No production `fcgcpa-prod` or FCGBC changes. No secrets.

Earlier docs that this file does not replace:

- PR #39 (`docs/fcg-source-inventory.md` on `cursor/multilingual-compile-plan-beb3`): what this token could read in-tree; `fcgcpa-prod` was unread.
- PR #43 (`docs/finish-line-plan.md` on `cursor/finish-line-plan-0b9c`): Nov 10–13 plan. Native `listen` was **not** on that HEAD. It is on this tree (`src/rt-net.vire`, Linux ELF + Windows PE).
- L5 inventory (fcgcpa-prod `main` `5cc11020`): native HTTP listen/TLS named as the #1 blocker; native `/health` on Windows PE was the first slice (`guest-health.vire`, `tools/native-net-windows.ps1`).
- `NATIVE-COMPILER.md` status: gen1 = gen2 self-host is closed on PE and ELF. Do not reopen that work here.

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

The FCG health contract lives in `tests/rebuild/contracts/fcg-health.json`. Source of the JSON body is in-tree `api/fcgcpa.vire` plus L5 note that Node `GET /health` and `GET /api/health` are unauthenticated. This token still cannot re-open the private Node handler.

### 3. Vire port

Write a `.vire` guest that implements only the captured endpoints. Compile with `compile-native.vire` to a native binary (ELF here, PE on Windows). Do not wrap Node/Go. Do not present a stub as the port.

First slice: `guest-health.vire` (`GET /health`, `GET /api/health`). It already existed; this lane adds the differential harness and the method, it does not re-emit the HTTP runtime.

### 4. Side-by-side differential harness

`tools/rebuild-health-diff.sh`:

1. Optionally compile a **fail-before** guest that violates the contract and require a mismatch.
2. Compile the Vire port to ELF.
3. Bind `127.0.0.1` on an OS port (`listen with 0` in the harness copy).
4. Replay each recorded request.
5. Diff status, the headers named in the contract, and body.
6. Print `PASS_AFTER at <sha>` only when every required case matches.

Reference side is the **recorded contract**, not a live `fcgcpa-prod` process.

### 5. Proof

A slice is proven when:

- fail-before exits non-zero on a contract miss
- pass-after matches on the ported cases
- `tools/native-elf-selfhost.sh` still prints gen1 SHA = gen2 SHA (compiler unchanged)
- existing tests still run (none skipped or deleted)

### 6. Human-review flags

Flag, do not paper over:

- HTTP status that the host derives from `"status":N` in JSON (`VireListen.StatusOf`) while native `rt_net_sendhttp` always emits `HTTP/1.1 200` for a successful `route` return
- TLS (no native TLS server)
- WebSocket (guest emit exists only as `tests/native/fixtures/gc-tagged-walk/rt-ws.vire`, not in production `compile-native.vire`)
- unread production Node/Go services
- nondeterministic bodies (timestamps, ids)
- auth tokens (`FCG_API_TOKEN` must never be printed; `/health` stays unauthenticated)

## Native capabilities (this HEAD)

| Capability | Native status | Evidence |
| --- | --- | --- |
| HTTP listen (loopback) | **Present** PE + ELF | `src/rt-net.vire`, `tools/native-net-windows.ps1`, `tools/native-elf-tcp.sh` |
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
| 1 | `GET /health` and `GET /api/health` JSON | HTTP, JSON | Both present | **This PR.** `guest-health.vire` + `tools/rebuild-health-diff.sh` |
| 2 | Other unauth JSON on `api/fcgcpa.vire` (`/info`, `/connect`) | HTTP, JSON | Present | Next. Same listen guest, larger contract |
| 3 | `/payments` and `/mine` 403 bodies | HTTP, JSON, **HTTP status from `"status"`** | Body yes; native HTTP code stays 200 | Flag until native sendhttp maps `StatusOf` |
| 4 | `GET /chain`, `POST /block` | HTTP, JSON, `data/` files, `hash` | All present on native | After 2–3. Needs chain fixtures, not prod data |
| 5 | Host `FCG_API_TOKEN` on non-health paths | HTTP, constant-time header compare | Host `VireListen`; native guest has no token gate | Human review: port header check or keep host |
| 6 | Static landing / Couch Potato HTML emit | `write` of strings | Present | Interpreter already; native write prove is separate from HTTP |
| 7 | Node landing/API from `fcgcpa-prod` | HTTP, JSON, likely TLS, likely more routes | TLS missing; prod unread here | Blocked on recorded contracts from a local-only read |
| 8 | Go `api-go`, `cpa-go` | unknown until source | unknown | Blocked; unread |
| 9 | Loopback Postgres/Redis if those Go services use them | DB client, no TLS | Clients exist; not wired to FCG | After a recorded SQL/RESP contract |
| 10 | WebSocket chat / live | WS, maybe TLS | Fixture only | Blocked |
| 11 | Public TLS terminator | TLS | Missing | Reverse proxy in front of loopback, or a later TLS lane. Not a stub. |
| 12 | Skinned browser, Proof of Rot miner, shop, OAuth clients | unknown | none | Blocked on missing source (PR39) |

### Rank 1 contract (proven on Linux ELF in this lane)

Recorded in `tests/rebuild/contracts/fcg-health.json`:

- `GET /health` → 200, `Content-Type: application/json` (no charset; Go `writeJSON` in fcgbds-go `server.go`), `Connection: close`, `nosniff`, `Cache-Control: no-store`, body `{"ok":true,"service":"fcgcpa","payments":false}`
- `GET /api/health` → same
- `GET /nope` → body `{"ok":false,"status":404,"error":"not found"}`. **HTTP status is a human-review flag:** host `StatusOf` yields 404; native route responses are 200. The harness treats HTTP 200 + that body as a documented native gap, not as a silent pass against HTTP 404.

### What this PR does not prove

- Byte-identical Node handler vs Vire (private repo unread)
- Remaining `api/fcgcpa.vire` routes
- TLS, WebSocket, DNS, public bind
- Go microservices
- Payments on, mining network, testnet
- Compiler self-host identity is re-proved after `parkNet` `txt_hdrs` (JSON Content-Type without charset). `compile-native.vire` was not edited.

## Commands

```text
bash tools/rebuild-health-diff.sh
bash tools/native-elf-selfhost.sh
dotnet test tests/Vire.Tests/Vire.Tests.csproj -c Release --nologo
```

Windows PE health remains `tools/native-net-windows.ps1` (needs gen1 PE). This Linux lane does not replace that proof.
