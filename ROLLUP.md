# VIRE 4-hour rollup (proof-only)

This branch is not a merge unit. Land the source PRs, then this rollup only as an integration check.

## Base

`cursor/vire-cleanup-integration` at `6693e0e5d78c9df775d0531a39a14a574239cfac`.

## Merged (normal merge, no rebase)

| PR | head | notes |
|---|---|---|
| #144 | `4b618c2d` | clean |
| #145 | `29ba1ef1` | clean |
| #146 | `3add41ce` | clean |
| #147 | `67603360` | conflict `docs/FINISH-LIST.md`. Kept 144-146 row deletions. Dropped tools-ci rows 147 implements. |
| #148 | `65fc7692` | conflict `docs/FINISH-LIST.md`. Dropped `pg_auth` row. Did not restore stale 147-branch rows. |
| #149 | `ed926c6a` (`cursor/windows-tls-0630`) | clean |
| #150 | `8f460c49` (`cursor/pe-dns-json-chain-567f`) | conflict `tools/couchstation-windows-all.ps1`. Kept `native-forms`. Dropped MZ-only proxy block. Writes `data/couchstation-windows-all-results.md`. |

## Not merged

#143 (`51de3c2f`, POST `/block` auth) is not a git ancestor of the base. Host `BlockAuthTests.cs` matches the base file. Base `6693e0e5` already denies native `POST /block` when the write secret is missing or short. Merging #143 from `native-compiler` would delete native listen code on this branch. Policy is already contained.

## Left out on purpose

Dashboard, proxy, and WS feature lanes, and later 4h lanes. Fold those in a follow-up rollup.

## CouchStation one-shot (Windows PC only)

Linux ELF is not PE proof. Do not touch Defender. Do not reboot. Unset `VIRE_BUDGET` (the script does this).

```
git fetch origin cursor/vire-4h-rollup
git checkout cursor/vire-4h-rollup
Remove-Item Env:VIRE_BUDGET -ErrorAction SilentlyContinue
$env:VIRE_HEADLESS = "1"
powershell -NoProfile -File tools/couchstation-windows-all.ps1
```

Results: `data/couchstation-windows-all-results.md` and `data/couchstation-windows-all.log`.

## Linux proof commands (this rollup)

```
python3 tools/pe-windows-gaps-check.py
bash tools/native-elf-selfhost.sh
dotnet test tests/Vire.Tests/Vire.Tests.csproj -c Release --nologo
bash tools/windows-tls-lane-check.sh
```

Caps stay arena 33554432, list 100000, steps 5000000, itemCap 1e6.
