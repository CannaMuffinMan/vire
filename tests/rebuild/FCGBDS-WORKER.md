# fcgbds-go + worker-go native port

Derived from source, not live (`fcgcpa-prod` `5cc11020`). No production dials, secrets, or internal hostnames.

PR #96 covers a one-route `fcgbds-go GET /health` sidecar guest. This lane is a **separate** service guest (`guest-fcgbds.vire`) with every unauth route plus worker-go. It does not edit #96 files.

## Volatile fields

Harness `tools/rebuild-fcgbds-worker-diff.sh` drops JSON keys `ts`, `generatedAt`, `lastSeenAt`, `dayKey` before equality. Go uses `time.Now` (RFC3339Nano). Native has no clock; the guest writes `"now"` or `1970-01-01`.

## HTTP status vs Go bodies

Go `WriteHeader(503|400)` with bodies that omit `"status"`. Vire maps status from JSON `"status":N`. Refused and 400 heartbeat bodies therefore include `"status"` so the status line matches. Field match is still `ok`/`error`.

TODO(VIRE-FINISH-NOW): remaining gaps below still lack an in-tree contract or would weaken listen/sandbox. Do not stub them.

## Remaining gaps

- Reviewer TTL is process-local in Go. This guest is per-request. There is no recorded multi-request live-count golden and no guest clock for expiry.
- Go `PORT` set binds `0.0.0.0`. Vire native listen prints `127.0.0.1`. Host public bind is `VIRE_BIND=public` plus a 16-char token, not PORT. Do not open native 0.0.0.0.
- Go `json.Encoder` trailing newline is stripped in the diff.
- Worker env is argv `KEY=VALUE` (no getenv). `say` is stdout, not stderr. Job bodies (aggregation work) are skeleton-only; no Go job-run goldens in this repo.
- Windows PE not proven here; see `tools/rebuild-fcgbds-worker-windows.ps1` and `tools/rebuild-fcgbds-heartbeat-windows.ps1`.
