# Forever Couch Gang landing port (fcgcpa-prod main)

Read-only inventory of https://github.com/CannaMuffinMan/fcgcpa-prod (`main`). No secrets were copied. Nothing was pushed to that repository.

## What the public site is

`forevercouchgang.space` is not one static tree. It is three layers:

1. **Next.js app** in `landing-page/` (`src/app/**/page.tsx`, `layout.tsx`, `globals.css`, middleware). Routes are React server components. SOP, partners, waitlist-admin, gift-admin, and similar paths are application screens, not files.
2. **Go process** in `landing-go/` (`pages.go`, `routes.go`, `dist.go`). Fixture HTML is concatenated in Go (`homePage`, `doc(...)`, `shellCSS`). `LANDING_DIST` serves an exported Next tree with `http.ServeContent` (ETag / Last-Modified from the OS). Cookie gates, `/api` proxy, and `data_held` JSON are **not** static.
3. **Public files** in `landing-page/public/` (robots, svgs, pngs, live-popup.json, ads.txt, verification HTML, large watermark). These are bytes on disk.

## Static vs server-rendered

| Kind | Where | Vire port |
|---|---|---|
| Public robots/svg/json/md | `landing-page/public/*` | Vendored under `sites/landing/site/` when small and secret-free |
| Home HTML | Go `homePage` / Next `src/app/page.tsx` | Static snapshot in `sites/landing/site/index.html` (from in-tree `sites/landing/site.vire`) |
| Legal / plans / promo HTML | Go `doc(...)` templates | Not vendored (server-rendered copy in Go; Next still owns the live pages) |
| SOP, auth cookies, API proxy | `landing-go` + Next `src/app/api` | Out of scope for this lane |
| Held routes (`{"reason":"data_held"}`) | `landing-go/routes.go` | Not static |
| `{{year}}` / `{{payments}}` | Tiny Vire expand on `text/html` | Host substitutes `2026` and `off` |

## What was vendored

Under `sites/landing/site/` only:

- `index.html`, `site.css` (public home snapshot, no keys)
- `robots.txt`, `whitepaper.md`, `live-popup.json`, `file.svg`

Skipped: AdSense `ads.txt`, Google site-verification HTML, 7MB watermark, PNG/JPEG brand art, SOP, `.env`, API code.

## Vire serving rules

- Declared root: `site` or a relative path ending in `/site` (`VIRE_SITE_ROOT`). Capability: `VIRE_SITE_CAP=1` (default on).
- GET/HEAD only for files. Other methods on an existing file → 405 HTML.
- `..`, `%`, `\`, NUL, `:` → 404. Encoded `%2e%2e` is refused before it becomes `..`.
- Allowlisted MIME, `ETag` (SHA-256 of served bytes on the host), `Last-Modified`, `Cache-Control: public, max-age=60`, 304 on `If-None-Match` / `If-Modified-Since`.
- Native PE: hooking `rt_net_client`'s `fn_route` call crashed gen2 compile-native and GET `/health`. `emitSiteRuntime` is currently a no-op so gen1=gen2 and JSON health stay intact. Host `VireSite` is the proven static path.

## Proof

Windows job `.github/workflows/native-site.yml` copies `sites/landing/site` to `site/`, serves with the host listener and a gen1-compiled `guest-landing.vire`, and prints `sha256` of every GET body against the files on disk. Traversal requests must be 404.
