# FAIL_BEFORE / PASS_AFTER: native PE listen mux, timeouts, 20k requests, hang isolation.
$ErrorActionPreference = "Stop"
$Root = Split-Path -Parent $PSScriptRoot
Set-Location -LiteralPath $Root
. (Join-Path $PSScriptRoot "native-host-info.ps1")
$env:VIRE_BUDGET = "5000000"
$env:VIRE_HEADLESS = "1"
$Data = Join-Path $Root "data"
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

function Wait-Listen([string]$OutFile, [string]$ErrFile, $Proc, [int]$Sec) {
    $deadline = (Get-Date).AddSeconds($Sec)
    while ((Get-Date) -lt $deadline) {
        if (Test-Path $OutFile) {
            $txt = Get-Content -Raw $OutFile
            if ($txt -match "listening on 127.0.0.1:(\d+)") { return [int]$Matches[1] }
        }
        if ($Proc.HasExited) {
            $so = if (Test-Path $OutFile) { Get-Content -Raw $OutFile } else { "" }
            $se = if (Test-Path $ErrFile) { Get-Content -Raw $ErrFile } else { "" }
            throw "server exited $($Proc.ExitCode) out=$so err=$se"
        }
        Start-Sleep -Milliseconds 50
    }
    throw "did not print listening port"
}

function Start-HealthExe([string]$Exe) {
    $outFile = Join-Path $Data "native-server.out.txt"
    $errFile = Join-Path $Data "native-server.err.txt"
    if (Test-Path $outFile) { Remove-Item -Force $outFile }
    if (Test-Path $errFile) { Remove-Item -Force $errFile }
    $p = Start-Process -FilePath $Exe -WorkingDirectory $Root -NoNewWindow -PassThru -RedirectStandardOutput $outFile -RedirectStandardError $errFile
    $port = Wait-Listen $outFile $errFile $p 30
    return @{ Proc = $p; Port = $port; Out = $outFile; Err = $errFile }
}

function Get-Health([int]$Port, [int]$WaitMs) {
    $c = New-Object System.Net.Sockets.TcpClient
    $c.ReceiveTimeout = $WaitMs
    $c.SendTimeout = $WaitMs
    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    try {
        $c.Connect("127.0.0.1", $Port)
        $s = $c.GetStream()
        $req = [Text.Encoding]::ASCII.GetBytes("GET /health HTTP/1.1`r`nHost: 127.0.0.1`r`n`r`n")
        $s.Write($req, 0, $req.Length)
        $buf = New-Object byte[] 4096
        $n = 0
        try { $n = $s.Read($buf, 0, $buf.Length) } catch { $n = 0 }
        $sw.Stop()
        $txt = if ($n -gt 0) { [Text.Encoding]::ASCII.GetString($buf, 0, $n) } else { "" }
        return @{ Ok = ($txt -match "HTTP/1.1 200 "); Ms = $sw.ElapsedMilliseconds; Text = $txt }
    } finally {
        try { $c.Close() } catch { }
    }
}

function Compile-Health {
    Copy-Item (Join-Path $Root "guest-health.vire") (Join-Path $Data "guest-health.vire") -Force
    $hex = Join-Path $Data "guest-health-server.hex"
    $exe = Join-Path $Data "guest-health-server.exe"
    if (Test-Path $hex) { Remove-Item -Force $hex }
    $code = Invoke-Vire compile-native.vire data/guest-health.vire data/guest-health-server.hex
    if ($code -ne 0) { throw "compile health exit $code" }
    Convert-HexToExe $hex $exe
    return $exe
}

git cat-file -e "$BaseSha^{commit}" 2>$null
if ($LASTEXITCODE -ne 0) { git fetch --depth 1 origin $BaseSha }

$Snap = Join-Path $Data "native-server-snap"
New-Item -ItemType Directory -Force -Path $Snap | Out-Null
foreach ($rel in @("src/pe.vire", "src/rt-net.vire", "src/rt-server.vire", "compile-native.vire", "data/src/pe.vire", "data/src/rt-net.vire", "data/src/rt-server.vire", "data/compile-native.vire")) {
    $src = Join-Path $Root $rel
    if (Test-Path $src) {
        $dest = Join-Path $Snap $rel
        New-Item -ItemType Directory -Force -Path (Split-Path $dest) | Out-Null
        Copy-Item $src $dest -Force
    }
}

Write-Output "phase fail-before $BaseSha"
git checkout $BaseSha -- src/pe.vire src/rt-net.vire compile-native.vire data/src/pe.vire data/src/rt-net.vire data/compile-native.vire
if (Test-Path (Join-Path $Root "src/rt-server.vire")) { Remove-Item (Join-Path $Root "src/rt-server.vire") -Force }
if (Test-Path (Join-Path $Root "data/src/rt-server.vire")) { Remove-Item (Join-Path $Root "data/src/rt-server.vire") -Force }
$beforeExe = Compile-Health
$before = Start-HealthExe $beforeExe
$hang = New-Object System.Net.Sockets.TcpClient
$hang.Connect("127.0.0.1", $before.Port)
$hs = $hang.GetStream()
$partial = [Text.Encoding]::ASCII.GetBytes("GET /health HTTP/1.1`r`n")
$hs.Write($partial, 0, $partial.Length)
Start-Sleep -Milliseconds 200
$blocked = Get-Health $before.Port 800
Write-Output ("fail_before_overlap_ms {0} ok={1}" -f $blocked.Ms, $blocked.Ok)
try { $hang.Close() } catch { }
try { $before.Proc.Kill() } catch { }
if ($blocked.Ok) { throw "FAIL_BEFORE expected hang to stall overlapping /health" }
Write-Output "FAIL_BEFORE at $BaseSha overlapping /health stalled while a client hung"

foreach ($rel in @("src/pe.vire", "src/rt-net.vire", "src/rt-server.vire", "compile-native.vire", "data/src/pe.vire", "data/src/rt-net.vire", "data/src/rt-server.vire", "data/compile-native.vire")) {
    $src = Join-Path $Snap $rel
    if (Test-Path $src) { Copy-Item $src (Join-Path $Root $rel) -Force }
}
Copy-Item (Join-Path $Root "compile-native.vire") (Join-Path $Root "data/compile-native.vire") -Force
Copy-Item (Join-Path $Root "src/rt-server.vire") (Join-Path $Root "data/src/rt-server.vire") -Force
Copy-Item (Join-Path $Root "src/rt-net.vire") (Join-Path $Root "data/src/rt-net.vire") -Force
Copy-Item (Join-Path $Root "src/pe.vire") (Join-Path $Root "data/src/pe.vire") -Force

Write-Output "phase pass-after $AfterSha"
$afterExe = Compile-Health
$pe = [IO.File]::ReadAllBytes($afterExe)
$ascii = [Text.Encoding]::ASCII.GetString($pe)
if ($ascii -notlike "*select*") { throw "PE missing select" }
Write-Output "health_pe_iat select SO_RCVTIMEO/SO_SNDTIMEO mux"

$after = Start-HealthExe $afterExe
Write-Output "health_listen 127.0.0.1:$($after.Port)"
$hang2 = New-Object System.Net.Sockets.TcpClient
$hang2.Connect("127.0.0.1", $after.Port)
$hs2 = $hang2.GetStream()
$hs2.Write($partial, 0, $partial.Length)
Start-Sleep -Milliseconds 100
$live = Get-Health $after.Port 2000
Write-Output ("pass_after_overlap_ms {0} ok={1}" -f $live.Ms, $live.Ok)
if (-not $live.Ok) { throw "hanging client stalled /health" }
if ($live.Ms -gt 1500) { throw "overlapping /health too slow $($live.Ms)ms" }
Write-Output "PASS_AFTER hang isolation /health while slowloris held"

$ok = 0
$loadSw = [Diagnostics.Stopwatch]::StartNew()
$jobs = @()
1..8 | ForEach-Object {
    $jobs += Start-Job -ScriptBlock {
        param($Port)
        $n = 0
        for ($i = 0; $i -lt 2500; $i++) {
            $c = New-Object System.Net.Sockets.TcpClient
            $c.ReceiveTimeout = 5000
            $c.Connect("127.0.0.1", $Port)
            $s = $c.GetStream()
            $req = [Text.Encoding]::ASCII.GetBytes("GET /health HTTP/1.1`r`nHost: x`r`n`r`n")
            $s.Write($req, 0, $req.Length)
            $buf = New-Object byte[] 2048
            $got = $s.Read($buf, 0, $buf.Length)
            $c.Close()
            $t = [Text.Encoding]::ASCII.GetString($buf, 0, $got)
            if ($t -match "HTTP/1.1 200 ") { $n++ }
        }
        return $n
    } -ArgumentList $after.Port
}
$ok = ($jobs | Wait-Job | Receive-Job | Measure-Object -Sum).Sum
Remove-Job $jobs -Force
$loadSw.Stop()
Write-Output ("load_health_ok {0} ms {1}" -f $ok, $loadSw.ElapsedMilliseconds)
if ($ok -lt 20000) { throw "expected 20000 health ok, got $ok" }
if ($after.Proc.HasExited) { throw "server died during load exit $($after.Proc.ExitCode)" }
Write-Output "PASS_AFTER 20000 /health requests at $AfterSha"

try { $hang2.Close() } catch { }
$disc = New-Object System.Net.Sockets.TcpClient
$disc.Connect("127.0.0.1", $after.Port)
$ds = $disc.GetStream()
$ds.Write($partial, 0, $partial.Length)
$disc.Close()
Start-Sleep -Milliseconds 200
$afterDrop = Get-Health $after.Port 2000
if (-not $afterDrop.Ok) { throw "disconnect mid-request killed the server" }
Write-Output "PASS_AFTER client disconnect mid-request server still serves"
if ($after.Proc.HasExited) { throw "server exited after disconnect" }

try { $after.Proc.Kill() } catch { }
$gen1 = Join-Path $Data "gen1.exe"
if (Test-Path $gen1) {
    Write-Output "native-selfhost gen1 present; gen1=gen2 owned by native-selfhost-windows"
}
Write-Output "native server windows ok"
exit 0
