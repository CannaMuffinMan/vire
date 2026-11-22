# Rewrite unit. fcgbds-core, dashboard, and twins

Inventory SHA `5cc110206f8f42ee25c127f2bfbe0f8bcd6067f4`. This agent did not re-open the files.

## Source paths

- `fcgbds-core/`. Express on `PORT` or 3040. Daily "blockchain" event in `runtime.ts` is an audit-log hash. It does not call `FCGCNode`. Must not `prisma migrate deploy`. Selected when `FCGBDS_CORE_BASE_URL` is set.
- `fcgbds-dashboard/`. Next 16.3.6, React 18, Three.js, Playwright `test:tilt`.
- `fcgbds-go/`, `fcgbds-dashboard-go/`, `fcgbds-middleware/`.
- Public OSS `github.com/cannamuffinman/fcgbds` 404. Product source is these folders.

## Behavior to preserve

BDS HTTP service and dashboard. Audit-log hash is not the product chain. Bridge into Node at `/api/fcgbds/bridge`.

Do not run Prisma migrate from this unit.

## Acceptance tests

1. Input `GET` health on port 3040 or `PORT`. Expected 200 from the core process. Re-read the exact path when the repo is readable.
2. Input the daily hash job with a fixed clock in a later harness. Expected a stable hash for stable events. Do not talk to `FCGCNode`.
3. Input `npx prisma migrate deploy` from this unit. Expected the rewrite never does that.
4. Input Playwright `test:tilt` on the dashboard. Expected pass on the Node app. A VIR WebGL port is out of Friday scope.

## Vire capability

Second HTTP service plus WebGL. Out of Friday scope. Three.js is not a VIR builtin.

## Security

Unauthenticated Node `POST /api/admin/bds/test` must not be cloned. Master password on nearby upload. Treat BDS ingest as hostile input.

## Size and order

After API health. Go twins are stranglers. Wrapping them is not a Vire build.
