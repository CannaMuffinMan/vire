# Rewrite unit. Other Go sidecars and harnesses

Inventory SHA `5cc110206f8f42ee25c127f2bfbe0f8bcd6067f4`. This agent did not re-open the files.

## Source paths and sizes from the inventory

| Path | files/lines | Role |
| --- | --- | --- |
| `landing-go/` | 13 / 3583 | Landing strangler |
| `cpa-go/` | 13 / 1610 | CPA strangler |
| `edge-go/` | 4 / 918 | Reverse proxy. rpc host to service `fcgbc` port 3001. Admin host to `fcgbc-copy` 8080. Railway service names, not a testnet dump. |
| `worker-go/` | 3 / 98 | Job names only. `main.go` exits. The inventory does not record the job name strings. Do not invent them. |
| `landing-go`, `cpa-go`, `fcgbds-go`, `fcgbds-dashboard-go`, `fcgbds-middleware`, `rpc-portal-go`, `dev-portal-go`, `worker-go` listen ports | unknown | Absent from the inventory. Re-read after clone. |
| `loadtest/`, `tools/load-test/`, `scripts/` | harness | Localhost only. `127.0.0.1`. Ports 7099 and 8778 forbidden. |

## Behavior to preserve

Edge routing table once re-read. Worker no-ops until Node schedulers are ported. Load tests stay loopback.

## Acceptance tests

1. Input `worker-go` start with job flags on. Expected exit 0 and no writes. Do not pretend jobs ran.
2. Input load test against a non-loopback address. Expected refuse.
3. Input bind of 7099 or 8778. Expected refuse.

## Vire capability

HTTP reverse proxy needs listen plus outbound TCP. Native PE has neither on this branch. Wrapping `go` is a failed goal.

Friday skip. Not a compile target this week.

## Security

Edge can send rpc traffic to the wrong service name. Keep Railway names as documentation, not as a reason to import chain data.

## Size and order

After API and edge policy. Worker follows Node schedulers, not the Go stub.
