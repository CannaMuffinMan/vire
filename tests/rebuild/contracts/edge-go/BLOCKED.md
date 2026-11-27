# edge-go blocked (no stubs)

TODO(VIRE-FINISH-NOW): prove remaining edge-go Host-map/maintenance/payments behaviors listed below on host and native without raising caps.

- reverse-proxy `Host` map to `*.railway.internal`
- `Location` rewrite, `X-Forwarded-Host` / `X-Forwarded-Proto`
- SHA-256 `X-FCG-Maintenance-Bypass`, CIDR `MAINTENANCE_ALLOW_IPS`
- `PAYMENTS_ENABLED` startup refuse (process exit, no HTTP body)
- maintenance HTML, `Retry-After`, `X-Robots-Tag`
- public `0.0.0.0` bind (Vire is loopback only)
