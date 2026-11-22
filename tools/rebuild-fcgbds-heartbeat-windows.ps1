# Windows PE proof for fcgbds-go heartbeat JSON sessionId.
# CouchStation only. Do not touch Defender.
$ErrorActionPreference = "Stop"
$Root = Split-Path -Parent $PSScriptRoot
Set-Location -LiteralPath $Root
. (Join-Path $PSScriptRoot "native-host-info.ps1")
$env:VIRE_HEADLESS = "1"
Remove-Item Env:VIRE_BUDGET -ErrorAction SilentlyContinue
$Data = Join-Path $Root "data"
$VireDll = Join-Path $Root "bin\Release\net10.0\vire.dll"
$gen1 = Join-Path $Data "gen1.exe"
if (-not (Test-Path $gen1)) { throw "missing data/gen1.exe; run native-selfhost-handoff.ps1 on Windows first" }

function Convert-HexToExe([string]$HexPath, [string]$ExePath) {
    $hex = [System.IO.File]::ReadAllText($HexPath).Trim()
    $bytes = New-Object byte[] ($hex.Length / 2)
    for ($i = 0; $i -lt $bytes.Length; $i++) {
        $bytes[$i] = [Convert]::ToByte($hex.Substring($i * 2, 2), 16)
    }
    [System.IO.File]::WriteAllBytes($ExePath, $bytes)
}

function Compile-Guest([string]$Src, [string]$Stem) {
    $vire = Get-Content -Raw -LiteralPath $Src
    $vire = $vire.Replace("listen with 18080", "listen with 0")
    $outSrc = Join-Path $Data "$Stem.vire"
    Set-Content -LiteralPath $outSrc -Value $vire -NoNewline
    $hex = Join-Path $Data "$Stem.hex"
    $exe = Join-Path $Data "$Stem.exe"
    if (Test-Path $hex) { Remove-Item -Force $hex }
    $p = Start-Process -FilePath $gen1 -ArgumentList @("data/$Stem.vire", "data/$Stem.hex") -WorkingDirectory $Root -NoNewWindow -PassThru
    $code = Get-ChildExitCode $p
    if ($code -ne 0) { throw "gen1 $Stem compile exit $code" }
    Convert-HexToExe $hex $exe
    return $exe
}

function Read-Http([int]$Port, [string]$Method, [string]$Path, [string]$Send) {
    $payload = if ($null -eq $Send) { [byte[]]@() } else { [System.Text.Encoding]::UTF8.GetBytes($Send) }
    $sb = New-Object System.Text.StringBuilder
    [void]$sb.Append("$Method $Path HTTP/1.1`r`nHost: 127.0.0.1`r`nConnection: close`r`n")
    if ($Method -eq "POST") {
        [void]$sb.Append("Content-Type: application/json`r`nContent-Length: $($payload.Length)`r`n")
    }
    [void]$sb.Append("`r`n")
    $head = [System.Text.Encoding]::ASCII.GetBytes($sb.ToString())
    $tcp = New-Object System.Net.Sockets.TcpClient
    $tcp.Connect("127.0.0.1", $Port)
    $stream = $tcp.GetStream()
    $stream.Write($head, 0, $head.Length)
    if ($payload.Length -gt 0) { $stream.Write($payload, 0, $payload.Length) }
    $ms = New-Object System.IO.MemoryStream
    $buf = New-Object byte[] 4096
    try {
        while (($n = $stream.Read($buf, 0, $buf.Length)) -gt 0) { $ms.Write($buf, 0, $n) }
    } catch {
        if ($ms.Length -eq 0 -and -not (Test-VireRstException $_.Exception)) { throw }
    }
    $tcp.Close()
    $text = [System.Text.Encoding]::UTF8.GetString($ms.ToArray())
    $split = $text.IndexOf("`r`n`r`n")
    if ($split -lt 0) { throw "missing headers $text" }
    $start = $text.Substring(0, $split)
    $body = $text.Substring($split + 4)
    $status = [int]($start.Split(" ")[1])
    return @{ Status = $status; Body = $body }
}

function Assert-Heartbeat([int]$Port, $Cases, [string]$Label) {
    foreach ($c in $Cases) {
        $got = Read-Http $Port $c.method $c.path $c.body
        if ($got.Status -ne [int]$c.status) { throw "$Label $($c.name) status $($got.Status) want $($c.status) body $($got.Body)" }
        $json = $got.Body | ConvertFrom-Json
        foreach ($prop in $c.body_fields.PSObject.Properties) {
            $name = $prop.Name
            $want = $prop.Value
            if ($want -is [bool] -or "$want" -eq "True" -or "$want" -eq "False") {
                $gv = [bool]$json.$name
                $wv = [bool]$want
                if ($gv -ne $wv) { throw "$Label $($c.name) field $name=$gv want $wv" }
            } elseif ($want -is [string]) {
                if ("$($json.$name)" -ne "$want") { throw "$Label $($c.name) field $name=$($json.$name) want $want" }
            }
        }
        Write-Host "case $Label $($c.name) status $($got.Status)"
    }
}

New-Item -ItemType Directory -Force -Path $Data | Out-Null
Copy-Item (Join-Path $Root "tests/rebuild/guests/fcgbds-heartbeat.vire") (Join-Path $Data "fcgbds-heartbeat.vire") -Force
Copy-Item (Join-Path $Root "tests/rebuild/guests/fcgbds-heartbeat-fail.vire") (Join-Path $Data "fcgbds-heartbeat-fail.vire") -Force

$contract = Get-Content -Raw (Join-Path $Root "tests/rebuild/contracts/fcgbds-heartbeat.json") | ConvertFrom-Json
$exe = Compile-Guest (Join-Path $Data "fcgbds-heartbeat.vire") "fcgbds-heartbeat"
$failExe = Compile-Guest (Join-Path $Data "fcgbds-heartbeat-fail.vire") "fcgbds-heartbeat-fail"
$pe = [System.IO.File]::ReadAllBytes($exe)
if ($pe[0] -ne 0x4d -or $pe[1] -ne 0x5a) { throw "heartbeat PE missing MZ" }

$hostProc = Start-VireProcess -FilePath "dotnet" -ArgumentList @("exec", $VireDll, "data/fcgbds-heartbeat.vire") -WorkingDirectory $Root
try {
    $hport = Get-ListenPort $hostProc
    Assert-Heartbeat $hport $contract.cases "host"
} finally {
    try { if (-not $hostProc.HasExited) { $hostProc.Kill() } } catch { }
}

$natProc = Start-VireProcess -FilePath $exe -WorkingDirectory $Root
try {
    $nport = Get-ListenPort $natProc
    Assert-Heartbeat $nport $contract.cases "pe"
} finally {
    try { if (-not $natProc.HasExited) { $natProc.Kill() } } catch { }
}

$failProc = Start-VireProcess -FilePath $failExe -WorkingDirectory $Root
try {
    $fport = Get-ListenPort $failProc
    $ok = $contract.cases | Where-Object { $_.name -eq "post_json_session_ok" } | Select-Object -First 1
    $got = Read-Http $fport $ok.method $ok.path $ok.body
    if ($got.Status -eq 200) { throw "FAIL_BEFORE fail guest accepted session" }
    Write-Host "FAIL_BEFORE heartbeat-fail status $($got.Status)"
} finally {
    try { if (-not $failProc.HasExited) { $failProc.Kill() } } catch { }
}

Write-Host "HOST_NATIVE_MATCH fcgbds-heartbeat"
Write-Host "PASS_AFTER replay tests/rebuild/contracts/fcgbds-heartbeat.json host vs PE"
