# Bulk emitList and PE concat after PR #34

Depends on PR #34 (`7cbc63c`) / PR #33 (`3f9e0cd`). Not PR #31, #32, or #35.

## Profile on PR #34 (Linux, uninstrumented, this VM, 60s cap)

`probe-build-exe` 0.521s vs `probe-open-image` 0.516s on an earlier sample, then 0.533s vs 0.516s. The extra was a 14336-iteration `push` in `buildExe`. `emitList` still ran 846 times in `src/rt.vire` plus `src/rt-more.vire` (counted). Guest empty/hello/strings/expr compiles stayed near 1.15–1.20s. Linux hello did not hide an 8s `emitU8`-style cost. Windows call density from Build still says those 846 Vire loops can matter there. Linux walls are not Windows walls.

## Change

- Host builtin `extend` mutates a list by appending another, wrapping each extra item like `emitU8`, refusing past the list cap.
- `emitList` is `extend`. Interpreter and `CompiledMachine` both have it.
- `buildExe` concatenates the 512-byte header and the image with list `+` instead of per-byte `push`.

## After (same VM)

| Probe | PR #34 | This |
|---|---|---|
| `probe-emitlist.vire` 21000 | 0.190s | 0.110–0.120s |
| `probe-open-image.vire` | 0.516s | 0.368s |
| `probe-build-exe.vire` | 0.533s | 0.390s |
| compile empty | 1.130s | 1.055s |
| compile hello | 1.167s | 1.162s |
| compile strings | 1.166s | 1.165s |
| compile expr | 1.269s | 1.167s |

Hello `.hex` SHA-256 `c82fcb56dab3407745e40510e230eae29fbf5c1770fdd90124ad9985ed8a3173` unchanged. PE execute unproven.

Linux hello was already parse + `openImage` + `hexOf`. The isolated probes moved. Windows must be timed on Windows.

## Overlap with PR #35

PR #35 (`cursor/security-audit-fix-0b9c`) also edits `src/pe.vire` (GetFileAttributesA IAT) and `src/rt.vire` (frame_base). This PR edits `buildExe` at the end of `pe.vire` and `emitList` at the top of `rt.vire`. Different hunks. Do not merge by copying PR #35 sandbox code into this lane. Rebase/merge later by hand.

## Windows recipe

```text
set VIRE_BUDGET=5000000
dotnet exec bin\Release\net10.0\vire.dll probe-emitlist.vire
dotnet exec bin\Release\net10.0\vire.dll probe-open-image.vire
dotnet exec bin\Release\net10.0\vire.dll probe-build-exe.vire
dotnet exec bin\Release\net10.0\vire.dll compile-native.vire data\guest-hello.vire data\guest-hello.hex
```

Copy `guest-hello.vire` into `data\` first (`read` only opens `data/` and `site/`). Compare hello hex SHA to `c82fcb56…`. Do not run `native-selfhost-proof.ps1`.
