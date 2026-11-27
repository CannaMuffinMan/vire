# CouchStation PE proof stub: api-go chat/live RFC 6455 vs host.
$ErrorActionPreference = "Stop"
$Root = Split-Path -Parent $PSScriptRoot
$rt = Get-Content -Raw (Join-Path $Root "src\rt.vire")
if ($rt -notmatch "33554432") { throw "arena cap drifted" }
$cs = Get-Content -Raw (Join-Path $Root "Vire.cs")
if ($cs -notmatch "100000") { throw "list cap missing" }
if ($cs -notmatch "5000000") { throw "step cap missing" }
# TODO(VIRE-FINISH-NOW): compile apigo-ws to PE and match ELF 101/echo/fail-closed frames
exit 1
