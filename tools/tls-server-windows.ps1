# Host SslStream TLS listener proof for CouchStation.
# Self-signed certs generated at run time. Loopback 127.0.0.1 only.
# Caps unchanged. Native PE tls_listen stays fail-closed until SChannel.
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
$BaseSha = "5c1f89adb5952f6c72037edbc8a856c3fd03bfdf"
$AfterSha = (git rev-parse HEAD).Trim()
Write-Output "fail_before_sha $BaseSha"
Write-Output "pass_after_sha $AfterSha"

git cat-file -e "$BaseSha^{commit}" 2>$null
if ($LASTEXITCODE -ne 0) {
    git fetch --depth 1 origin $BaseSha
}
$oldTls = (& git -C $Root show "${BaseSha}:src/rt-tls.vire") -join "`n"
if ($oldTls -notmatch "native tls_listen is fail-closed") {
    throw "FAIL_BEFORE expected fail-closed tls_listen at $BaseSha"
}
Write-Output "FAIL_BEFORE at $BaseSha native tls_listen fail-closed"

Add-Type -AssemblyName System.Security
$certPath = Join-Path $Data "tls-health-cert.pem"
$keyPath = Join-Path $Data "tls-health-key.pem"
Add-Type -TypeDefinition @"
using System;
using System.IO;
using System.Net;
using System.Security.Cryptography;
using System.Security.Cryptography.X509Certificates;
public static class VireTlsCert {
    public static void Write(string certPath, string keyPath) {
        using (RSA rsa = RSA.Create(2048)) {
            CertificateRequest req = new CertificateRequest("CN=localhost", rsa, HashAlgorithmName.SHA256, RSASignaturePadding.Pkcs1);
            SubjectAlternativeNameBuilder san = new SubjectAlternativeNameBuilder();
            san.AddDnsName("localhost");
            san.AddIpAddress(IPAddress.Loopback);
            req.CertificateExtensions.Add(san.Build());
            using (X509Certificate2 cert = req.CreateSelfSigned(DateTimeOffset.UtcNow.AddHours(-1), DateTimeOffset.UtcNow.AddDays(1))) {
                File.WriteAllText(certPath, "-----BEGIN CERTIFICATE-----\n" + Convert.ToBase64String(cert.Export(X509ContentType.Cert), Base64FormattingOptions.InsertLineBreaks) + "\n-----END CERTIFICATE-----\n");
                File.WriteAllText(keyPath, "-----BEGIN RSA PRIVATE KEY-----\n" + Convert.ToBase64String(rsa.ExportRSAPrivateKey(), Base64FormattingOptions.InsertLineBreaks) + "\n-----END RSA PRIVATE KEY-----\n");
            }
        }
    }
}
"@
[VireTlsCert]::Write($certPath, $keyPath)

$src = Join-Path $Data "guest-health-tls.vire"
Copy-Item -Force (Join-Path $Root "guest-health-tls.vire") $src
$contract = Get-Content -Raw (Join-Path $Root "tests/rebuild/contracts/health.json")
if ($contract -notmatch '"service":\s*"fcgcpa"') { throw "health contract missing fcgcpa" }

$psi = New-Object System.Diagnostics.ProcessStartInfo
$psi.FileName = "dotnet"
$psi.Arguments = "exec `"$VireDll`" `"data/guest-health-tls.vire`""
$psi.WorkingDirectory = $Root
$psi.RedirectStandardOutput = $true
$psi.RedirectStandardError = $true
$psi.UseShellExecute = $false
$proc = [System.Diagnostics.Process]::Start($psi)
$line = $null
$deadline = [DateTime]::UtcNow.AddSeconds(15)
while ([DateTime]::UtcNow -lt $deadline) {
    if ($proc.HasExited) { throw "host tls_listen exited $($proc.ExitCode) $($proc.StandardError.ReadToEnd())" }
    if ($proc.StandardOutput.Peek() -ge 0) {
        $line = $proc.StandardOutput.ReadLine()
        if ($line -match "listening on 127.0.0.1:(\d+)") {
            $port = [int]$Matches[1]
            break
        }
    } else {
        Start-Sleep -Milliseconds 50
    }
}
if (-not $port) { throw "host did not print loopback listen port" }
Write-Output "tls_host_listen 127.0.0.1:$port"

Add-Type -TypeDefinition @"
using System;
using System.Net.Http;
using System.Net.Security;
using System.Security.Cryptography.X509Certificates;
public static class VireTlsGet {
    public static string Health(int port, string certPath) {
        X509Certificate2 expected = X509CertificateLoader.LoadCertificateFromFile(certPath);
        string want = expected.GetCertHashString();
        HttpClientHandler handler = new HttpClientHandler();
        handler.ServerCertificateCustomValidationCallback = (req, got, chain, errors) =>
            got != null && got.GetCertHashString() == want;
        using (HttpClient client = new HttpClient(handler)) {
            client.Timeout = TimeSpan.FromSeconds(10);
            return client.GetStringAsync("https://127.0.0.1:" + port + "/health").GetAwaiter().GetResult();
        }
    }
}
"@
$body = [VireTlsGet]::Health($port, $certPath)
Write-Output $body
if ($body -notmatch '"ok":true') { throw "health missing ok" }
if ($body -notmatch 'fcgcpa') { throw "health missing service" }
if ($body -notmatch '"payments":false') { throw "health payments must stay false" }
Write-Output "PASS_AFTER at $AfterSha host SslStream GET /health matches contract"
Write-Output "tls_server_windows ok"
try { $proc.Kill() } catch { }
