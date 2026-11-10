# Rewrite unit. couch-potato-app/

Inventory SHA `5cc110206f8f42ee25c127f2bfbe0f8bcd6067f4`. This agent did not re-open the files.

## Source paths

- Vite SPA. Serve `dist`.
- Routes in `apps/web/src/App.tsx`.
- Root lists `@prisma/client` 7.10.0. No `schema.prisma` under this app. `prisma/package.json` is empty. Product schema is API Prisma 5.
- Desktop. `src-tauri/Cargo.toml` only. No `tauri.conf.json`. No Rust sources beyond that crate file.
- Proof of Rot client code named `proofOfRot.ts` in this tree. It disagrees with the JS node and with `fcgbc-go`.
- Vitest exists locally. Not the thin GitHub CI for the monorepo.

## Behavior to preserve

Browser CPA flows that call the Node API. Do not invent a local Prisma 7 schema.

Desktop shell is incomplete. Do not claim a Tauri or WebView2 product.

## Acceptance tests

1. Input the Vite production `index.html` plus hashed assets. Expected the App routes render without talking to a missing `apps/api`.
2. Input a PoR action that would hit `/por/mine`. Expected a documented error until the operator names the RPC. Do not mine. Do not copy testnet.
3. Input compose that builds `apps/api`. Expected that path remains absent. Do not add it in Vire.

## Vire capability

SPA plus optional Tauri. Not in Vire stdlib. `sites/cpa/app.vire` is the wrong app.

Friday. Not feasible as a full Vite plus desktop shell in VIR.

## Security

Wallet signing in the browser. Treat PoR messages as distinct from `ethers.verifyMessage` on the API. No child accounts. Do not enable payments.

## Size and order

After API. After a VIR SPA pattern. Desktop is a missing-source item in `docs/fcg-access.md`.
