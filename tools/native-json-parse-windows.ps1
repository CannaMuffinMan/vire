$ErrorActionPreference = "Stop"
$Root = Split-Path -Parent $PSScriptRoot
Set-Location -LiteralPath $Root
. (Join-Path $PSScriptRoot "native-host-info.ps1")
Remove-Item Env:VIRE_BUDGET -ErrorAction SilentlyContinue
$env:VIRE_HEADLESS = "1"
$Data = Join-Path $Root "data"
$VireDll = Join-Path $Root "bin/Release/net10.0/vire.dll"
if (-not (Test-Path $VireDll)) { throw "missing $VireDll" }
Remove-Item Env:FCG_API_TOKEN -ErrorAction SilentlyContinue
Remove-Item Env:FCG_BLOCK_TOKEN -ErrorAction SilentlyContinue
$FailBlob = "6e969fc2e9c94f537bad69b948e56670096c2a1b"
$curBlob = (Get-Content -Raw (Join-Path $Root "src/rt-net-json-blob.txt")).Trim()
git cat-file -e "$FailBlob^{commit}" 2>$null
if ($LASTEXITCODE -eq 0) {
    $oldBlob = (git show "${FailBlob}:src/rt-net-json-blob.txt").Trim()
    if ($curBlob -eq $oldBlob) { throw "FAIL_BEFORE json blob still $FailBlob" }
}
Write-Host "FAIL_BEFORE json blob moved past $FailBlob"

function Convert-HexToExe([string]$HexPath, [string]$ExePath) {
    $hex = [System.IO.File]::ReadAllText($HexPath).Trim()
    if ($hex.Length -eq 0 -or ($hex.Length % 2) -ne 0) { throw "bad hex $HexPath" }
    $bytes = New-Object byte[] ($hex.Length / 2)
    for ($i = 0; $i -lt $bytes.Length; $i++) {
        $bytes[$i] = [Convert]::ToByte($hex.Substring($i * 2, 2), 16)
    }
    [System.IO.File]::WriteAllBytes($ExePath, $bytes)
}

function Compile-Native([string]$Src, [string]$Stem) {
    Copy-Item -LiteralPath $Src -Destination (Join-Path $Data "$Stem.vire") -Force
    $hex = Join-Path $Data "$Stem.hex"
    $exe = Join-Path $Data "$Stem.exe"
    if (Test-Path $hex) { Remove-Item -Force $hex }
    & dotnet exec $VireDll --compiler compile-native.vire "data/$Stem.vire" "data/$Stem.hex" pe
    if ($LASTEXITCODE -ne 0) { throw "compile-native $Stem exit $LASTEXITCODE" }
    Convert-HexToExe $hex $exe
    return $exe
}

Write-Host "CouchStation PE json/parse"
$parseExe = Compile-Native (Join-Path $Root "tests/fuzz/findings/native-pe-json-map.vire") "json-map-pe"
$parseOut = & $parseExe
if ($LASTEXITCODE -ne 0) { throw "json-map PE exit $LASTEXITCODE" }
$norm = (($parseOut | Out-String) -replace '\s', '').Trim()
if ($norm -ne '{"a":2}') { throw "json-map PE got $parseOut" }
Write-Host "json_map_pe_ok $parseOut"

$arrSrc = Join-Path $Data "parse-round.vire"
Set-Content -LiteralPath $arrSrc -Value "define main`n  say (json with (parse with `"[1,true,null]`"))`nend`n"
$arrExe = Compile-Native $arrSrc "parse-round-pe"
$arrOut = & $arrExe
if ($LASTEXITCODE -ne 0) { throw "parse-round PE exit $LASTEXITCODE" }
$arrNorm = (($arrOut | Out-String) -replace '\s', '').Trim()
if ($arrNorm -ne '[1,true,null]') { throw "parse-round PE got $arrOut" }
Write-Host "parse_round_pe_ok $arrOut"

$listenExe = Compile-Native (Join-Path $Root "tests/rebuild/guests/listen-parse.vire") "listen-parse-pe"
$outFile = Join-Path $Data "listen-parse-pe.out"
$proc = Start-Process -FilePath $listenExe -WorkingDirectory $Root -NoNewWindow -RedirectStandardOutput $outFile -PassThru
Start-Sleep -Milliseconds 400
$lout = Get-Content -Raw $outFile
if ($lout -notmatch "listening on 127.0.0.1:(\d+)") { if (-not $proc.HasExited) { Stop-Process -ErrorAction SilentlyContinue -Id $proc.Id -Force }; throw "listen-parse PE did not listen" }
$port = [int]$Matches[1]
try {
    $got = Invoke-VireHttpRequest -Port $port -Method "POST" -Path "/p" -Send '{"a":1}'
    if ("$($got.Body)" -notmatch '"a":\s*1') { throw "listen-parse POST PE $($got.Body)" }
    Write-Host "listen_parse_pe_ok"
} finally {
    if ($proc -and -not $proc.HasExited) { Stop-Process -ErrorAction SilentlyContinue -Id $proc.Id -Force }
}
Write-Host "PASS_AFTER Windows PE json/parse and listen+parse completed on this CouchStation. Linux is not PE proof."
