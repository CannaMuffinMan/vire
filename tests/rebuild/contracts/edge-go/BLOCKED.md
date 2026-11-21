# edge-go blocked (no stubs)

- reverse-proxy `Host` map to `*.railway.internal`
- `Location` rewrite, `X-Forwarded-Host` / `X-Forwarded-Proto`
- SHA-256 `X-FCG-Maintenance-Bypass`, CIDR `MAINTENANCE_ALLOW_IPS`
- `PAYMENTS_ENABLED` startup refuse (process exit, no HTTP body)
- maintenance HTML, `Retry-After`, `X-Robots-Tag`
- public `0.0.0.0` bind (Vire is loopback only)
