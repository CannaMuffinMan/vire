# FCG source access and missing pieces

## Repos this token can see

| Target | This run | Kind |
| --- | --- | --- |
| `CannaMuffinMan/vire` | Readable. Default branch `native-compiler`. | Compiler |
| `CannaMuffinMan/fcgcpa-prod` | HTTP 404 on `gh api` as user `cursor`. | Product source. Inventory SHA still `5cc110206f8f42ee25c127f2bfbe0f8bcd6067f4`. |
| Other `CannaMuffinMan` repos | `gh repo list` returned only `vire`. | Unknown versus this token |

The earlier inventory agent could `gh repo view` `fcgcpa-prod`. This agent cannot. Any later rewrite must re-open that repo with a token that lists it, then re-pin the SHA.

## Present in git according to the inventory SHA

These trees were measured at `5cc110206f8f42ee25c127f2bfbe0f8bcd6067f4`. This agent did not re-list them.

- `api/`
- `api-go/`
- `landing-page/`
- `couch-potato-app/`
- `fcgbds-core/`, `fcgbds-dashboard/`, `fcgbds-middleware/`, `fcgbds-go/`, `fcgbds-dashboard-go/`
- `rpc-portal/`, `rpc-portal-go/`
- `dev-portal/`, `dev-portal-go/`
- `fcgbc-go/`
- `landing-go/`, `cpa-go/`, `edge-go/`, `worker-go/`
- `couchy/`
- `shared/couchy/`
- `loadtest/`, `tools/load-test/`, `scripts/`

## Not locatable as source

| Piece | What exists | What is missing | Access needed |
| --- | --- | --- | --- |
| Shopify shop | Widget `landing-page/src/components/ShopifyBuy.tsx` and Next routes `landing-page/src/app/api/shopify/{config,collection,admin-collection}/route.ts`. Grant routes `api/src/routes/merchProGrantRoutes.ts`. Hosted URL named `https://shop.forevercouchgang.space`. | Theme, Hydrogen app, Admin app repo. Tokens not in git. Env names `SHOPIFY_DOMAIN` / `SHOPIFY_STORE_URL`, `SHOPIFY_STOREFRONT_TOKEN`, optional `SHOPIFY_COLLECTION_ID`, admin token, `SHOPIFY_WEBHOOK_SECRET`. | Shopify admin plus a theme repo if it exists outside this git. |
| Skinned browser / WebView2 | Vite app `couch-potato-app/`. Tauri `src-tauri/Cargo.toml` only. | `tauri.conf.json`, Rust sources, Chromium fork, WebView2 shell. No Chrome extension. | Desk disk or a private desktop repo. Historical remotes named in inventory 404 to that token. |
| Proof of Rot client | HTTP `api/src` PoR routes. CPA `proofOfRot.ts` named. JS node and Go node disagree. | A dedicated miner UI repo. In-tree handlers for `POST /por/mine`, `/contract/.../register-wallet`, and `/governance/anchor` are absent. Live `FCGBC_RPC_URL` process is unknown from git. | Operator to name the live RPC process. Do not copy testnet. |
| OAuth clients | Registry `api/src/platforms/oauthManager.ts`. Blank id/secret skips the provider. | Client ids and secrets. They are host env, not a second repo. Names `GOOGLE_*`, `X_*`/`TWITTER_*`, `YOUTUBE_*`, `TWITCH_*`, `KICK_*`, `DISCORD_*`, `REDDIT_*`, `INSTAGRAM_*`, `TIKTOK_*`, `META_*`. `OAUTH_GITHUB_*` in `api/.env.example` unused by routes. | Operator env. Never copy values into Vire. |
| OBS / StreamStuff | `couchy/couchy-brain/STREAMSTUFF_MAP.md` points at local `PRODONLY/StreamStuff`. | Overlay source. Not in git. | Desk path or a private repo. Out of this program. |
| Solidity | Zero `.sol` files. No `hardhat.config.js`. `seedProtectedFiles.ts` still names old Hardhat paths. | Contract source. | Separate repo or archive. |
| `worker-go` job bodies | `worker-go/` prints skeleton and exits 0. | Real job implementations. Product jobs live in the Node API process. | Node `api/` schedulers, not Go. |
| `signer/` | `api/docker-compose.yml` builds `./signer`. | Directory absent. | Unknown. |
| CPA `apps/api` | CPA compose builds it. | Directory absent. Product schema is API Prisma 5. | Do not invent a second API. |
| Production `.env` and Railway live values | Env names in source. | Values. Unread on purpose. | Never required for this map. |
| `github.com/cannamuffinman/fcgbds` | 404. In-tree FCGBDS is the product. | Public OSS link. | None. Use in-tree paths. |
| Historical remotes | `CannaMuffinMan/FCGCPAPRODONLY`, `Forever-Couch-Gang-LLC/FCGCPA`, `forevercouchgang/PRODONLY` | 404 to the inventory token. Couchy README says FCGCPAPRODONLY is gone. | Treat as gone unless the operator grants another remote. |

## Wrong to invent

- A Chromium skinned browser that is not in git
- A second Proof of Rot miner UI
- A Shopify Hydrogen app
- Proof of reserve. This PoR is Proof of Rot.
- Live Railway as current source of truth
