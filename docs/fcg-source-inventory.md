# FCG source inventory (cloud, 2026-11-07)

This file records what this planning agent could read. It is not a claim that Forever Couch Gang is complete in Vire. It is not a review of private or missing repos.

Inspected at Vire `native-compiler` `0f758e702771ed3276ee553a76c7a86cc83846dd`. Draft PRs 31-38 were read with `gh pr view` only. Those branches were not checked out.

## Accessible GitHub

| Ref | Result |
| --- | --- |
| `https://github.com/CannaMuffinMan/vire` | Public. Default `native-compiler`. Only org repo `gh repo list` returned. |
| `https://github.com/CannaMuffinMan/fcgcpa-prod` | Not resolved. `gh repo view` GraphQL, "Could not resolve to a Repository". Private, renamed, or absent from this token. **Not reviewed.** |
| Other CannaMuffinMan repos | `gh search repos --owner CannaMuffinMan` returned only `vire`. User repo list API returned 403. **No second public FCG repo found.** |

## Accessible in-tree FCG-related files

| Path | What it is | Runtime it needs |
| --- | --- | --- |
| `api/fcgcpa.vire` | Web2 door. Routes `/health`, `/payments` (403), `/info`, `/connect`, GET `/chain`, POST `/block`, `/mine` (403). Chain files under `data/chain/`. | Vire `listen`, `hash`, `json`/`parse`, `write`/`read`. `PORT` / `FCG_API_TOKEN` per `api/README.md`. |
| `api/README.md` | Only web2 service. Railway deploy. Apps are a skinned browser. Proof of Rot mining stays in the app. Chain id `forevercouchgang.blockchain`. Payments off. | Railway `PORT`. No TLS in-process (`SECURITY.md` non-guarantee). |
| `sites/landing/site.vire` | Emits HTML and CSS strings. Google fonts URL. | Interpreter `write` into `sites/landing/site/`. |
| `sites/landing/README.md` | Static home. Do not start `listen` from that folder. | Same. |
| `sites/cpa/app.vire` | Couch Potato HTML and CSS. Merch link `https://shop.forevercouchgang.space`. | Interpreter write into `sites/cpa/site/`. |
| `sites/cpa/README.md` | States the page is HTML and CSS written by Vire. It is not a React app. | Same. |
| `systems/chain.vire` | Sample chain writer, not the API. | Interpreter. |
| `vault.vire` | Writes HTML, CSS, and JS as text. Not named FCG in the README. | Interpreter plus later browser. |
| `GUIDE.md` / `VireListen.cs` | `listen` loopback, token `X-FCG-Token`, static `site/` GET allowlist including `.js`. | .NET host. Native PE listen is not this HEAD. |
| `compose.yaml` | Docker runs `tests.vire` only. | Not an FCG deploy. |

## Evidenced FCG subsystems (from those files only)

1. Web2 API (`fcgcpa.vire`). Present as Vire source.
2. Local demo chain on disk. Present.
3. Static landing HTML/CSS. Present as Vire string emit, not as a compiled HTML frontend.
4. Couch Potato static HTML/CSS. Present the same way.
5. Skinned browser apps that mine with Proof of Rot and POST blocks. **Source missing** (not in `vire`, `fcgcpa-prod` inaccessible).
6. Mining network. README says there is none. `/mine` is 403.
7. Payments. Off. `/payments` is 403.
8. Shop `shop.forevercouchgang.space`. External URL only. **Storefront source missing.**
9. Twitch and YouTube connect URLs. JSON in `/connect`. No OAuth client source in this tree.
10. TLS, Railway prod config, OBS, customer data. **Not in this tree. Do not invent.**

## Vire capability vs each evidenced part

| Part | Vire today | Missing | Order |
| --- | --- | --- | --- |
| API process | `listen` + route in Vire | Native self-host unproven. No TLS server (`SECURITY.md`). POST `/block` auth is Canna's call (`api/fcgcpa.vire` comments, CHANGELOG). | Keep Vire. Do not rewrite in C#. Direct compile later via ML1+ after self-host. |
| Chain files | `data/chain/*.json` SHA via `hash` | Segment cap 64, 512KiB grow (`appendBlock`). No migration language. | Tests on `verifyChain` before any storage change. |
| Landing / CPA pages | String `write` of HTML/CSS | Direct HTML/CSS frontend is ML3. Remote fonts must not fetch at compile. | After ML1. |
| Skinned browser / Proof of Rot app | None in-tree | Entire client. Language unknown until local handoff. | Blocked on missing source. |
| `cl.exe` C plugins | `VireBuild.cs` shells MSVC | Direct C subset is ML2. | After ML1. Not FCG-critical until a `.c` file appears in FCG sources. |
| Advisory / CVE | `deps.lock` file hashes only | OSV/NVD snapshots (ML4). Compiling source does not clear CVEs. | Parallel after ML1. |

## Drafts that are not this plan

| PR | Branch | Note |
| --- | --- | --- |
| 31 | `cursor/native-selfhost-intern-0258` | Intern. Not merged. Not a 32MB fixed-point. |
| 32 | `cursor/gap-closure-portability-0258` | Gap plan. Says Vire does not compile JS/Rust/C#. |
| 33-34, 36 | emit hot paths | Compiler lane. |
| 35 | `cursor/security-audit-fix-0b9c` | Native sandbox. |
| 37 | `cursor/selfhost-extend-0258` | `rt_extend` so gen1 can compile `emitList`. Not integrated into `native-compiler`. Not gen1/gen2 proof. |
| 38 | `cursor/native-runtime-32mb-0b9c` | Intern/heap_cell on path/frame sandbox. Explicitly not merged. Remaining Windows junction and fixed-point. |

Do not call 37 or 38 a complete standalone runtime.

## Missing-source assumptions (explicit)

- If `fcgcpa-prod` exists privately, this cloud token cannot see it. Treat production API, env, and Railway service config as unread.
- If a mobile or desktop FCG app lives in another git remote, it was not listed by `gh repo list`.
- Proof of Rot algorithm text is the README phrase only. No implementation file was found.
- "Entire FCG stack in Vire" cannot be scheduled as a finite current support set. The missing client is the largest hole.

## Next gates (operator)

1. Local-only read of `fcgcpa-prod` via the handoff in `docs/fcg-local-handoff.md`. Cloud must not receive `.env`, secrets, or customer chain data.
2. Operator GO on ML1 in `docs/multilingual-source-compiler-plan.md`.
3. Sibling compiler and security agents keep 31-38. This branch does not touch them.
4. Next planning milestone (after 8PM EST Nov 7 only if the operator asks later). Map any newly visible client repo onto the capability table. Do not start stack implementation in that milestone.
