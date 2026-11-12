# Native Schannel HTTPS listen proof. Windows only. Throwaway CI PEM, never a user secret.
$ErrorActionPreference = "Stop"
$Root = Split-Path -Parent $PSScriptRoot
Set-Location -LiteralPath $Root
. (Join-Path $PSScriptRoot "native-host-info.ps1")
$env:VIRE_BUDGET = "5000000"
$env:VIRE_HEADLESS = "1"
$Data = Join-Path $Root "data"
$TlsDir = Join-Path $Data "tls-ci"
New-Item -ItemType Directory -Force -Path $TlsDir | Out-Null
$VireDll = Join-Path $Root "bin/Release/net10.0/vire.dll"
$gen1 = Join-Path $Data "gen1.exe"
if (-not (Test-Path $gen1)) { throw "missing gen1.exe; run native-selfhost-handoff.ps1 first" }

function Convert-HexToExe([string]$HexPath, [string]$ExePath) {
    $hex = [System.IO.File]::ReadAllText($HexPath).Trim()
    if ($hex.Length -eq 0 -or ($hex.Length % 2) -ne 0) { throw "bad hex $HexPath" }
    $bytes = New-Object byte[] ($hex.Length / 2)
    for ($i = 0; $i -lt $bytes.Length; $i++) {
        $bytes[$i] = [Convert]::ToByte($hex.Substring($i * 2, 2), 16)
    }
    [System.IO.File]::WriteAllBytes($ExePath, $bytes)
}

function Write-Pem([string]$Path, [string]$Kind, [byte[]]$Der) {
    $b64 = [Convert]::ToBase64String($Der, [Base64FormattingOptions]::InsertLineBreaks)
    $text = "-----BEGIN $Kind-----`r`n$b64`r`n-----END $Kind-----`r`n"
    [System.IO.File]::WriteAllText($Path, $text)
}

$cert = New-SelfSignedCertificate -Subject "CN=127.0.0.1" -DnsName "127.0.0.1" -CertStoreLocation "Cert:\CurrentUser\My" -NotAfter (Get-Date).AddDays(2) -KeyAlgorithm RSA -KeyLength 2048 -HashAlgorithm SHA256 -KeyExportPolicy Exportable
Write-Pem (Join-Path $TlsDir "cert.pem") "CERTIFICATE" $cert.Export([System.Security.Cryptography.X509Certificates.X509ContentType]::Cert)
$rsa = [System.Security.Cryptography.X509Certificates.RSACertificateExtensions]::GetRSAPrivateKey($cert)
Write-Pem (Join-Path $TlsDir "key.pem") "PRIVATE KEY" $rsa.ExportPkcs8PrivateKey()
$wrong = New-SelfSignedCertificate -Subject "CN=wrong.example" -DnsName "wrong.example" -CertStoreLocation "Cert:\CurrentUser\My" -NotAfter (Get-Date).AddDays(2) -KeyAlgorithm RSA -KeyLength 2048 -HashAlgorithm SHA256 -KeyExportPolicy Exportable
Write-Pem (Join-Path $TlsDir "wrong.pem") "CERTIFICATE" $wrong.Export([System.Security.Cryptography.X509Certificates.X509ContentType]::Cert)
Write-Output "tls_ci_cert throwaway self-signed CN=127.0.0.1 (not a user secret)"

$plain = Join-Path $Data "guest-health.exe"
if (-not (Test-Path $plain)) { throw "missing guest-health.exe from native-net-windows.ps1" }
$outFile = Join-Path $Data "https-fail-before.out.txt"
$errFile = Join-Path $Data "https-fail-before.err.txt"
if (Test-Path $outFile) { Remove-Item -Force $outFile }
if (Test-Path $errFile) { Remove-Item -Force $errFile }
$server = Start-Process -FilePath $plain -WorkingDirectory $Root -NoNewWindow -PassThru -RedirectStandardOutput $outFile -RedirectStandardError $errFile
$deadline = (Get-Date).AddSeconds(30)
$port = $null
while ((Get-Date) -lt $deadline) {
    if (Test-Path $outFile) {
        $txt = Get-Content -Raw $outFile
        if ($txt -match "listening on 127.0.0.1:(\d+)") { $port = [int]$Matches[1]; break }
    }
    if ($server.HasExited) { throw "fail-before health server exited $($server.ExitCode)" }
    Start-Sleep -Milliseconds 100
}
if (-not $port) { throw "fail-before did not print listening port" }
$failOut = Join-Path $Data "https-fail-before-curl.txt"
$failArgs = @("-sS", "-D", "-", "--max-time", "5", "https://127.0.0.1:$port/health")
$p = Start-Process -FilePath "curl.exe" -ArgumentList $failArgs -NoNewWindow -Wait -PassThru -RedirectStandardOutput $failOut -RedirectStandardError (Join-Path $Data "https-fail-before-curl.err.txt")
$failBody = if (Test-Path $failOut) { Get-Content -Raw $failOut } else { "" }
$failErr = Get-Content -Raw (Join-Path $Data "https-fail-before-curl.err.txt")
Write-Output ("FAIL_BEFORE https plaintext_port=" + $port + " curl_exit=" + $p.ExitCode)
Write-Output ("FAIL_BEFORE_curl_err " + (($failErr -replace '\s+', ' ').Trim()))
if ($p.ExitCode -eq 0) { throw "FAIL_BEFORE expected HTTPS to plaintext listen to fail" }
Write-Output "FAIL_BEFORE https to native PE failed as required (no TLS listen)"
try { $server.Kill() } catch { }

Copy-Item (Join-Path $Root "guest-health-https.vire") (Join-Path $Data "guest-health-https.vire") -Force
$hex = Join-Path $Data "guest-health-https.hex"
$exe = Join-Path $Data "guest-health-https.exe"
if (Test-Path $hex) { Remove-Item -Force $hex }
$cp = Start-Process -FilePath $gen1 -ArgumentList @("data/guest-health-https.vire", "data/guest-health-https.hex") -WorkingDirectory $Root -NoNewWindow -Wait -PassThru
if ($cp.ExitCode -ne 0) { throw "gen1 https compile exit $($cp.ExitCode)" }
Convert-HexToExe $hex $exe
$pe = [System.IO.File]::ReadAllBytes($exe)
$ascii = [System.Text.Encoding]::ASCII.GetString($pe)
if ($ascii -notmatch "secur32.dll") { throw "https PE missing secur32.dll" }
if ($ascii -notmatch "crypt32.dll") { throw "https PE missing crypt32.dll" }
if ($ascii -notmatch "ncrypt.dll") { throw "https PE missing ncrypt.dll" }
if ($ascii -notmatch "AcquireCredentialsHandleA") { throw "https PE missing AcquireCredentialsHandleA" }
if ($ascii -match "LoadLibraryA") { throw "https PE has LoadLibraryA" }
Write-Output "https_pe_iat secur32.dll crypt32.dll ncrypt.dll AcquireCredentialsHandleA (no LoadLibraryA)"

$hout = Join-Path $Data "https-server.out.txt"
$herr = Join-Path $Data "https-server.err.txt"
if (Test-Path $hout) { Remove-Item -Force $hout }
if (Test-Path $herr) { Remove-Item -Force $herr }
$hs = Start-Process -FilePath $exe -WorkingDirectory $Root -NoNewWindow -PassThru -RedirectStandardOutput $hout -RedirectStandardError $herr
$deadline = (Get-Date).AddSeconds(30)
$hport = $null
while ((Get-Date) -lt $deadline) {
    if (Test-Path $hout) {
        $txt = Get-Content -Raw $hout
        if ($txt -match "listening on 127.0.0.1:(\d+)") { $hport = [int]$Matches[1]; break }
    }
    if ($hs.HasExited) {
        Write-Output ("https_server_out " + (Get-Content -Raw $hout -ErrorAction SilentlyContinue))
        Write-Output ("https_server_err " + (Get-Content -Raw $herr -ErrorAction SilentlyContinue))
        throw "https server exited $($hs.ExitCode) early"
    }
    Start-Sleep -Milliseconds 100
}
if (-not $hport) { throw "https server did not print listening port" }
Write-Output "https_listen 127.0.0.1:$hport"
Start-Sleep -Milliseconds 400

$ca = Join-Path $TlsDir "cert.pem"
function Invoke-CurlHttps([string[]]$Extra, [string]$Url) {
    $out = Join-Path $Data ("curl-" + [Guid]::NewGuid().ToString("N") + ".txt")
    $err = "$out.err"
    $args = @("-sS", "-D", "-", "--max-time", "15", "--http1.1", "--cacert", $ca) + $Extra + @($Url)
    $proc = Start-Process -FilePath "curl.exe" -ArgumentList $args -NoNewWindow -Wait -PassThru -RedirectStandardOutput $out -RedirectStandardError $err
    return @{
        Code = $proc.ExitCode
        Out = $(if (Test-Path $out) { Get-Content -Raw $out } else { "" })
        Err = $(if (Test-Path $err) { Get-Content -Raw $err } else { "" })
    }
}

$want = '{"ok":true,"service":"fcgcpa","payments":false}'
$verbose = Join-Path $Data "https-curl-verbose.txt"
$vproc = Start-Process -FilePath "curl.exe" -ArgumentList @("-v", "-sS", "-D", "-", "--max-time", "15", "--http1.1", "--cacert", $ca, "https://127.0.0.1:$hport/health") -NoNewWindow -Wait -PassThru -RedirectStandardOutput (Join-Path $Data "https-health.body.txt") -RedirectStandardError $verbose
$vtext = Get-Content -Raw $verbose
$body = Get-Content -Raw (Join-Path $Data "https-health.body.txt")
Write-Output ("PASS_AFTER_https_curl_exit " + $vproc.ExitCode)
Write-Output ("PASS_AFTER_https_verbose " + (($vtext -replace '\s+', ' ').Trim()))
Write-Output ("PASS_AFTER_https_health " + (($body -replace '\s+', ' ').Trim()))
if ($vproc.ExitCode -ne 0) { throw "HTTPS GET /health failed" }
if ($body -notmatch "HTTP/1.1 200 ") { throw "https health status not 200" }
if ($body -notmatch [regex]::Escape($want)) { throw "https health body mismatch" }
if ($vtext -notmatch "TLS") { throw "verbose log missing TLS" }
if ($vtext -notmatch "127.0.0.1") { throw "verbose log missing 127.0.0.1 cert host" }
Write-Output "PASS_AFTER GET https://127.0.0.1:$hport/health 200 body $want"
if ($vtext -match "TLSv1\.3") { Write-Output "PASS_AFTER_tls_protocol TLS 1.3" }
elseif ($vtext -match "TLSv1\.2") { Write-Output "PASS_AFTER_tls_protocol TLS 1.2" }
else { Write-Output "PASS_AFTER_tls_protocol TLS (see verbose)" }

$api = Invoke-CurlHttps @() "https://127.0.0.1:$hport/api/health"
Write-Output ("PASS_AFTER_https_api " + (($api.Out -replace '\s+', ' ').Trim()))
if ($api.Code -ne 0) { throw "HTTPS GET /api/health failed" }
if ($api.Out -notmatch "HTTP/1.1 200 ") { throw "https api/health status not 200" }
if ($api.Out -notmatch [regex]::Escape($want)) { throw "https api/health body mismatch" }
Write-Output "PASS_AFTER GET https://127.0.0.1:$hport/api/health 200 body $want"

$badCa = Join-Path $TlsDir "wrong.pem"
$negOut = Join-Path $Data "https-neg-ca.txt"
$negErr = Join-Path $Data "https-neg-ca.err"
$neg = Start-Process -FilePath "curl.exe" -ArgumentList @("-sS", "--max-time", "8", "--cacert", $badCa, "https://127.0.0.1:$hport/health") -NoNewWindow -Wait -PassThru -RedirectStandardOutput $negOut -RedirectStandardError $negErr
$negErrText = Get-Content -Raw $negErr
Write-Output ("NEG_bad_cert curl_exit=" + $neg.ExitCode + " " + (($negErrText -replace '\s+', ' ').Trim()))
if ($neg.ExitCode -eq 0) { throw "bad-cert client was accepted" }

$hostNeg = Start-Process -FilePath "curl.exe" -ArgumentList @("-sS", "--max-time", "8", "--cacert", $ca, "--resolve", "localhost:${hport}:127.0.0.1", "https://localhost:$hport/health") -NoNewWindow -Wait -PassThru -RedirectStandardOutput (Join-Path $Data "https-neg-host.txt") -RedirectStandardError (Join-Path $Data "https-neg-host.err")
$hostErr = Get-Content -Raw (Join-Path $Data "https-neg-host.err")
Write-Output ("NEG_wrong_host curl_exit=" + $hostNeg.ExitCode + " " + (($hostErr -replace '\s+', ' ').Trim()))
if ($hostNeg.ExitCode -eq 0) { throw "wrong-host client was accepted" }
Write-Output "PASS_AFTER negative bad-cert and wrong-host rejected"

try { $hs.Kill() } catch { }
Write-Output "native https windows ok"
