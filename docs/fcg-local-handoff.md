# Local-only FCG inventory handoff

Use this if Grok Build CLI (or any local agent) can see repos the cloud token cannot. Cloud `gh repo view CannaMuffinMan/fcgcpa-prod` failed with repository not resolved on 2026-11-07.

Do not assume the CLI is installed. Do not run this from the cloud agent. Do not implement the FCG stack. Do not change production, Railway, OBS, Station, or Brain. Do not copy `.env`, tokens, customer chain JSON, or secrets into a PR.

## Goal

Produce a read-only evidence pack the operator can paste or attach to a later planning PR. Paths and SHAs only. No source dumps of secrets.

## Allowlist to inspect (if present on disk)

- `https://github.com/CannaMuffinMan/fcgcpa-prod` at its default HEAD. Record `git rev-parse HEAD`, default branch, and a file tree of extensions (`.vire`, `.cs`, `.ts`, `.js`, `.c`, Docker, Railway).
- Any sibling FCG repo the operator names. Record the exact remote URL.
- Local clones already on the machine. Record path and `git remote -v`.

## Refuse

- `.env`, `*.pem`, `*secret*`, `VIRE_SEAL_KEY`, `FCG_API_TOKEN`, `X-FCG-Token` values
- `data/chain/` customer bodies
- Production deploy, domain, or OBS edits
- Starting compilers, installing packages onto the operator machine beyond what the CLI already has
- Opening PRs that contain copied secrets

## Commands (local, read-only)

```text
git -C <clone> rev-parse HEAD
git -C <clone> branch --show-current
git -C <clone> ls-files | sed -n '1,200p'
git -C <clone> ls-files | awk -F. '{print $NF}' | sort | uniq -c | sort -nr
```

Do not `git push`. Do not `railway up`.

## Report shape

- Repo URL and HEAD SHA (or "still inaccessible")
- Language inventory by extension count
- Whether the API matches `vire/api/fcgcpa.vire` or diverges
- Whether a Proof of Rot or skinned-browser tree exists
- Lockfiles (`package-lock.json`, `Cargo.lock`, `go.sum`, `deps.lock`) names only
- Nothing that looks like a credential

Attach the report to a follow-up on the multilingual planning PR. The cloud planning branch stays docs-only.
