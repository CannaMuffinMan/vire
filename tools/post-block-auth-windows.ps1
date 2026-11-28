# CouchStation PE proof for native POST /block deny-by-default Bearer.
# Linux ELF proof is tools/post-block-auth-native.sh. Do not treat a Linux run as PE proof.
# Loopback 127.0.0.1 only. Never prints FCG_API_TOKEN / FCG_BLOCK_TOKEN.
$ErrorActionPreference = "Stop"
$Root = Split-Path -Parent $PSScriptRoot
Set-Location -LiteralPath $Root
. (Join-Path $PSScriptRoot "native-host-info.ps1")
$env:VIRE_HEADLESS = "1"
Remove-Item Env:VIRE_BUDGET -ErrorAction SilentlyContinue
Remove-Item Env:FCG_API_TOKEN -ErrorAction SilentlyContinue
Remove-Item Env:FCG_BLOCK_TOKEN -ErrorAction SilentlyContinue
$After = (git rev-parse HEAD).Trim()
Write-Host "pass_after_sha $After"
$Data = Join-Path $Root "data"
$gen1 = Join-Path $Data "gen1.exe"
if (-not (Test-Path $gen1)) { throw "missing data/gen1.exe; run native-selfhost-handoff.ps1 on Windows first" }
$vire = Get-Content -Raw -LiteralPath (Join-Path $Root "guest-chain.vire")
$vire = $vire.Replace("listen with 18080", "listen with 0")
Set-Content -LiteralPath (Join-Path $Data "block-auth.vire") -Value $vire -NoNewline
$hex = Join-Path $Data "block-auth.hex"
$exe = Join-Path $Data "block-auth.exe"
if (Test-Path $hex) { Remove-Item -Force $hex }
$p = Start-Process -FilePath $gen1 -ArgumentList @("data/block-auth.vire", "data/block-auth.hex") -WorkingDirectory $Root -NoNewWindow -PassThru
$code = Get-ChildExitCode $p
if ($code -ne 0) { throw "gen1 compile exit $code" }
$h = [IO.File]::ReadAllText($hex).Trim()
$bytes = New-Object byte[] ($h.Length / 2)
for ($i = 0; $i -lt $bytes.Length; $i++) { $bytes[$i] = [Convert]::ToByte($h.Substring($i * 2, 2), 16) }
[IO.File]::WriteAllBytes($exe, $bytes)
New-Item -ItemType Directory -Force -Path (Join-Path $Data "chain") | Out-Null
Copy-Item (Join-Path $Root "data/rebuild/chain/head.json") (Join-Path $Data "chain/head.json") -Force
Copy-Item (Join-Path $Root "data/rebuild/chain/000001.json") (Join-Path $Data "chain/000001.json") -Force
Copy-Item (Join-Path $Root "data/rebuild/chain/blocks.json") (Join-Path $Data "chain/blocks.json") -Force
$env:FCG_API_TOKEN = "short-token"
$outLog = Join-Path $Data "block-auth-pe.log"
$proc = Start-Process -FilePath $exe -WorkingDirectory $Root -NoNewWindow -PassThru -RedirectStandardOutput $outLog -RedirectStandardError ($outLog + ".err")
$null = $proc.Handle
$port = 0
$deadline = (Get-Date).AddSeconds(15)
while ((Get-Date) -lt $deadline) {
    if (Test-Path $outLog) {
        $t = Read-SharedText $outLog
        if ($t -match "listening on 127.0.0.1:(\d+)") { $port = [int]$Matches[1]; break }
    }
    if ($proc.HasExited) { throw "PE guest exited early" }
    Start-Sleep -Milliseconds 50
}
if ($port -lt 1) { throw "PE listen port missing" }
function Invoke-Raw([int]$Port, [string]$Req) {
    $tcp = New-Object System.Net.Sockets.TcpClient
    $tcp.Connect("127.0.0.1", $Port)
    $s = $tcp.GetStream()
    $buf = [Text.Encoding]::ASCII.GetBytes($Req)
    $s.Write($buf, 0, $buf.Length)
    $ms = New-Object IO.MemoryStream
    $tmp = New-Object byte[] 2048
    $s.ReadTimeout = 4000
    try {
        while (($n = $s.Read($tmp, 0, $tmp.Length)) -gt 0) { $ms.Write($tmp, 0, $n) }
    } catch { }
    $tcp.Close()
    return [Text.Encoding]::ASCII.GetString($ms.ToArray())
}
$before = Invoke-Raw $port "GET /chain HTTP/1.1`r`nHost: x`r`nConnection: close`r`n`r`n"
$post = Invoke-Raw $port "POST /block HTTP/1.1`r`nHost: x`r`nContent-Length: 16`r`nConnection: close`r`n`r`n{`"text`":`"pwned`"}"
Write-Host ("POST short-secret " + ($post.Split("`r`n")[0]))
if ($post -notmatch "401") { throw "PE short secret expected 401" }
if ($post -match "pwned" -and $post -match "accepted") { throw "PE short secret appended" }
$after = Invoke-Raw $port "GET /chain HTTP/1.1`r`nHost: x`r`nConnection: close`r`n`r`n"
$bbody = if ($before.Contains("`r`n`r`n")) { $before.Substring($before.IndexOf("`r`n`r`n") + 4) } else { $before }
$abody = if ($after.Contains("`r`n`r`n")) { $after.Substring($after.IndexOf("`r`n`r`n") + 4) } else { $after }
if ($bbody -ne $abody) { throw "PE chain changed after 401" }
try { Stop-Process -Id $proc.Id -Force } catch { }
Write-Host "PASS_AFTER PE short configured secret 401 chain unchanged"

Remove-Item Env:FCG_API_TOKEN -ErrorAction SilentlyContinue
Remove-Item Env:FCG_BLOCK_TOKEN -ErrorAction SilentlyContinue
$env:FCG_API_TOKEN = "test-block-token1"
$outLog2 = Join-Path $Data "block-auth-pe-api.log"
$proc2 = Start-Process -FilePath $exe -WorkingDirectory $Root -NoNewWindow -PassThru -RedirectStandardOutput $outLog2 -RedirectStandardError ($outLog2 + ".err")
$null = $proc2.Handle
$port2 = 0
$deadline2 = (Get-Date).AddSeconds(15)
while ((Get-Date) -lt $deadline2) {
    if (Test-Path $outLog2) {
        $t2 = [IO.File]::ReadAllText($outLog2)
        if ($t2 -match "listening on 127.0.0.1:(\d+)") { $port2 = [int]$Matches[1]; break }
    }
    if ($proc2.HasExited) { throw "PE api-token guest exited early" }
    Start-Sleep -Milliseconds 50
}
if ($port2 -lt 1) { throw "PE api-token listen port missing" }
$none = Invoke-Raw $port2 "POST /block HTTP/1.1`r`nHost: x`r`nContent-Length: 16`r`nConnection: close`r`n`r`n{`"text`":`"none`"}"
Write-Host ("POST api-token no-bearer " + ($none.Split("`r`n")[0]))
if ($none -notmatch "401") { throw "PE FCG_API_TOKEN write path expected 401 without Bearer" }
$wrong = Invoke-Raw $port2 "POST /block HTTP/1.1`r`nHost: x`r`nAuthorization: Bearer wrong-token-16x`r`nContent-Length: 16`r`nConnection: close`r`n`r`n{`"text`":`"wrong`"}"
if ($wrong -notmatch "401") { throw "PE FCG_API_TOKEN wrong Bearer expected 401" }
try { Stop-Process -Id $proc2.Id -Force } catch { }
Write-Host "PASS_AFTER PE FCG_API_TOKEN deny-by-default 401 (CouchStation execute, not claimed from Linux)"
Write-Host "post-block-auth windows ok"
