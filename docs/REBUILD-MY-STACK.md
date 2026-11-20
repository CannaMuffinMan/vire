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

`guest-health.vire` serves `GET /health`, `GET /api/health`, `GET /info`, `GET /connect`. Native `rt_net_statusof` maps JSON `"status":N` to the HTTP status line the same way host `VireListen.StatusOf` does.

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

## Native capabilities (this HEAD)

| Capability | Native status | Evidence |
| --- | --- | --- |
| HTTP listen (loopback) | **Present** PE + ELF | `src/rt-net.vire`, `tools/native-net-windows.ps1`, `tools/native-elf-tcp.sh` |
| HTTP status from JSON `"status"` | **Present** | `rt_net_statusof`; harness `GET /nope` → 404 |
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
| 2 | Other unauth JSON on `api/fcgcpa.vire` (`/info`, `/connect`) | HTTP, JSON | Present | **This PR.** Same listen guest, extra contracts |
| 3 | `fcgbds-go` `GET /health` | HTTP, JSON | Present | **Next native proof.** Golden fields `ok`, `service: fcgbds-core`, `paymentsEnabled: false`. `ts` is now() — compare JSON fields, not exact bytes. Keep separate from Node/`api/fcgcpa.vire` health. |
| 3b | `api/fcgcpa.vire` `/payments` and `/mine` 403 | HTTP, JSON, status from `"status"` | Mapping present | After unauth Go health GETs, or in parallel on the same guest |
| 4 | `GET /chain`, `POST /block` | HTTP, JSON, `data/` files, `hash` | All present on native | After 3. Needs chain fixtures, not prod data |
| 5 | Host `FCG_API_TOKEN` on non-health paths | HTTP, constant-time header compare | Host `VireListen`; native guest has no token gate | Human review: port header check or keep host |
| 6 | Static landing / Couch Potato HTML emit | `write` of strings | Present | Interpreter already; native write prove is separate from HTTP |
| 7 | Node landing/API from `fcgcpa-prod` | HTTP, JSON, likely TLS, likely more routes | TLS missing; prod unread here | Blocked on recorded contracts from a local-only read |
| 8 | Go `api-go`, `cpa-go` | unknown until source | unknown | Blocked; unread |
| 9 | Loopback Postgres/Redis if those Go services use them | DB client, no TLS | Clients exist; not wired to FCG | After a recorded SQL/RESP contract |
| 10 | WebSocket chat / live | WS, maybe TLS | Fixture only | Blocked |
| 11 | Public TLS terminator | TLS | Missing | Reverse proxy in front of loopback, or a later TLS lane. Not a stub. |
| 12 | Skinned browser, Proof of Rot miner, shop, OAuth clients | unknown | none | Blocked on missing source (PR39) |

### Rank 1–2 contracts (proven on Linux ELF in this lane)

Recorded in `tests/rebuild/contracts/`:

- `GET /health` → 200, `Content-Type: application/json` (no charset; Go `writeJSON` in fcgbds-go `server.go`), `Connection: close`, `nosniff`, `Cache-Control: no-store`, body `{"ok":true,"service":"fcgcpa","payments":false}`
- `GET /api/health` → same
- `GET /info` → 200, same headers, body from `api/fcgcpa.vire` `/info`
- `GET /connect` → 200, same headers, body `{"twitch":"https://www.twitch.tv","youtube":"https://www.youtube.com"}`
- `GET /nope` → HTTP **404**, body `{"ok":false,"status":404,"error":"not found"}` (host `StatusOf` and native `rt_net_statusof`)

### What this PR does not prove

- Byte-identical Node handler vs Vire (private repo unread)
- Remaining `api/fcgcpa.vire` routes (`/payments`, `/mine`, `/chain`, `/block`)
- Go sidecars (`fcgbds-go` `/health`, `fcgbc-go` `/pending-transactions`, `cpa-go` `/health` text/plain, `rpc-portal-go` `/api/health`, `api-go` `/healthz`). Those contracts are not this PR. `api-go` `/api/health` is not the Node/`fcgcpa` health body.
- TLS, WebSocket, DNS, public bind
- Go microservices
- Payments on, mining network, testnet
- Compiler changes (`compile-native.vire` / emitters were not edited; blob+pins+fixes for `rt_net_statusof` only)
- Compiler self-host identity is re-proved after `parkNet` `txt_hdrs` (JSON Content-Type without charset). `compile-native.vire` was not edited.

## Commands

```text
bash tools/rebuild-health-diff.sh
dotnet test tests/Vire.Tests/Vire.Tests.csproj -c Release --nologo
```

Windows PE health remains `tools/native-net-windows.ps1` (needs gen1 PE). This Linux lane does not replace that proof.
