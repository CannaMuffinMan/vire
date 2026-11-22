# Rewrite unit. couchy/ and shared/couchy/

Inventory SHA `5cc110206f8f42ee25c127f2bfbe0f8bcd6067f4`. This agent did not re-open the files.

## Source paths

- `couchy/` recovered assist, brain, MCP, voice, video, local router.
- `couchy/AGENTS.md` says this tree is not wired to deploy by itself.
- `couchy/couchy-brain/STREAMSTUFF_MAP.md` points at local `PRODONLY/StreamStuff`, not in git.
- `shared/couchy/` shared FAQ JSON. Tiny.
- Node API also exposes `/api/couchy`.

## Behavior to preserve

FAQ JSON. HTTP `/api/couchy` once re-read.

Do not start OBS. Do not port StreamStuff from a desk path this program cannot see. Local desk overlays are out of this program.

## Acceptance tests

1. Input read of shared FAQ JSON. Expected parse as JSON. No secrets.
2. Input Couchy deploy-from-this-tree. Expected not wired, matching `AGENTS.md`.
3. Input OBS launch from a Vire guest. Expected absent. Pass when the rewrite has no OBS spawn.

## Vire capability

MCP, voice, and video are far beyond current VIR. File JSON is in stdlib.

Friday. FAQ file clone only, and only after health, and only if the operator still wants it. Full Couchy is infeasible.

## Security

MCP tools can exfiltrate. Voice/video stacks pull native codecs. Keep this unit dark until a dedicated threat pass.

## Size and order

Last among product apps. After API. OBS never in this program.
