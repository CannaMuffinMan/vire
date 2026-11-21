# dev-portal-go blocked (no stubs)

- cookie page gate 307 `/login`
- JWT session POST/GET/DELETE `/api/auth/session`
- `/fcg-api/` reverse-proxy
- static files when `DEV_PORTAL_DIST` exists
- GET `/api/auth/session` 503 `not_configured` (needs auth cookie present)
- static 405 Allow GET, HEAD (only after dist exists)
