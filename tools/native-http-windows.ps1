# FAIL_BEFORE / PASS_AFTER: Vire HTTP framework, host vs gen1 PE.
# Caps unchanged. Real OS listen + raw TCP. No outside compiler.
$ErrorActionPreference = "Stop"
$Root = Split-Path -Parent $PSScriptRoot
Set-Location -LiteralPath $Root
. (Join-Path $PSScriptRoot "native-host-info.ps1")
Write-VireHostInfo
$env:VIRE_BUDGET = "5000000"
$env:VIRE_HEADLESS = "1"
$Data = Join-Path $Root "data"
New-Item -ItemType Directory -Force -Path $Data | Out-Null
$VireDll = Join-Path $Root "bin/Release/net10.0/vire.dll"
if (-not (Test-Path $VireDll)) { throw "missing $VireDll" }
$BaseSha = "9ea4561d12236f7f2f44858f137d7c948836df65"
$AfterSha = if ($env:VIRE_HEAD_SHA) { $env:VIRE_HEAD_SHA.Trim() } else { (git rev-parse HEAD).Trim() }
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

function Invoke-Vire {
    param([Parameter(ValueFromRemainingArguments = $true)][string[]]$Args)
    $leaf = [IO.Path]::GetFileName($Args[0])
    $savedBudget = $env:VIRE_BUDGET
    if ($leaf -eq "compile-native.vire" -or $leaf -eq "compiler.vire") {
        $Args = @("--compiler") + $Args
        Remove-Item Env:VIRE_BUDGET -ErrorAction SilentlyContinue
    }
    try {
        $out = & dotnet exec $VireDll @Args
        $code = $LASTEXITCODE
        if ($null -ne $out) { $out | Write-Host }
        if ($null -eq $code) { return 0 }
        return [int]$code
    } finally {
        if ($savedBudget) { $env:VIRE_BUDGET = $savedBudget }
    }
}

git cat-file -e "$BaseSha^{commit}" 2>$null
if ($LASTEXITCODE -ne 0) {
    git fetch --depth 1 origin $BaseSha
}
$fb = Join-Path $Data "http-fail-before"
if (Test-Path $fb) { Remove-Item -Recurse -Force $fb }
git worktree add --detach $fb $BaseSha
try {
    if (Test-Path (Join-Path $fb "src/http.vire")) { throw "base already has src/http.vire" }
    $probe = Join-Path $fb "data/http-missing.vire"
    New-Item -ItemType Directory -Force -Path (Join-Path $fb "data") | Out-Null
    Set-Content -Path $probe -Value "use `"src/http.vire`"`ndefine main`n  say 1`nend`n"
    $beforeOut = & git -C $fb rev-parse HEAD
    Write-Output "fail_before_checkout $beforeOut"
    Push-Location $fb
    try {
        $missing = & dotnet exec $VireDll --compiler "compile-native.vire" "data/http-missing.vire" "data/http-missing.hex" 2>&1 | Out-String
        $missingCode = $LASTEXITCODE
    } finally { Pop-Location }
    Write-Output $missing.TrimEnd()
    Write-Output "fail_before_compile_exit $missingCode"
    if ($missingCode -eq 0) { throw "fail-before compile unexpectedly succeeded" }
} finally {
    git worktree remove --force $fb
}
Write-Output ("FAIL_BEFORE at {0}: src/http.vire missing; HTTP framework guest would not compile" -f $BaseSha)

Copy-Item (Join-Path $Root "http-prove.vire") (Join-Path $Data "http-prove.vire") -Force
Copy-Item (Join-Path $Root "guest-http.vire") (Join-Path $Data "guest-http.vire") -Force
New-Item -ItemType Directory -Force -Path (Join-Path $Data "src") | Out-Null
Copy-Item (Join-Path $Root "src/http.vire") (Join-Path $Data "src/http.vire") -Force

Write-Output "http_prove_host_start"
$hostProve = & dotnet exec $VireDll "http-prove.vire"
$hostProveCode = $LASTEXITCODE
Write-Output $hostProve
Write-Output "http_prove_host_exit $hostProveCode"
if ($hostProveCode -ne 0) { throw "host http-prove exit $hostProveCode" }

$gen1 = Join-Path $Data "gen1.exe"
if (-not (Test-Path $gen1)) { throw "missing gen1.exe; run native-selfhost-handoff.ps1 first" }

$proveHex = Join-Path $Data "http-prove.hex"
$proveExe = Join-Path $Data "http-prove.exe"
if (Test-Path $proveHex) { Remove-Item -Force $proveHex }
$p = Start-Process -FilePath $gen1 -ArgumentList @("data/http-prove.vire", "data/http-prove.hex") -WorkingDirectory $Root -NoNewWindow -Wait -PassThru
if ($p.ExitCode -ne 0) { throw "gen1 http-prove compile exit $($p.ExitCode)" }
Convert-HexToExe $proveHex $proveExe
$peProveOut = & $proveExe
$peProveCode = $LASTEXITCODE
Write-Output $peProveOut
Write-Output "http_prove_pe_exit $peProveCode"
if ($peProveCode -ne 0) { throw "pe http-prove exit $peProveCode" }
$hostN = ($hostProve | Out-String).Trim() -replace "`r`n", "`n"
$peN = ($peProveOut | Out-String).Trim() -replace "`r`n", "`n"
if ($hostN -cne $peN) { throw "http-prove host vs PE stdout differ" }
Write-Output "http_prove_host_pe_identical"

$guestHex = Join-Path $Data "guest-http.hex"
$guestExe = Join-Path $Data "guest-http.exe"
if (Test-Path $guestHex) { Remove-Item -Force $guestHex }
$gp = Start-Process -FilePath $gen1 -ArgumentList @("data/guest-http.vire", "data/guest-http.hex") -WorkingDirectory $Root -NoNewWindow -Wait -PassThru
if ($gp.ExitCode -ne 0) { throw "gen1 guest-http compile exit $($gp.ExitCode)" }
Convert-HexToExe $guestHex $guestExe

function Send-RawBytes([int]$Port, [byte[]]$Payload, [int]$WaitMs = 3000) {
    $client = New-Object System.Net.Sockets.TcpClient
    $client.ReceiveTimeout = $WaitMs
    $client.SendTimeout = $WaitMs
    $client.Connect("127.0.0.1", $Port)
    $stream = $client.GetStream()
    $stream.Write($Payload, 0, $Payload.Length)
    $buf = New-Object byte[] 8192
    $n = 0
    try { $n = $stream.Read($buf, 0, $buf.Length) } catch { $n = 0 }
    $client.Close()
    if ($n -le 0) { return ,[byte[]]@() }
    $out = New-Object byte[] $n
    [Array]::Copy($buf, $out, $n)
    return ,$out
}

function Convert-BytesToAscii([byte[]]$Bytes) {
    if ($null -eq $Bytes -or $Bytes.Length -eq 0) { return "" }
    $chars = New-Object char[] $Bytes.Length
    for ($i = 0; $i -lt $Bytes.Length; $i++) {
        $b = $Bytes[$i]
        $chars[$i] = [char]$(if ($b -ge 32 -and $b -le 126) { $b } else { 46 })
    }
    return New-Object string (,$chars)
}

$routes = @(
    @{ Name = "health"; Req = "GET /health HTTP/1.1`r`nHost: 127.0.0.1`r`n`r`n" },
    @{ Name = "api_health"; Req = "GET /api/health HTTP/1.1`r`nHost: 127.0.0.1`r`n`r`n" },
    @{ Name = "user_id"; Req = "GET /api/users/42 HTTP/1.1`r`nHost: 127.0.0.1`r`n`r`n" },
    @{ Name = "search_q"; Req = "GET /api/search?q=hello%20world HTTP/1.1`r`nHost: 127.0.0.1`r`n`r`n" },
    @{ Name = "ping"; Req = "GET /api/ping HTTP/1.1`r`nHost: 127.0.0.1`r`n`r`n" },
    @{ Name = "info"; Req = "GET /info HTTP/1.1`r`nHost: 127.0.0.1`r`n`r`n" },
    @{ Name = "cors"; Req = "GET /api/cors?origin=https%3A%2F%2Fex.test HTTP/1.1`r`nHost: 127.0.0.1`r`n`r`n" },
    @{ Name = "echo"; Req = "POST /api/echo HTTP/1.1`r`nHost: 127.0.0.1`r`nContent-Length: 3`r`n`r`nxyz" },
    @{ Name = "login"; Req = "POST /api/login HTTP/1.1`r`nHost: 127.0.0.1`r`nContent-Length: 0`r`n`r`n" },
    @{ Name = "secure"; Req = "GET /api/secure?token=demo HTTP/1.1`r`nHost: 127.0.0.1`r`n`r`n" },
    @{ Name = "who"; Req = "GET /api/who?cookie=sid%3Dabc HTTP/1.1`r`nHost: 127.0.0.1`r`n`r`n" }
)

function Collect-Routes([int]$Port, [string]$Label) {
    $map = @{}
    foreach ($r in $routes) {
        $bytes = [System.Text.Encoding]::ASCII.GetBytes($r.Req)
        $resp = Send-RawBytes $Port $bytes
        $ascii = Convert-BytesToAscii $resp
        $hex = ([System.BitConverter]::ToString($resp) -replace "-", "")
        Write-Output ("route_{0}_{1}_len {2}" -f $Label, $r.Name, $resp.Length)
        Write-Output ("route_{0}_{1}_ascii {2}" -f $Label, $r.Name, $ascii)
        $map[$r.Name] = $hex
    }
    return $map
}

function Start-ListenProc([string]$FilePath, [string[]]$ArgumentList, [string]$OutFile, [string]$ErrFile) {
    if (Test-Path $OutFile) { Remove-Item -Force $OutFile }
    if (Test-Path $ErrFile) { Remove-Item -Force $ErrFile }
    $start = @{
        FilePath = $FilePath
        WorkingDirectory = $Root
        NoNewWindow = $true
        PassThru = $true
        RedirectStandardOutput = $OutFile
        RedirectStandardError = $ErrFile
    }
    if ($ArgumentList -and $ArgumentList.Count -gt 0) { $start.ArgumentList = $ArgumentList }
    return Start-Process @start
}

function Wait-Listen([System.Diagnostics.Process]$Proc, [string]$OutFile, [int]$WantPort) {
    $deadline = (Get-Date).AddSeconds(30)
    while ((Get-Date) -lt $deadline) {
        if (Test-Path $OutFile) {
            $txt = Get-Content -Raw $OutFile
            if ($txt -match "listening on 127.0.0.1:(\d+)") {
                $got = [int]$Matches[1]
                if ($WantPort -gt 0 -and $got -ne $WantPort) { throw "wanted port $WantPort got $got" }
                return $got
            }
        }
        if ($Proc.HasExited) { throw "listener exited $($Proc.ExitCode) early $(Get-Content -Raw $OutFile)" }
        Start-Sleep -Milliseconds 100
    }
    throw "did not print listening port"
}

$hostOut = Join-Path $Data "guest-http-host.out.txt"
$hostErr = Join-Path $Data "guest-http-host.err.txt"
$hostProc = Start-ListenProc "dotnet" @("exec", $VireDll, "guest-http.vire") $hostOut $hostErr
try {
    $hostPort = Wait-Listen $hostProc $hostOut 18081
    Write-Output "host_listen 127.0.0.1:$hostPort"
    $hostMap = Collect-Routes $hostPort "host"
    $badLen = [System.Text.Encoding]::ASCII.GetBytes("POST /api/echo HTTP/1.1`r`nHost: x`r`nContent-Length: +3`r`n`r`nxyz")
    $clte = [System.Text.Encoding]::ASCII.GetBytes("POST /api/echo HTTP/1.1`r`nHost: x`r`nTransfer-Encoding: chunked`r`nContent-Length: 5`r`n`r`nhello")
    $huge = "GET / HTTP/1.1`r`nHost: x`r`n"
    $pad = "X: " + ("y" * 240) + "`r`n"
    while ($huge.Length + $pad.Length -le 16384) { $huge += $pad }
    if ($huge.Length -lt 16384) { $huge += "Z" * (16384 - $huge.Length) }
    $hugeBytes = [System.Text.Encoding]::ASCII.GetBytes($huge)
    $hBad = Convert-BytesToAscii (Send-RawBytes $hostPort $badLen)
    $hClte = Convert-BytesToAscii (Send-RawBytes $hostPort $clte)
    $hHuge = Convert-BytesToAscii (Send-RawBytes $hostPort $hugeBytes)
    Write-Output "adversary_host_bad_length $hBad"
    Write-Output "adversary_host_cl_te $hClte"
    Write-Output "adversary_host_oversize $hHuge"
    if ($hBad -notmatch "^HTTP/1.1 400 ") { throw "host bad length not 400" }
    if ($hClte -notmatch "^HTTP/1.1 400 ") { throw "host CL+TE not 400" }
    if ($hHuge -notmatch "^HTTP/1.1 400 ") { throw "host oversize not 400" }
} finally {
    try { $hostProc.Kill() } catch { }
    try { $hostProc.WaitForExit(5000) } catch { }
}

Start-Sleep -Milliseconds 400
$peOut = Join-Path $Data "guest-http-pe.out.txt"
$peErr = Join-Path $Data "guest-http-pe.err.txt"
$peProc = Start-ListenProc $guestExe @() $peOut $peErr
try {
    $pePort = Wait-Listen $peProc $peOut 18081
    Write-Output "pe_listen 127.0.0.1:$pePort"
    $peMap = Collect-Routes $pePort "pe"
    $badLen = [System.Text.Encoding]::ASCII.GetBytes("POST /api/echo HTTP/1.1`r`nHost: x`r`nContent-Length: +3`r`n`r`nxyz")
    $clte = [System.Text.Encoding]::ASCII.GetBytes("POST /api/echo HTTP/1.1`r`nHost: x`r`nTransfer-Encoding: chunked`r`nContent-Length: 5`r`n`r`nhello")
    $huge = "GET / HTTP/1.1`r`nHost: x`r`n"
    $pad = "X: " + ("y" * 240) + "`r`n"
    while ($huge.Length + $pad.Length -le 16384) { $huge += $pad }
    if ($huge.Length -lt 16384) { $huge += "Z" * (16384 - $huge.Length) }
    $hugeBytes = [System.Text.Encoding]::ASCII.GetBytes($huge)
    $pBad = Convert-BytesToAscii (Send-RawBytes $pePort $badLen)
    $pClte = Convert-BytesToAscii (Send-RawBytes $pePort $clte)
    $pHuge = Convert-BytesToAscii (Send-RawBytes $pePort $hugeBytes)
    Write-Output "adversary_pe_bad_length $pBad"
    Write-Output "adversary_pe_cl_te $pClte"
    Write-Output "adversary_pe_oversize $pHuge"
    if ($pBad -notmatch "^HTTP/1.1 400 ") { throw "pe bad length not 400" }
    if ($pClte -notmatch "^HTTP/1.1 400 ") { throw "pe CL+TE not 400" }
    if ($pHuge -notmatch "^HTTP/1.1 400 ") { throw "pe oversize not 400" }
    foreach ($r in $routes) {
        if ($hostMap[$r.Name] -cne $peMap[$r.Name]) {
            throw ("raw response differ {0} host={1} pe={2}" -f $r.Name, $hostMap[$r.Name], $peMap[$r.Name])
        }
        Write-Output ("route_diff_{0} identical" -f $r.Name)
    }
} finally {
    try { $peProc.Kill() } catch { }
}

Write-Output ("PASS_AFTER at {0} host and gen1 PE HTTP framework routes identical; adversarial 400" -f $AfterSha)
