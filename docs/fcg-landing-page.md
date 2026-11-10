# Rewrite unit. landing-page/

Inventory SHA `5cc110206f8f42ee25c127f2bfbe0f8bcd6067f4`. This agent did not re-open the files.

## Source paths

- `landing-page/` Next.js 16.3.6, React 19, Tailwind 4, ethers, WebAuthn browser, pusher-js, pg.
- App router under `landing-page/src/app/`. Named routes include join, legal, subscription, bot-defense-system, mscb, waitlist-admin, whitepaper.
- Shopify widget `landing-page/src/components/ShopifyBuy.tsx`.
- Next routes `landing-page/src/app/api/shopify/config/route.ts`, `collection/route.ts`, `admin-collection/route.ts`.
- Tests in `landing-page/package.json` `test`. CI `.github/workflows/landing-node.yml` runs a cookie test plus `npm run build` on Node 24.
- Nested `*/.github/workflows/npm-security.yml` files are inert until those folders are their own GitHub repos.

Public site name in the inventory is `forevercouchgang.space`.

## Behavior to preserve

Public marketing and join flows. Shopify buy widget talks to hosted shop `https://shop.forevercouchgang.space`. Waitlist admin. Legal pages. Cookie behavior covered by the CI cookie test.

Do not port Hydrogen. There is no Hydrogen repo here.

Vire `sites/landing/site.vire` is not this app. Do not ship that emitter as the landing rewrite.

## Acceptance tests

1. Input `GET /` of the built site. Expected 200 HTML for the home route. Exact markup needs a token that can open `landing-page/src/app`.
2. Input the CI cookie test command from `landing-node.yml`. Expected pass on the Node app. A Vire port must match that cookie contract.
3. Input Shopify config route with tokens unset. Expected no secret leak. Fail closed or empty public config.
4. Input waitlist Google OAuth callback with blank client id. Expected skip, not a 500 stack trace.

Payments on subscription pages stay off.

## Vire capability

Needs HTML, CSS, and JS emit plus browser WebAuthn and wallet. Needs a Next-class SSR or a static export that still hits the API. ML3 HTML emit in VIR is not Next 16. Native PE does not run React 19.

Friday. Not feasible as a VIR React runtime. A static export of a few pages behind Vire `listen` would still be wrapping a Node build unless the pages are rewritten in VIR. Rewriting the whole App Router in VIR in the remaining days is not a real plan.

## Security

Storefront token in env, not git. Admin collection route needs admin token. Webhook secret on merch grant lives in `api/`. XSS in MDX or user waitlist content. Cookie flags from the cookie test.

## Size and order

After API health. Parallel with other Next apps only after a VIR page pattern exists. Not on Friday critical path.
