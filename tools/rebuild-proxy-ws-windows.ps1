# CouchStation PE proof stub: RFC 6455 upgrade through reverse-proxy.
$ErrorActionPreference = "Stop"
$Root = Split-Path -Parent $PSScriptRoot
$rt = Get-Content -Raw (Join-Path $Root "src\rt.vire")
if ($rt -notmatch "33554432") { throw "arena cap drifted" }
$cs = Get-Content -Raw (Join-Path $Root "Vire.cs")
if ($cs -notmatch "100000") { throw "list cap missing" }
if ($cs -notmatch "5000000") { throw "step cap missing" }
# TODO(VIRE-FINISH-NOW): host-vs-PE proxy-ws 101 / bad 400 / refuse 403 vs loopback echo
exit 1
