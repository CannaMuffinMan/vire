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
| #148 | `65fc7692` | conflict `docs/FINISH-LIST.md`. Dropped `pg_auth` row. Did not restore stale 147-branch rows. Re-merge when `cursor/pg-scram-plus-e596` moves. |
| #149 | `16f7f4f8` (`cursor/windows-tls-0630`) | first merge `ed926c6a`, then re-merged `16f7f4f8` (no PersistKeySet on ephemeral PFX). Clean both times. |
| #150 | `8f460c49` (`cursor/pe-dns-json-chain-567f`) | conflict `tools/couchstation-windows-all.ps1`. Kept `native-forms`. Dropped MZ-only proxy block. Writes `data/couchstation-windows-all-results.md`. |
| #151 | `36d2e644` (`cursor/native-405-proxy-ws-33ca`) | conflict `docs/FINISH-LIST.md` only. Packed blobs did not conflict in git. See below. |

## Packed rt-net / listen blobs (#150 vs #151)

Git auto-merged `src/rt-net.vire`. No conflict markers. Byte check after the merge:

- `src/rt-net-r4-blob.txt` matches #150 (`8f460c4`), not #151. DNS rbx/share-7 pack kept.
- `src/rt-net-json-blob.txt` matches #144 (`4b618c2`), not the stale #151 copy.
- `src/rt-net-blob.txt` is identical on #150 and #151.
- `src/rt-net.vire` is #144 park comments plus #151 `land_st_405`, POST body overlay at blob+2728, and in-process WS echo overlay.

Re-run on this tip:

```
python3 tools/pe-windows-gaps-check.py
bash tools/native-405-proxy-ws-check.sh
```

## Not merged yet

- #143 (`51de3c2f`) host/native POST `/block` deny-by-default is already on `6693e0e5`. Do not merge the `native-compiler` branch. It would delete native listen.
- `cursor/vire-4h-auth-compare` is not on origin yet. Merge it when the branch exists.
- #148 head is still `65fc7692`. Re-merge (no rebase) when `cursor/pg-scram-plus-e596` moves.

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
bash tools/native-405-proxy-ws-check.sh
bash tools/windows-tls-lane-check.sh
bash tools/native-elf-selfhost.sh
dotnet test tests/Vire.Tests/Vire.Tests.csproj -c Release --nologo
```

Caps stay arena 33554432, list 100000, steps 5000000, itemCap 1e6.
