# Host + gen1 PE FCG API prove on Windows. Redis on 127.0.0.1. Caps unchanged.
$ErrorActionPreference = "Stop"
$Root = Split-Path -Parent $PSScriptRoot
Set-Location -LiteralPath $Root
. (Join-Path $PSScriptRoot "native-host-info.ps1")
$env:VIRE_BUDGET = "5000000"
$env:VIRE_HEADLESS = "1"
$Data = Join-Path $Root "data"
New-Item -ItemType Directory -Force -Path $Data | Out-Null
$VireDll = Join-Path $Root "bin/Release/net10.0/vire.dll"
if (-not (Test-Path $VireDll)) { throw "missing $VireDll" }
$BaseSha = "9ea4561d12236f7f2f44858f137d7c948836df65"
$AfterSha = (git rev-parse HEAD).Trim()
Write-Output "fail_before_sha $BaseSha"
Write-Output "pass_after_sha $AfterSha"

function Convert-HexToExe([string]$HexPath, [string]$ExePath) {
    $hex = [System.IO.File]::ReadAllText($HexPath).Trim()
    if ($hex.Length -eq 0 -or ($hex.Length % 2) -ne 0) { throw "bad hex $HexPath" }
    $bytes = New-Object byte[] ($hex.Length / 2)
    for ($i = 0; $i -lt $bytes.Length; $i++) {
        $bytes[$i] = [Convert]::ToByte($hex.Substring($i * 2, 2), 16)
    }
    [System.IO.File]::WriteAllBytes($ExePath, $bytes)
}

function Invoke-Http([string]$Method, [string]$Url, [string]$Body) {
    $req = [System.Net.HttpWebRequest]::Create($Url)
    $req.Method = $Method
    $req.Timeout = 20000
    if ($Method -eq "POST") {
        $raw = [Text.Encoding]::UTF8.GetBytes($Body)
        $req.ContentType = "application/json"
        $req.ContentLength = $raw.Length
        $s = $req.GetRequestStream()
        $s.Write($raw, 0, $raw.Length)
        $s.Close()
    }
    try {
        $resp = $req.GetResponse()
        $reader = New-Object IO.StreamReader($resp.GetResponseStream())
        $text = $reader.ReadToEnd()
        $code = [int]$resp.StatusCode
        $reader.Close(); $resp.Close()
        return @{ Code = $code; Body = $text }
    } catch [System.Net.WebException] {
        $resp = $_.Exception.Response
        if ($resp -eq $null) { throw }
        $reader = New-Object IO.StreamReader($resp.GetResponseStream())
        $text = $reader.ReadToEnd()
        $code = [int]$resp.StatusCode
        $reader.Close(); $resp.Close()
        return @{ Code = $code; Body = $text }
    }
}

function Wait-Port([int]$Port, [int]$Tries = 300) {
    for ($i = 0; $i -lt $Tries; $i++) {
        try {
            $c = New-Object Net.Sockets.TcpClient
            $c.Connect("127.0.0.1", $Port)
            $c.Close()
            return
        } catch {
            Start-Sleep -Milliseconds 100
        }
    }
    throw "port $Port not listening"
}

function Redis-Cmd([int]$Port, [string[]]$Parts) {
    $sb = "*$($Parts.Count)`r`n"
    foreach ($p in $Parts) {
        $sb += "`$$($p.Length)`r`n$p`r`n"
    }
    $c = New-Object Net.Sockets.TcpClient
    $c.Connect("127.0.0.1", $Port)
    $st = $c.GetStream()
    $bytes = [Text.Encoding]::ASCII.GetBytes($sb)
    $st.Write($bytes, 0, $bytes.Length)
    $buf = New-Object byte[] 4096
    $n = $st.Read($buf, 0, $buf.Length)
    $c.Close()
    return [Text.Encoding]::ASCII.GetString($buf, 0, $n)
}

$RedisPort = 16379
$ListenHost = 18082
$ListenPe = 18083

# Throwaway redis-server if present; otherwise a tiny RESP PING/GET/SET listener in this process is not used.
# CI installs Redis-x64. Local runs may already have redis on 6379 — still bind 16379.
$redisExe = $null
foreach ($c in @(
        (Join-Path $env:ProgramFiles "Redis\redis-server.exe"),
        (Join-Path $env:LOCALAPPDATA "fcg-redis\redis-server.exe"),
        "redis-server"
    )) {
    if (Get-Command $c -ErrorAction SilentlyContinue) { $redisExe = (Get-Command $c).Source; break }
    if (Test-Path $c) { $redisExe = $c; break }
}
if (-not $redisExe) {
    $zip = Join-Path $Data "redis-win.zip"
    $dest = Join-Path $env:LOCALAPPDATA "fcg-redis"
    New-Item -ItemType Directory -Force -Path $dest | Out-Null
    Invoke-WebRequest -UseBasicParsing -Uri "https://github.com/microsoftarchive/redis/releases/download/win-3.0.504/Redis-x64-3.0.504.zip" -OutFile $zip
    Expand-Archive -Force -Path $zip -DestinationPath $dest
    $redisExe = Join-Path $dest "redis-server.exe"
}
$redisProc = Start-Process -FilePath $redisExe -ArgumentList "--port", "$RedisPort", "--bind", "127.0.0.1", "--protected-mode", "no" -PassThru -WindowStyle Hidden
Start-Sleep -Milliseconds 400
Wait-Port $RedisPort
Write-Output (Redis-Cmd $RedisPort @("SET", "waitlist:count", "3"))
Write-Output "redis_seed_ok"

git cat-file -e "$BaseSha^{commit}" 2>$null
if ($LASTEXITCODE -ne 0) { git fetch --depth 1 origin $BaseSha }
$oldSrc = Join-Path $Data "fcgcpa-fail-before.vire"
git show "${BaseSha}:api/fcgcpa.vire" | Set-Content -Path $oldSrc -Encoding utf8
$oldProc = Start-Process -FilePath "dotnet" -ArgumentList @("exec", $VireDll, $oldSrc, "18081") -PassThru -WindowStyle Hidden -RedirectStandardOutput (Join-Path $Data "old-listen.out") -RedirectStandardError (Join-Path $Data "old-listen.err")
Wait-Port 18081
$before = Invoke-Http "GET" "http://127.0.0.1:18081/api/waitlist/count" $null
Write-Output $before.Body
if ($before.Body -notmatch '"status":404') { throw "FAIL_BEFORE expected 404" }
Write-Output "FAIL_BEFORE at $BaseSha GET /api/waitlist/count is 404"
try { $oldProc.Kill() } catch { }

function Assert-Routes([int]$Port, [string]$Tag) {
    $pairs = @(
        @{ P = "/health"; W = '{"ok":true,"service":"fcgcpa","payments":false}' },
        @{ P = "/api/health"; W = '{"ok":true,"service":"fcgcpa","payments":false}' },
        @{ P = "/api/health/redis"; W = '{"ok":true,"redis":"PONG","payments":false}' },
        @{ P = "/payments"; W = '{"ok":false,"status":403,"error":"payments are off","payments":false}' },
        @{ P = "/api/payment/catalog"; W = '{"ok":false,"status":403,"error":"payments are off","payments":false}' },
        @{ P = "/api/waitlist/count"; W = '{"count":3,"max":null,"spotsLeft":null,"full":false,"registrationClosed":false}' }
    )
    foreach ($x in $pairs) {
        $got = Invoke-Http "GET" "http://127.0.0.1:$Port$($x.P)" $null
        Write-Output "$Tag $($x.P) $($got.Body)"
        if ($got.Body -ne $x.W) { throw "$Tag mismatch $($x.P) $($got.Body)" }
        if ($got.Body -match '"payments":true') { throw "payments on" }
    }
    $hp = Invoke-Http "POST" "http://127.0.0.1:$Port/api/login" "{}"
    Write-Output "$Tag honeypot $($hp.Body)"
    if ($hp.Body -ne '{"ok":false,"status":404,"error":"Endpoint not found"}') { throw "$Tag honeypot" }
    return $hp.Body
}

$hostProc = Start-Process -FilePath "dotnet" -ArgumentList @("exec", $VireDll, "fcg-api.vire", "$ListenHost", "$RedisPort") -PassThru -WindowStyle Hidden -RedirectStandardOutput (Join-Path $Data "host-listen.out") -RedirectStandardError (Join-Path $Data "host-listen.err")
Wait-Port $ListenHost
$hostLogin = Assert-Routes $ListenHost "host"
Write-Output "PASS_AFTER host FCG API at $AfterSha"

$pack = Join-Path $Data "fcg-api-guest.vire"
$parts = @(
    (Get-Content -Raw (Join-Path $Root "api/redis-cmd.vire")),
    (Get-Content -Raw (Join-Path $Root "api/fcg-routes.vire")),
    ((Get-Content (Join-Path $Root "fcg-api.vire") | Where-Object { $_ -notmatch '^use ' -and $_ -notmatch '^~' }) -join "`n")
)
[IO.File]::WriteAllText($pack, ($parts -join "`n`n") + "`n")
Write-Output "packed data/fcg-api-guest.vire"

$hexRel = "data/fcg-api.hex"
Remove-Item Env:VIRE_BUDGET -ErrorAction SilentlyContinue
$compileOut = & dotnet exec $VireDll --compiler compile-native.vire data/fcg-api-guest.vire $hexRel
$compileCode = $LASTEXITCODE
$env:VIRE_BUDGET = "5000000"
Write-Output $compileOut
if ($compileCode -ne 0) { throw "compile-native fcg-api exit $compileCode" }
if ("$compileOut" -notmatch "compiled") { throw "compile-native missing compiled" }
$exe = Join-Path $Data "fcg-api.exe"
Convert-HexToExe (Join-Path $Root $hexRel) $exe
$peProc = Start-Process -FilePath $exe -ArgumentList @("$ListenPe", "$RedisPort") -PassThru -WindowStyle Hidden -RedirectStandardOutput (Join-Path $Data "pe-listen.out") -RedirectStandardError (Join-Path $Data "pe-listen.err")
Wait-Port $ListenPe
$peLogin = Assert-Routes $ListenPe "pe"
if ($hostLogin -ne $peLogin) { throw "host/PE honeypot bodies differ" }
Write-Output "PASS_AFTER at $AfterSha host and gen1 PE FCG API bodies identical"

try { $hostProc.Kill() } catch { }
try { $peProc.Kill() } catch { }
try { $redisProc.Kill() } catch { }
