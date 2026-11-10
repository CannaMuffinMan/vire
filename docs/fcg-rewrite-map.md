# How to use the FCG rewrite map

You are rebuilding Forever Couch Gang in Vire. You are not wrapping Node, Go, .NET, npm, or Chromium. This folder is the specification. It is not the product.

## What this folder is

Each `docs/fcg-*.md` file is one rewrite unit or one shared fact sheet. Read `docs/fcg-vire-capabilities.md` first. Then read the unit you will compile. Then follow `docs/fcg-program-plan.md` only after the operator says to execute.

This map does not authorize implementation. Native listen, TLS, HTTP, JSON, files, and a proven `GET /health` guest must exist before any FCG rewrite starts.

## What this agent could and could not read

This agent confirmed Vire at commit `7c7c8ea3dcc4030ba8714fc2330d30b67f8d6867` on branch `native-compiler`. Native PE IAT on that commit is `kernel32.dll` only. Native guests have no `json`, `parse`, or `listen` in `builtinArity`. Draft PR 47 head measured later in this run is `42ef1a5ce1be815d1b91f097f837885cceeba4ad`. That PR is not merged and is not proven.

This agent ran `gh api repos/CannaMuffinMan/fcgcpa-prod/commits/main` as GitHub user `cursor` on 2026-11-10 and received HTTP 404. `gh repo list CannaMuffinMan` returned only public `vire`. The GitHub MCP namespace was in error. This run did not clone `fcgcpa-prod`.

FCG product paths, ports, and tests below are cited from the attached inventory that measured `fcgcpa-prod` `main` at SHA `5cc110206f8f42ee25c127f2bfbe0f8bcd6067f4` on 2026-11-10. Treat those cites as second-hand until a token that can read the private repo re-opens the files. Do not invent extra routes.

## Hard rules for every later rewrite

- Docs in this PR only. No product code here.
- No FCGBC testnet data in Vire.
- Payments stay disabled. `PAYMENTS_ENABLED` is never `true` in Vire.
- No secrets from `fcgcpa-prod`. Env names only.
- Wrapping Go, .NET, npm, or Chromium is not "built by Vire".
- C# `VireListen.cs` is the interpreter host. It does not count as a native PE listener.
- Do not merge this draft until the operator says so. Do not push `main` or `native-compiler`. Do not deploy.

## Read order

1. `docs/fcg-vire-capabilities.md`
2. `docs/fcg-access.md`
3. `docs/fcg-api.md`
4. `docs/fcg-api-go.md`
5. `docs/fcg-landing-page.md`
6. `docs/fcg-couch-potato-app.md`
7. `docs/fcg-fcgbds.md`
8. `docs/fcg-rpc-portal.md`
9. `docs/fcg-dev-portal.md`
10. `docs/fcg-fcgbc.md`
11. `docs/fcg-sidecars.md`
12. `docs/fcg-couchy.md`
13. `docs/fcg-program-plan.md` when the operator starts execution

## Friday 2026-11-13 verdict

The whole FCG stack as native Vire PE by Friday Eastern is not feasible. Measured product source is on the order of 230000 lines of TypeScript, JavaScript, and Go across more than 20 trees. Native Vire on this branch has file IO, SHA-256 `hash`, lists, maps, and text. Interpreter `listen`, `json`, and `parse` exist only on the C# host. There are no native PE sockets on `native-compiler`. There is no native JSON, Postgres wire, Redis RESP, WebSocket, JWT HMAC, or in-process TLS. PR 47 adds a gated `ws2_32` HTTP/1.1 plus JSON lane and is unproven. Compiling Next 16, Prisma, Stripe, and ten OAuth clients as VIR in the remaining days is not a real plan.

The honest Friday ceiling is a native `/health` guest after PR 47 is proven, plus this specification. Anything larger is a later program.

## Critical path after this PR

1. Keep Vire self-host gates. Do not raise the 32 MB arena, the 100000 list cap, or the 5 million step cap as the way to ship FCG.
2. Prove native HTTP/1.1 `GET /health` from a gen1-compiled guest. PR 47 is the candidate. C# `listen` is not the proof.
3. Stop. Re-estimate. Do not start Prisma, Stripe, OAuth, Next, or chain ports on hope.
4. If and only if that health guest holds, clone Node `GET /health` and `GET /api/health` contracts from `api/` with payments off.
5. Frontends, BDS, portals, Couchy, and chain wait behind that gate.

## Top five missing Vire capabilities

Ranked by what blocks FCG first.

1. Native PE TCP listen and HTTP/1.1. Interpreter only in `VireListen.cs`. Native candidate is unmerged PR 47.
2. Native `json` and `parse`. Present on the C# host only on this branch. Prisma-class Postgres is a further gap. 68 models live in `api/prisma/schema.prisma` per the inventory.
3. Redis RESP plus process timers that today run inside the Node API.
4. WebSocket RFC6455. Product has `Ws.Server` on `/ws/kick` only.
5. JWT HMAC, cookie `authToken`, CSRF, WebAuthn, SIWE, and TLS at the edge or in-process. Native PE IAT on this branch has no crypto beyond SHA-256 `hash` in `src/rt-more.vire` `emitSha`. Host `seal` is AES-256-GCM in `VireSeal.cs` and is not native TLS.
