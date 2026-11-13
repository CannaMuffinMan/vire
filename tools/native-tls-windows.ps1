# Fail-before / pass-after: native guest outbound HTTPS via Schannel.
# connect stays loopback-only. fetch/post are an explicit needTls opt-in.
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
$BaseSha = "5b10ea5fa5eea46859f17a52b36037d9d088c01d"
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
        $out = & dotnet exec $VireDll @Args 2>&1 | Out-String
        $code = $LASTEXITCODE
        if ($null -ne $out) { Write-Host $out.TrimEnd() }
        if ($null -eq $code) { return @{ Code = 0; Out = $out } }
        return @{ Code = [int]$code; Out = $out }
    } finally {
        if ($savedBudget) { $env:VIRE_BUDGET = $savedBudget }
    }
}

git cat-file -e "$BaseSha^{commit}" 2>$null
if ($LASTEXITCODE -ne 0) {
    git fetch --depth 1 origin $BaseSha
}
$oldLines = @(& git -C $Root show "${BaseSha}:compile-native.vire")
$oldNative = ($oldLines | ForEach-Object { $_ }) -join "`n"
if ($oldNative -match 'nm == "fetch"') { throw "base compile-native already has fetch" }
if ($oldNative -notmatch 'define main') { throw "fail-before snapshot missing define main" }
$oldSrc = Join-Path $Root "compile-native-fail-before.vire"
$utf8 = New-Object System.Text.UTF8Encoding $false
[System.IO.File]::WriteAllText($oldSrc, $oldNative + "`n", $utf8)
Set-Content -Path (Join-Path $Data "tls-fail-before.vire") -Value "define main`n  fetch with `"https://example.com/`"`nend`n"
try {
    $beforeOut = & dotnet exec $VireDll --compiler "compile-native-fail-before.vire" "data/tls-fail-before.vire" "data/tls-fail-before.hex" 2>&1 | Out-String
    $beforeCode = $LASTEXITCODE
} finally {
    if (Test-Path $oldSrc) { Remove-Item -Force $oldSrc }
}
$env:VIRE_BUDGET = "5000000"
Write-Output $beforeOut.TrimEnd()
Write-Output "fail_before_compile_exit $beforeCode"
if ($beforeCode -eq 0) { throw "fail-before compile unexpectedly succeeded" }
if ($beforeOut -notmatch "there is no definition named fetch") {
    throw "fail-before missing unavailable fetch"
}
Write-Output "FAIL_BEFORE at $BaseSha showing fetch is unavailable"

function Compile-And-RunPe([string]$SrcRel, [string]$Name) {
    $hexRel = "data/$Name.hex"
    $hexPath = Join-Path $Root $hexRel
    if (Test-Path $hexPath) { Remove-Item -Force $hexPath }
    $compile = Invoke-Vire compile-native.vire $SrcRel $hexRel
    if ($compile.Code -ne 0) { throw "compile-native $Name exit $($compile.Code)" }
    $exe = Join-Path $Data "$Name.exe"
    Convert-HexToExe $hexPath $exe
    return $exe
}

Copy-Item (Join-Path $Root "tests/native/https-get.vire") (Join-Path $Data "https-get.vire") -Force
Write-Output "tls_host_get_start"
$sw = [System.Diagnostics.Stopwatch]::StartNew()
$hostGet = Invoke-Vire "data/https-get.vire"
$sw.Stop()
Write-Output "tls_host_get_sec $($sw.Elapsed.TotalSeconds.ToString('0.000'))"
Write-Output "tls_host_get_exit $($hostGet.Code)"
if ($hostGet.Code -ne 0) { throw "host https-get exit $($hostGet.Code)" }
$hostGetNorm = (($hostGet.Out | Out-String) -replace '\r', '').Trim()
if ($hostGetNorm -notmatch "(?m)^status 200$") { throw "host missing status 200" }
if ($hostGetNorm -notmatch "(?m)^[0-9a-f]{64}$") { throw "host missing body hash" }
Write-Output "host_get_hash_line $(([regex]::Match($hostGetNorm, '(?m)^[0-9a-f]{64}$')).Value)"

$getExe = Compile-And-RunPe "data/https-get.vire" "https-get"
$peBytes = [System.IO.File]::ReadAllBytes($getExe)
$ascii = [System.Text.Encoding]::ASCII.GetString($peBytes)
if ($ascii -notmatch "secur32.dll") { throw "PE missing secur32.dll" }
if ($ascii -notmatch "InitializeSecurityContextA") { throw "PE missing InitializeSecurityContextA" }
if ($ascii -notmatch "DecryptMessage") { throw "PE missing DecryptMessage" }
if ($ascii -notmatch "getaddrinfo") { throw "PE missing getaddrinfo" }
$sw = [System.Diagnostics.Stopwatch]::StartNew()
$peGetOut = & $getExe 2>&1 | Out-String
$peGetCode = $LASTEXITCODE
$sw.Stop()
Write-Output $peGetOut.TrimEnd()
Write-Output "tls_pe_get_sec $($sw.Elapsed.TotalSeconds.ToString('0.000'))"
Write-Output "tls_pe_get_exit $peGetCode"
if ($peGetCode -ne 0) { throw "https GET PE exit $peGetCode" }
$peGetNorm = ($peGetOut -replace '\r', '').Trim()
if ($hostGetNorm -ne $peGetNorm) {
    Write-Output "HOST_PE_MISMATCH"
    Write-Output "HOST $hostGetNorm"
    Write-Output "PE $peGetNorm"
    throw "host interpreter and gen1 PE GET stdout differ"
}
Write-Output "PASS_AFTER at $AfterSha host and gen1 PE GET status 200 + body hash identical"

Copy-Item (Join-Path $Root "tests/native/https-post.vire") (Join-Path $Data "https-post.vire") -Force
$hostPost = Invoke-Vire "data/https-post.vire"
$postExe = Compile-And-RunPe "data/https-post.vire" "https-post"
$pePostOut = & $postExe 2>&1 | Out-String
$pePostCode = $LASTEXITCODE
$hostPostNorm = (($hostPost.Out | Out-String) -replace '\r', '').Trim()
$pePostNorm = ($pePostOut -replace '\r', '').Trim()
Write-Output "tls_host_post_exit $($hostPost.Code)"
Write-Output "tls_pe_post_exit $pePostCode"
if ($hostPost.Code -eq 0) {
    if ($pePostCode -ne 0) { throw "host POST succeeded but PE failed" }
    if ($hostPostNorm -ne $pePostNorm) { throw "host/PE POST stdout differ" }
    if ($hostPostNorm -notmatch "(?m)^status 200$") { throw "POST missing status 200" }
    Write-Output "tls_post_200_hash_match"
} else {
    if ($pePostCode -eq 0) { throw "host POST failed but PE succeeded" }
    Write-Output "tls_post_fail_closed host=$($hostPost.Code) pe=$pePostCode"
    Write-Output "HOST_POST $hostPostNorm"
    Write-Output "PE_POST $pePostNorm"
}

Copy-Item (Join-Path $Root "tests/native/https-badcert.vire") (Join-Path $Data "https-badcert.vire") -Force
$hostBad = Invoke-Vire "data/https-badcert.vire"
$badExe = Compile-And-RunPe "data/https-badcert.vire" "https-badcert"
$peBadOut = & $badExe 2>&1 | Out-String
$peBadCode = $LASTEXITCODE
Write-Output "tls_host_badcert_exit $($hostBad.Code)"
Write-Output "tls_pe_badcert_exit $peBadCode"
Write-Output ((($hostBad.Out | Out-String) -replace '\r', '').Trim())
Write-Output $peBadOut.TrimEnd()
if ($hostBad.Code -eq 0) { throw "host expired.badssl.com unexpectedly succeeded" }
if ($peBadCode -eq 0) { throw "PE expired.badssl.com unexpectedly succeeded" }
if ((($hostBad.Out | Out-String) + $peBadOut) -match "opened") { throw "bad-cert path printed opened" }
Write-Output "tls_badcert_fail_closed"

Copy-Item (Join-Path $Root "tests/native/https-ssrf.vire") (Join-Path $Data "https-ssrf.vire") -Force
$hostSsrf = Invoke-Vire "data/https-ssrf.vire"
$ssrfExe = Compile-And-RunPe "data/https-ssrf.vire" "https-ssrf"
$peSsrfOut = & $ssrfExe 2>&1 | Out-String
$peSsrfCode = $LASTEXITCODE
Write-Output "tls_host_ssrf_exit $($hostSsrf.Code)"
Write-Output "tls_pe_ssrf_exit $peSsrfCode"
if ($hostSsrf.Code -eq 0 -or $peSsrfCode -eq 0) { throw "loopback fetch must fail closed" }
$hostSsrfN = (($hostSsrf.Out | Out-String) -replace '\r', '').Trim()
$peSsrfN = ($peSsrfOut -replace '\r', '').Trim()
if ($hostSsrfN -notmatch "fetch stays off this machine") { throw "host missing private-network sentence for loopback fetch" }
if ($peSsrfN -notmatch "fetch stays off this machine") { throw "PE missing private-network sentence for loopback fetch" }
Write-Output "tls_loopback_not_widened"

# connect guest still has no secur32
Set-Content -Path (Join-Path $Data "tls-connect-only.vire") -Value "define main`n  close with (connect with `"127.0.0.1`", 9)`nend`n"
$cnExe = Compile-And-RunPe "data/tls-connect-only.vire" "tls-connect-only"
$cnAscii = [System.Text.Encoding]::ASCII.GetString([System.IO.File]::ReadAllBytes($cnExe))
if ($cnAscii -match "secur32.dll") { throw "connect-only PE silently gained secur32" }
if ($cnAscii -match "getaddrinfo") { throw "connect-only PE silently gained getaddrinfo" }
Write-Output "tls_connect_still_loopback_iat"

Write-Output "PASS_AFTER at $AfterSha native tls windows ok"
