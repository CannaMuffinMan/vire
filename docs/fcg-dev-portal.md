# Rewrite unit. dev-portal/

Inventory SHA `5cc110206f8f42ee25c127f2bfbe0f8bcd6067f4`. This agent did not re-open the files.

## Source paths

- `dev-portal/` Next 16 developer portal.
- `dev-portal-go/webdist` contains built chunks. Those chunks are not the source of truth.
- `dev-portal-go/` strangler.

## Behavior to preserve

Developer docs and keys UI as in the Next source. Rebuild from source, not from `webdist`.

## Acceptance tests

1. Input `npm run build` on `dev-portal/` when the repo is readable. Expected success on Node. Not a Vire proof.
2. Input a page load of a route from `src/app` once listed. Expected 200. List the routes after re-read. Do not guess them here.

## Vire capability

Another Next app. Same gap as landing. Friday skip.

## Security

Dev tokens. Do not copy `ADMIN_DEPLOYMENT_TOKEN`. No public bind of a portal that mints keys until native token compare exists.

## Size and order

After landing pattern. Not Friday.
