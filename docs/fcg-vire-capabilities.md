# Vire capabilities against FCG needs

Facts from this checkout at `7c7c8ea3dcc4030ba8714fc2330d30b67f8d6867` unless a row names PR 47.

## Interpreter versus native PE

| Lane | What exists | Files | Counts as built by Vire for FCG |
| --- | --- | --- | --- |
| C# host | Parses VIR, runs builtins, `listen` | `Vire.cs`, `VireListen.cs`, `VireNet.cs` | No. Host is .NET. |
| Native gen1==gen2 | Windows x64 PE self-compile claimed on this branch | `compile-native.vire`, `src/rt.vire`, `src/rt-more.vire`, `src/pe.vire`, `NATIVE-COMPILER.md` | Yes for compute and files. No for FCG HTTP until sockets exist in the PE. |
| Native HTTP | Draft PR 47 | PR head `b650932307ffce7efe887c6cac67098e7f406822`, files include `src/rt-net.vire`, `guest-health.vire`, `tests/Vire.Tests/NativeNetTests.cs` | Not proven. Not on `native-compiler`. |

## Builtin map

| Need | Interpreter today | Native PE today | Notes |
| --- | --- | --- | --- |
| HTTP listen | Yes. `listen` in `Vire.cs` line 719, body in `VireListen.cs`. Loopback default. `VIRE_BIND=public` needs `FCG_API_TOKEN` length at least 16. | No on this branch. `systems/net.vire` is an in-memory map with no sockets. | C# `TcpListener` is not a VIR PE. |
| HTTP/1.1 parse | Yes. Tests in `tests/Vire.Tests/ListenTests.cs` and `ListenSecurityTests.cs`. `GET /health` returns 200 without token. | PR 47 only. | Chunked encoding refused in the C# host. |
| TLS | No. `SECURITY.md` says there is no TLS server. | No. | Product FCG also uses `http.createServer` only. TLS is at the edge. |
| JSON | Yes. `json` and `parse` in `Vire.cs`. Kit `deps/jsonkit/lib.vire`. | Partial. Compiler uses `json` in `compiler.vire`. Guest JSON over HTTP is PR 47. | 1 MB parse cap in the interpreter. |
| File IO | Yes. `read`, `write`, `append`, `copy`, `erase`, `files`, `folders` sandboxed to `data` and `site`. | Yes. `emitMore` file ops in `src/rt-more.vire`. | Product Prisma is not files. |
| SHA-256 | Yes. `hash` calls `VireSeal.HashText`. | Yes. `emitSha` in `src/rt-more.vire`. | Not HMAC-SHA256. Not bcrypt. |
| HMAC / JWT | No symbol in this tree. | No. | Product uses `jsonwebtoken` and cookie `authToken`. |
| Postgres wire | No. | No. | |
| Redis RESP | No. | No. | Product `ioredis`. |
| WebSocket | No. | No. | |
| Stripe | No. | No. | Keep `PAYMENTS_ENABLED` off. |
| `fetch` / `post` | Interpreter client in `VireNet.cs`. Refuses private nets. | PR 47 net blob is server-oriented. Do not assume outbound client. | |
| HTML emit | String writes to `site/`. `sites/landing/site.vire` is not Next 16. | Same guest file writes. | Not RSC, not Tailwind 4, not Vite. |
| Windows GUI | `open`, `line`, `field`, `button` in the host. | Not an FCG browser. | No WebView2 in this repo. |

## In-tree FCG lookalikes that are the wrong product

| Vire path | What it is | What fcgcpa-prod is, per inventory |
| --- | --- | --- |
| `api/fcgcpa.vire` | Disk JSON chain plus `listen` | Node Express in `api/src/index.ts` |
| `sites/landing/site.vire` | HTML string emitter | Next 16 `landing-page/` |
| `sites/cpa/app.vire` | Small VIR app | Vite `couch-potato-app/` |

Do not treat those VIR files as the rewrite source. They are a prior wrong inventory.

## Security that already binds Vire

- Loopback listen unless `VIRE_BIND` is `public` and a token is set. `GUIDE.md`, `VireListen.cs`.
- Reserved ports forbidden. `NATIVE-COMPILER.md` names 7099, 8778, 7071, 7072, 17841, 7093, 17843.
- No payments. No testnet dump.
- Token compare does not stop at the first differing character. `VireListen.cs` plus `ListenSecurityTests.cs`.
- Static `site/` GET is allowlisted. No directory listing. No `.vire` source.

## What "exists today" means for a later owner

If you ship FCG by calling `dotnet run` and `listen`, you shipped an interpreter demo. If you ship by `go run` or `node dist/index.js`, you did not compile FCG in Vire. The bar is a gen1-compiled PE that speaks the contract, or an explicit operator exception that this map does not grant.
