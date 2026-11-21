# Rebuild my stack

Lane status for porting remaining Go services onto native Vire. Caps stay arena 32MB / list 100000 / steps 5M.

| Primitives native now | Unblocks (service routes not in this lane) |
|---|---|
| SHA-256 (`hash` / `digest` via `rt_sha256`) | Already on `cursor/fcgbc-native-port-1a66` (PR #98) |
| HMAC-SHA256 (`hmac`, RFC 4231 1–7 including 131-byte keys) | Session cookies that sign, CPA/dev-portal tokens that MAC |
| JWT HS256 sign/verify (compact JWS; `alg` must be HS256; `exp`/`nbf` only with a caller clock) | `cpa-go`, `dev-portal-go`, `api-go` auth |
| Cookie parse (`Cookie` request header, RFC 6265 §5.4, first-wins) and `Set-Cookie` emit (Path, HttpOnly, Secure, SameSite, Max-Age; CR/LF/`;` refused) | `cpa-go`, `landing-go`, `rpc-portal-go` cookie sessions |
| PBKDF2-HMAC-SHA256 (`pbkdf2_sha256_tab` / `fcg_password_*`, RFC 8018; RFC 7914 §11 c=1 and c=80000) | Password login on `cpa-go`, `dev-portal-go`, `api-go`. Caps unchanged (arena 32MB / list 100000 / steps 5M / while 1M). |

Still later: AES-GCM, reverse-proxy, Postgres. This lane does not port `tests/rebuild/guests/*` or `tests/rebuild/contracts/*`.
