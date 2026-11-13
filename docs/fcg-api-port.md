# FCG API port (Node `fcgcpa-prod` → Vire)

Source: private `CannaMuffinMan/fcgcpa-prod` branch `main` (read-only; no secrets, no `.env` values). Node lives in `api/src/` (Express + Prisma + Redis). Vire listen is `define route with method, path, body` (no request headers on host or gen1 PE). Payments stay **off**.

Guest primitives used: `listen`, loopback `connect`/`send`/`recv`/`close` (PR #64, landed). Postgres v3 (PR #65), UTC `unix` (PR #66), RESP library `src/rt-redis.vire` (PR #67), and `ws_listen` (PR #68) were **not** copied; this lane implements a small RESP2 client in `api/redis-cmd.vire` and treats PG/WS/`unix` as residuals until those PRs land on `native-compiler`.

`src/rt-crypto.vire` / `src/rt-kdf.vire` already expose `jwt_hs256_sign` and `bcrypt_verify`. They are **not** called from the listen guest here: host `bcrypt_verify` of the published cost-4 vector takes ~60s, and `Vire.cs` `Budget.ForRequest` kills a listen route after **5 seconds** (`request ran too long` → HTTP 503 `busy`). This lane does not raise that deadline or any cap. Auth login/register stay residual until a faster native KDF is used from listen without changing those limits.

Entry: `fcg-api.vire` (repo root, so `use` can load `src/` + `api/`). Routes: `api/fcg-routes.vire`. Phase-0 chain listener without Redis remains `api/fcgcpa.vire`.

CI fake JWT signing string is `fcg-ci-jwt-not-secret`. CI bcrypt vector is the published `$2b$04$......................` password=`password` digest (not a production hash).

## Auth model (Node)

- User JWT: HS256, `JWT_SECRET`, cookie `authToken` or `Authorization: Bearer`. Payload `userId`. Middleware: `api/src/middleware/userAuth.ts`.
- Vire residual: `route` does not receive headers, so Bearer/cookie cannot be read. Login/register are POST bodies. Protected GETs stay residual until listen grows a fourth argument (do not widen sandbox here).
- Payments JWT: same HS256 plus CSRF cookie on browser POSTs (`paymentRoutes.ts`). Residual (payments off).
- Honeypot: `POST /api/login` is **not** the real login; Node returns 404 JSON (`honeypot.ts`). Ported.

## Database (Node Prisma)

Hot public count: `SELECT COUNT(*)::int AS count FROM "WaitlistEntry"` (`api/src/db/fastReads.js` `readWaitlistCount`, cache key `waitlist-count` in process memory `publicCounterCache.js`, 15s). Redis is used for waitlist nonces (`waitlist:nonce:{addr}:{nonce}`), session vaults, Couchy pending binds (`couchy:community:fcgbc:pending:{uploadId}`), rate-limit prefixes, featured live (`creators:featured:live:{login}`).

Vire public count reads Redis bulk `waitlist:count` (CI copies the Postgres COUNT into that key). Direct PG simple-query is residual (binary startup + `send` is UTF-8 text; PR #65 not landed).

## Port status

`ported` = implemented in `api/fcg-routes.vire` and proven in `.github/workflows/fcg-api.yml`. `residual` = documented, not in the Vire listen guest.

### Ported (this PR)

| Method | Path | Auth | Store | Expected body (CI) | Status |
|---|---|---|---|---|---|
| GET | `/health` | public | none | `{"ok":true,"service":"fcgcpa","payments":false}` | ported |
| GET | `/api/health` | public | Node: shard+Redis health object. Vire: same compact health as `/health` | `{"ok":true,"service":"fcgcpa","payments":false}` | ported (shape residual vs Node `getHealthStatus`) |
| GET | `/api/health/redis` | public | Redis `PING` | `{"ok":true,"redis":"PONG","payments":false}` | ported |
| GET | `/info` | public | none | `{"service":"fcgcpa",...,"payments":false}` | ported |
| GET | `/api/info` | public | none | same as `/info` | ported |
| GET | `/connect` | public | none | `{"twitch":"https://www.twitch.tv","youtube":"https://www.youtube.com"}` | ported |
| GET | `/payments` | public | none | `{"ok":false,"status":403,"error":"payments are off","payments":false}` | ported |
| GET | `/api/payment/catalog` | public | Node: SKU env + Stripe price ids | same 403 payments-off body | ported (Node may 200 with items when SKU JSON set; Vire always off) |
| POST | `/api/payment/intent` | JWT+CSRF | Stripe | 403 payments-off | ported refusal |
| GET | `/api/capabilities` | public | env presence | all oauth/payments false | ported |
| GET | `/api/couchy/info` | public | none | Couchy info JSON (`backend` is `"local"` in Vire; Node uses `COUCHY_ASSIST_URL`) | ported |
| GET | `/api/waitlist/count` | public | Node: `"WaitlistEntry"` COUNT. Vire: Redis `waitlist:count` | `{"count":3,"max":null,"spotsLeft":null,"full":false,"registrationClosed":false}` | ported |
| POST | `/api/login` | honeypot | audit log in Node | `{"ok":false,"status":404,"error":"Endpoint not found"}` | ported |
| GET | `/mine` | public | none | mining refused | ported |

### Residual — payments / Stripe (must stay off)

Mounted in Node as `/api/payment` (`paymentRoutes.ts`) and billing webhook in `index.ts` / `stripeWebhook.ts`:

| Method | Path | Auth | Store |
|---|---|---|---|
| POST | `/api/payment/subscription/create` | JWT+CSRF+charge | Stripe + `"Subscription"` |
| POST | `/api/payment/subscription/cancel` | JWT+CSRF | Stripe |
| POST | `/api/payment/refund` | JWT+CSRF | Stripe |
| POST | `/api/payment/sms/send-verification` | JWT | Twilio |
| POST | `/api/payment/sms/verify-code` | JWT | Twilio |
| POST | `/api/payment/sms/send-notification` | JWT+admin | Twilio |
| POST | `/api/billing/webhook` | Stripe signature | Stripe + DB |
| POST | `/api/payment/webhook` | Stripe signature | alias of billing webhook |

### Residual — waitlist (`waitlistRoutes.ts`, mount `/api/waitlist`)

| Method | Path | Auth | Store |
|---|---|---|---|
| POST | `/api/waitlist/join` | wallet sig | `"WaitlistEntry"`, `"User"`, Redis nonce |
| GET | `/api/waitlist/google/authorize` | none | Google OAuth |
| GET | `/api/waitlist/google/callback` | OAuth | User + waitlist |
| GET | `/api/waitlist/admin/stats` | `Bearer DEV_PASSWORD` | waitlist counts |
| POST | `/api/waitlist/session/start` | | Redis session |
| POST | `/api/waitlist/session/:id/vault` | | Redis |
| GET | `/api/waitlist/session/:id/vault` | | Redis |
| GET | `/api/waitlist/mobile/authorize` | | OAuth |
| GET | `/api/waitlist/mobile/callback` | | OAuth |
| GET | `/api/waitlist/session/status/:id` | | Redis |
| POST | `/api/waitlist/check-registration` | | `"WaitlistEntry"` |

### Residual — Couchy (`routes/couchy.ts`, mount `/api/couchy`)

POST error-diagnosis, code-review, debug-help, documentation, best-practices, architecture (dev JWT). POST community, public-help, grok/chat/completions, community/fcgbc/upload, community/fcgbc/bind. GET knowledge-base*, GET status, GET/POST/PUT/DELETE preferences*. Redis pending bind keys; Prisma `userPreferences`, `waitlistEntry`, `User`.

### Residual — auth (`userAuth.ts`, User passwordHash)

| Method | Path | Auth | Store | Why residual |
|---|---|---|---|---|
| POST | `/api/auth/login` | public | `"User".passwordHash`, JWT HS256 cookie | Host bcrypt_verify cost 4 ~60s vs listen 5s request deadline; Bearer/cookie not on `route` |
| POST | `/api/auth/register` | public | `"User"` insert + bcrypt hash | same deadline; salt RNG residual |
| GET/PUT | protected user routes | JWT header | `"User"` | `route` has no headers |

### Residual — TOTP (`totpRoutes.ts`, mount `/api/auth/totp`)

POST setup, verify, validate, disable. GET status/:userId. Table `"User"` totp columns. AES wrapping residual.

### Residual — other Node routers (file → mount)

Exact verbs live in each file. None of these are in the Vire guest yet.

| File | Typical mount | Auth / store |
|---|---|---|
| `legacyRoutes.ts` | `/api/legacy` | JWT; compensation tables |
| `creatorsPublicRoutes.ts` | `/api/creators` | public; Redis `creators:featured:live:*` + Twitch HTTPS (guest has no TLS) |
| `walletRoutes.ts` | `/api/wallet` | JWT; `"User".walletAddress` |
| `profileRoutes.ts` | `/api/profile` | JWT; profile tables |
| `blockchainRoutes.ts` / `adminBlockchainRoutes.ts` | `/api/blockchain` | mix; chain DB |
| `porRoutes.ts` | `/api/por` | Proof of Rot |
| `rewardsRoutes.ts` | `/api/rewards` | JWT |
| `voting.ts` | `/api/voting` | JWT |
| `bugReportRoutes.ts` | `/api/bugs` | mixed |
| `chatBridgeRoutes.ts` | `/api/chat` | JWT |
| `complianceAdminRoutes.ts` | `/api/compliance` | admin token |
| `dataProductsRoutes.ts` | `/api/data` | API key |
| `devRoutes.ts` / `creatorDevRoutes.ts` | `/api/dev` | dev JWT |
| `defenseOwnerAuthRoutes.ts` | `/api/defense` | owner |
| `fcgbdsBridgeRoutes.ts` | `/api/fcgbds` | bridge |
| `governanceRoutes.ts` | `/api/governance` | JWT + ledger |
| `interactionTrackingRoutes.ts` | `/api/interactions` | JWT |
| `lumiaIntegrationRoutes.ts` | `/api/lumia` | |
| `merchProGrantRoutes.ts` | `/api/merch` | |
| `mscbBridgeControlRoutes.ts` / `mscbTabRoutes.ts` | `/api/mscb` | admin |
| `partnershipRoutes.ts` | `/api/partnership` | |
| `planGiftRoutes.ts` | `/api/plan-gift` | |
| `preregistrationRoutes.ts` | `/api/preregistration` | file + User |
| `proofDataRoutes.ts` | `/api/proof` | |
| `purchaseRoutes.ts` | `/api/purchase` | **Stripe residual** |
| `recoveryRoutes.ts` / `walletFileRecovery.ts` | `/api/recovery` | |
| `sopStatementRoutes.ts` | `/api/sop` | |
| `syntheticAuthBrokerRoutes.ts` | `/api/synthetic` | |
| `alphaTesters.ts` | `/api/alpha-testers` | |
| `apiKeyRoutes.ts` | `/api/keys` | API keys table |
| `b2bManagementRoutes.ts` | `/api/b2b` | |
| `platforms/oauthRoutes.ts` | `/api/oauth` | OAuth; TLS residual |
| `streamWall/routes.ts` | `/api/stream-wall` | |
| `index.ts` (~550KB) | remaining ad-hoc `app.get/post` | many; not duplicated here |

WebSocket `/ws/kick` (Node) waits on PR #68.

## CI proof

Throwaway Postgres + Redis on Ubuntu. Windows uses a loopback RESP2 PING/GET/SET fixture (test-only). Seed three `"WaitlistEntry"` rows and copy `COUNT(*)=3` into `waitlist:count`. Host interpreter must return the **Expected body** column. Packed `compile-native` of the listen guest must print `compiled`. The gen1 PE must answer those routes with the native-net request shape (`Host` on GET; POST adds `Content-Length`). Extra client headers empty the socket on this packed listener. Payments stay off. Caps unchanged.

FAIL_BEFORE host SHA: `9ea4561d12236f7f2f44858f137d7c948836df65` (`GET /api/waitlist/count` → 404 from `api/fcgcpa.vire` on that pin).

FAIL_BEFORE PE SHA: `3946d1c6c4f3fc12e4a486da600bba354ad60c64` (`src/rt-net.vire` at the native-compiler tip before `emitClientLeaf`). PASS_AFTER compiles the same guest with `emitClientLeaf` and requires the PE to answer the documented bodies with `Host` + `Connection: close`; a `crash rip=` line fails the job.
