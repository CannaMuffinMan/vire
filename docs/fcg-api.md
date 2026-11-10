# Rewrite unit. api/

Pinned product SHA in the inventory is `5cc110206f8f42ee25c127f2bfbe0f8bcd6067f4`. This agent did not re-open the files.

## Source paths the inventory read

- `api/src/index.ts`. Listen `http.createServer` on `0.0.0.0` and `PORT`, default 4001. No `https.createServer`. Mounts including admin BDS. Unauthenticated `POST /api/admin/bds/test` near line 13530 returns `{ ok: true }`.
- `api/prisma/schema.prisma`. 68 Prisma models. Prisma 5.22 / `@prisma/client` 5.22.0.
- `api/src/platforms/oauthManager.ts`
- `api/src/routes/merchProGrantRoutes.ts`
- PoR HTTP `porRoutes.ts`. Posts `${FCGBC_RPC_URL}/por/mine`.
- `blockchainRoutes.ts`. Posts `/contract/.../register-wallet`.
- Governance outbox posts `/governance/anchor`.
- `api/src/blockchain/node.js` copied to `dist` by `copy-blockchain-runtime.js`. `tsconfig` excludes `src/blockchain/*.js`. In-memory SHA-256 chain. Genesis `Date.now()`. Mine to two leading zeros. Routes `/mine` and `/mine-engagement`, not `/por/mine`.
- `wallet.js` signs SHA-256 of pubkey plus data. PoR verifies with `ethers.verifyMessage`. Different systems.
- `fcgbcChainDb.js` has no caller.
- Schedulers in-process. `BackupScheduler`, `AggregationScheduler`, `SecurityMonitoringScheduler`, BDS ingest, governance outbox.
- `api/railway.toml` does not set `PAYMENTS_ENABLED`.
- `api/.env.example` for env names only. Do not copy values.
- Tests. Many `test:*` scripts. CI `.github/workflows/api-only-build.yml` is a thin subset.

Declared packages include jsonwebtoken, bcrypt, `@simplewebauthn/server`, otplib, siwe, ethers, stripe 22.1.0, ioredis, pg, ws, helmet, cors, multer, twilio, `@aws-sdk/client-s3`, `@noble/secp256k1`. Node 22. Express 5.2.1.

## Behavior to preserve

- Health. `GET /health` and `GET /api/health` succeed without auth.
- Version and capabilities. `GET /api/version`, `GET /api/capabilities`, `GET /api/csrf-token`.
- Auth. JWT cookie `authToken` or Bearer via `authMiddleware`. Email, passkey, SIWE, wallet, TOTP, Twilio phone. Dev `x-dev-token` / master password. Owner `/api/auth/owner`. Google waitlist OAuth is separate. Google is omitted from `/api/oauth/providers`.
- OAuth. Ten platforms in `oauthManager.ts`. Blank id or secret skips that provider.
- Billing fail-closed. Payments run only when `PAYMENTS_ENABLED` is exactly `true` and `STRIPE_SECRET_KEY` is set. Caps 1000 and 9000 cents. `FORCE_BILLING_DISABLED` / `BILLING_DISABLED` plus `BILLING_AUTO_ENABLE_AT` default 2026-04-01 in source. Vire keeps payments off.
- WebSocket. Only `Ws.Server` path `/ws/kick`. Token query plus origin check.
- Bot defense, waitlist, merch Shopify webhook, `/api/por`, `/api/blockchain`, `/api/couchy`, `/api/fcgbds/bridge`, `/api/dev`.
- OFAC fail-closed. No child accounts. No secrets printed.

Do not preserve the unauthenticated `POST /api/admin/bds/test` success. Close it. Nearby BDS upload already checks a master password.

Do not copy chain data. Do not implement `/por/mine`, `/contract/.../register-wallet`, or `/governance/anchor` until the operator names the live process. Those three paths have no in-tree handler on the JS node or on `fcgbc-go`.

## Acceptance tests a Vire build must pass

Payments stay disabled in every case.

1. Input `GET /health` to `127.0.0.1` on the listen port. Expected HTTP 200 and a JSON body the Node health handler already returns. Re-read the body on a token that can open `api/src/index.ts`. Until then, assert 200 and a body that parses as JSON with an `ok` or equivalent healthy flag if the inventory body used one. Do not guess extra fields.
2. Input `GET /api/health`. Expected same family as (1).
3. Input `GET /api/oauth/providers` with all OAuth env vars unset. Expected 200 and a map that omits providers with blank id or secret. Google waitlist stays off this map.
4. Input any `/api/billing/*` and `/api/payment` while `PAYMENTS_ENABLED` is unset or not `true`. Expected fail-closed. No Stripe network call.
5. Input `GET /ws/kick` without the token query. Expected non-101. With a valid token and allowed origin, expected 101 only after native WebSocket exists. Until then this case is blocked, not skipped as pass.
6. Input `POST /api/admin/bds/test` with no auth. Expected 401 or 403 in the Vire rewrite. The Node gap returning `{ ok: true }` is a defect.
7. Input CSRF. Routes that use `requireBrowserCsrf` reject a missing token. Purchase, compliance, FCGBDS bridge, interactions, rewards, and payment mount before global CSRF in Node. Payment then uses `requireBrowserCsrf`. Vire must not widen that hole.
8. Listen port default 4001 when `PORT` is unset. Bind not on reserved ports listed in `NATIVE-COMPILER.md`.

Unit files for these cases live under `api/` tests and are not re-listed here because this token could not open them. Re-pin the test file paths before coding.

## Vire capability

| Need | Today | File refs |
| --- | --- | --- |
| Interpreter HTTP | Yes | `VireListen.cs` |
| Native HTTP | No on this branch | PR 47 `src/rt-net.vire` |
| JSON | Interpreter yes, native guest HTTP JSON unproven | `Vire.cs`, `deps/jsonkit/lib.vire` |
| Postgres | No | |
| Redis | No | |
| JWT HMAC | No | |
| WebSocket | No | |
| bcrypt / WebAuthn / SIWE | No | |
| SHA-256 | Yes | `hash`, `emitSha` |
| File IO | Yes, not a substitute for Prisma | |
| Stripe | Must stay unused | |

This unit needs native PE plus Postgres, Redis, JWT, WS, and crypto. Interpreter-only is a demo.

## Security

- Fail closed on payments, OFAC, and missing OAuth secrets.
- Admin tokens named `BRIDGE_ADMIN_TOKEN`, `ADMIN_DEPLOYMENT_TOKEN`, `ADMIN_SECRET`. Names only.
- Close `bds/test`.
- No public bind without `VIRE_BIND=public` and a 16+ character token in Vire.
- Edge TLS. Do not claim in-process TLS.
- Threat. Unauthenticated admin, CSRF mount order, webhook spoof without `SHOPIFY_WEBHOOK_SECRET`, JWT cookie theft, Stripe enable by env mistake.

## Size and order

Largest product process. Last to start. Do not begin before native `/health`. Friday full port is infeasible. A health clone after PR 47 is the only honest near-term slice.

Depends on proven native listen. `api-go` is optional and is not the write path.
