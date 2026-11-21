# Native PE SChannel TLS proof for CouchStation.
# Loopback 127.0.0.1 only. Test CA / PFX generated here. Caps unchanged.
# Does not claim success unless this script runs on Windows.
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
$BaseSha = "1c9ae02f8372d607ea6fad1666459a3b1d8bb6ff"
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

git cat-file -e "$BaseSha^{commit}" 2>$null
if ($LASTEXITCODE -ne 0) {
    git fetch --depth 1 origin $BaseSha
}
$oldTls = (& git -C $Root show "${BaseSha}:src/rt-tls.vire") -join "`n"
if ($oldTls -notmatch "native tls on windows pe uses Schannel") {
    throw "FAIL_BEFORE expected PE refuse at $BaseSha"
}
if ($oldTls -notmatch "emitTlsPeRefuse") {
    throw "FAIL_BEFORE expected emitTlsPeRefuse at $BaseSha"
}
Write-Output "FAIL_BEFORE at $BaseSha native PE tls_* fail-closed (emitTlsPeRefuse)"

$ProofDll = Get-VireProofDll
$pfx = Join-Path $Data "tls-health.pfx"
$cer = Join-Path $Data "tls-health-cert.pem"
& dotnet exec $ProofDll write-pfx $pfx $cer ""
if ($LASTEXITCODE -ne 0) { throw "write-pfx failed" }

$src = @"
define route with method, path, body
  if path == "/health"
    return "{\"ok\":true,\"service\":\"fcgcpa\",\"payments\":false}"
  end
  return "{\"error\":\"not found\"}"
end
define main
  tls_listen with 0, "data/tls-health.pfx", ""
end
"@
Set-Content -Path (Join-Path $Data "guest-health-schan.vire") -Value $src
Remove-Item Env:VIRE_BUDGET -ErrorAction SilentlyContinue
$code = Invoke-Vire "compile-native.vire" "data/guest-health-schan.vire" "data/guest-health-schan.hex" "pe"
if ($code -ne 0) { throw "PE tls_listen compile failed" }
$env:VIRE_BUDGET = "5000000"
Convert-HexToExe (Join-Path $Data "guest-health-schan.hex") (Join-Path $Data "guest-health-schan.exe")
$ascii = [Text.Encoding]::ASCII.GetString([IO.File]::ReadAllBytes((Join-Path $Data "guest-health-schan.exe")))
if ($ascii -notmatch "secur32.dll") { throw "PE missing secur32.dll" }
if ($ascii -notmatch "AcquireCredentialsHandleA") { throw "PE missing AcquireCredentialsHandleA" }

$psi = New-Object System.Diagnostics.ProcessStartInfo
$psi.FileName = (Join-Path $Data "guest-health-schan.exe")
$psi.WorkingDirectory = $Root
$psi.RedirectStandardOutput = $true
$psi.RedirectStandardError = $true
$psi.UseShellExecute = $false
$proc = [System.Diagnostics.Process]::Start($psi)
$line = $null
$deadline = [DateTime]::UtcNow.AddSeconds(20)
while ([DateTime]::UtcNow -lt $deadline) {
    if ($proc.HasExited) { throw "PE tls_listen exited $($proc.ExitCode) $($proc.StandardError.ReadToEnd())" }
    if ($proc.StandardOutput.Peek() -ge 0) {
        $line = $proc.StandardOutput.ReadLine()
        if ($line -match "listening on 127.0.0.1:(\d+)") {
            $port = [int]$Matches[1]
            break
        }
    } else { Start-Sleep -Milliseconds 50 }
}
if (-not $port) { throw "PE did not print loopback listen port" }
Write-Output "tls_pe_listen 127.0.0.1:$port"
$contract = Get-Content -Raw (Join-Path $Root "tests/rebuild/contracts/health.json")
if ($contract -notmatch '"service":\s*"fcgcpa"') { throw "health contract missing fcgcpa" }
$body = & dotnet exec $ProofDll https-health $port $cer
if ($LASTEXITCODE -ne 0) { throw "https-health failed" }
Write-Output $body
if ($body -notmatch '"ok":true') { throw "health missing ok" }
if ($body -notmatch 'fcgcpa') { throw "health missing service" }
if ($body -notmatch '"payments":false') { throw "health payments must stay false" }
Write-Output "pe_health_contract_ok"
& dotnet exec $ProofDll tls10-fail $port
if ($LASTEXITCODE -ne 0) { throw "tls10-fail failed" }
Write-Output "pe_tls10_fail_closed"

$cli = @"
define main
  let h be tls_connect with "127.0.0.1", $port, "localhost", "data/tls-health-cert.pem"
  tls_send with h, "GET /health HTTP/1.1``r``nHost: localhost``r``nConnection: close``r``n``r``n"
  let got be tls_recv with h, 400
  tls_close with h
  say got
end
"@
Set-Content -Path (Join-Path $Data "tls-pe-client.vire") -Value $cli.Replace('`r','\r').Replace('`n','\n')
# Guest source uses real CR? Use explicit escapes in vire string:
Set-Content -Path (Join-Path $Data "tls-pe-client.vire") -Value @"
define main
  let h be tls_connect with "127.0.0.1", $port, "localhost", "data/tls-health-cert.pem"
  tls_send with h, "GET /health HTTP/1.1`r`nHost: localhost`r`nConnection: close`r`n`r`n"
  let got be tls_recv with h, 400
  tls_close with h
  say got
end
"@
Remove-Item Env:VIRE_BUDGET -ErrorAction SilentlyContinue
$code = Invoke-Vire "compile-native.vire" "data/tls-pe-client.vire" "data/tls-pe-client.hex" "pe"
if ($code -ne 0) { throw "PE tls_connect compile failed" }
$env:VIRE_BUDGET = "5000000"
Convert-HexToExe (Join-Path $Data "tls-pe-client.hex") (Join-Path $Data "tls-pe-client.exe")
$clientOut = & (Join-Path $Data "tls-pe-client.exe")
Write-Output $clientOut
if ("$clientOut" -notmatch 'fcgcpa') { throw "PE client HTTPS GET missing contract body" }
Write-Output "pe_client_https_get_ok"

$badName = @"
define main
  tls_connect with "127.0.0.1", $port, "not-localhost", "data/tls-health-cert.pem"
end
"@
Set-Content -Path (Join-Path $Data "tls-pe-mismatch.vire") -Value $badName
Remove-Item Env:VIRE_BUDGET -ErrorAction SilentlyContinue
$code = Invoke-Vire "compile-native.vire" "data/tls-pe-mismatch.vire" "data/tls-pe-mismatch.hex" "pe"
Convert-HexToExe (Join-Path $Data "tls-pe-mismatch.hex") (Join-Path $Data "tls-pe-mismatch.exe")
$env:VIRE_BUDGET = "5000000"
$mismatch = & (Join-Path $Data "tls-pe-mismatch.exe") 2>&1 | Out-String
if ($LASTEXITCODE -eq 0) { throw "hostname mismatch must fail closed" }
Write-Output "pe_hostname_mismatch_fail_closed"

$untrusted = @"
define main
  tls_connect with "127.0.0.1", $port, "localhost", ""
end
"@
Set-Content -Path (Join-Path $Data "tls-pe-untrusted.vire") -Value $untrusted
Remove-Item Env:VIRE_BUDGET -ErrorAction SilentlyContinue
$code = Invoke-Vire "compile-native.vire" "data/tls-pe-untrusted.vire" "data/tls-pe-untrusted.hex" "pe"
Convert-HexToExe (Join-Path $Data "tls-pe-untrusted.hex") (Join-Path $Data "tls-pe-untrusted.exe")
$env:VIRE_BUDGET = "5000000"
$ut = & (Join-Path $Data "tls-pe-untrusted.exe") 2>&1 | Out-String
if ($LASTEXITCODE -eq 0) { throw "untrusted CA must fail closed" }
Write-Output "pe_untrusted_ca_fail_closed"

try { $proc.Kill() } catch { }
Write-Output "PASS_AFTER at $AfterSha PE SChannel client GET /health; hostname mismatch and untrusted CA fail closed; TLS1.0 refused; contract matches"
Write-Output "tls_schannel_windows ok"
Write-Output "WINDOWS_PROOF ran on CouchStation"
