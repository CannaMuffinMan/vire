# rt-net lane finish list

Placeholders use `TODO(VIRE-FINISH-NOW):` in source.

| file | symbol | what's missing | priority |
|---|---|---|---|
| src/rt-net.vire | rt-net-json-blob | Regen packed JSON encode/parse so parked `buf_*` / `push` / `map_put` / `to_text` roots match GPR/rbp helpers | high |
| src/rt-pg.vire | pg_auth / SCRAM | Guest SCRAM-SHA-256-PLUS (tls-unique / server-end-point) is not on the TLS API | medium |

## Removals (this PR)

| path / symbol | why dead | evidence |
|---|---|---|
| src/rt-net.vire `netNamesR3` | Never called; byte-identical to `netNamesR4`. Packed emit uses `netNames` or `netNamesR4` (`route_nparams == 4`) | repo grep: only the `define`; no `netNamesR3` call site |
| src/rt-net-r3-names.txt, src/rt-net-r4-names.txt | Packer dump leftovers; not read by emit, stage, tests, or `pack-tls-pe.py` | filename grep: zero references |
| src/rt-tls.vire `emitTlsPeRefuse` + `msg_tls_pe` park | Superseded by packed SChannel `emitTlsPeGuest` (`rt-tls-pe-blob`) | `emitTlsRuntime` PE path only calls `emitTlsPeGuest`; `emitTlsPeRefuse with` never used |
| src/rt-ws.vire `emitWsIat` | Duplicate of `emitIat`; listen path already uses `emitIat` | `emitWsIat with` never appears; IAT sites call `emitIat` |
| src/dist-static.vire `dist_known` | Alias of `dist_path`, never referenced | guests call `dist_path`; grep only the define |

`src/rt-net-unpacked.vire` kept: `dump-net-extras.vire` uses it to regenerate blobs. Packed `rt-net-*.txt` blobs that `emitNetRuntime` reads kept. `rt-tls-pe-names.txt` kept: `tools/pack-tls-pe.py` writes it.

Staged copies `data/src/rt-net.vire`, `data/src/rt-ws.vire`, `data/src/rt-tls.vire` updated to match `src/` (CompilerStageTests).

## Cross-lane notes (untouched)

- `src/rt-net-r3-blob.txt` / pins / fixes (and `data/src` copies) are not read by `emitNetRuntime`, but `CompilerStage.cs`, `tools/stage-compiler-src.sh`, `tools/native-selfhost-handoff.ps1`, `tools/native-elf-win-hello.ps1`, and `CompilerStageTests` still require them. Do not delete until that lane drops the stage list.
- Duplicate `parkDns` lives in both `src/rt-net.vire` (packed) and `src/rt-dns.vire` (unpacked `use`). Packed compiler does not `use` rt-dns.
- `tests/native/fixtures/gc-tagged-walk/rt-ws.vire` still defines unused `emitWsIat` (fixture copy).
- `dump-net-extras.vire` is outside this lane; it is the unpack/regen driver.
