# Native PE Postgres/Redis TLS through SChannel for CouchStation.
# Loopback 127.0.0.1 only. Throwaway test CA. Caps 32MB / 100000 / 5M.
# Linux agents cannot execute PE; this script is the Windows execute proof.
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
$FailBeforeSha = "1328b737d5d121cf5f898cb13e86a26d9f5f772f"
$AfterSha = (git rev-parse HEAD).Trim()
Write-Output "fail_before_sha $FailBeforeSha"
Write-Output "pass_after_sha $AfterSha"
Write-Output "pg_redis_tls_residual no SCRAM-SHA-256-PLUS no RESP3; PE execute is CouchStation-only"
Write-VireHostInfo

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

function Assert-PeSchannel([string]$HexPath, [string]$Need) {
    $hex = [IO.File]::ReadAllText($HexPath).Trim()
    $bytes = New-Object byte[] ($hex.Length / 2)
    for ($i = 0; $i -lt $bytes.Length; $i++) {
        $bytes[$i] = [Convert]::ToByte($hex.Substring($i * 2, 2), 16)
    }
    if ($bytes[0] -ne 0x4d -or $bytes[1] -ne 0x5a) { throw "$Need PE MZ missing" }
    $ascii = [Text.Encoding]::ASCII.GetString($bytes)
    if ($ascii -notmatch "secur32.dll") { throw "$Need missing secur32.dll" }
    if ($ascii -notmatch "crypt32.dll") { throw "$Need missing crypt32.dll" }
    if ($ascii -match "LoadLibraryA") { throw "$Need LoadLibraryA forbidden" }
    if ($ascii -match "GetProcAddress") { throw "$Need GetProcAddress forbidden" }
    if ($ascii -match "libssl.so.3") { throw "$Need must not import OpenSSL" }
    if ($ascii -notmatch "InitializeSecurityContextA") { throw "$Need missing ISC" }
    Write-Output "$Need pe_schannel_iat_ok"
}

git cat-file -e "$FailBeforeSha^{commit}" 2>$null
if ($LASTEXITCODE -ne 0) { git fetch --depth 1 origin $FailBeforeSha }
$peTls = (& git -C $Root show "${FailBeforeSha}:src/rt-tls-pe.vire") -join "`n"
if ($peTls -match "rt_tls_wrap") { throw "FAIL_BEFORE expected no rt_tls_wrap at $FailBeforeSha" }
Write-Output "FAIL_BEFORE at $FailBeforeSha PE SChannel guest has no rt_tls_wrap (pg TLS compile: map has no key rt_tls_wrap)"

$utf8nb = New-Object System.Text.UTF8Encoding $false
[IO.File]::WriteAllText((Join-Path $Data "pg-redis-wrap.vire"), "define main`n  tls_wrap with 1, `"localhost`", `"`", 1`nend`n", $utf8nb)
Remove-Item Env:VIRE_BUDGET -ErrorAction SilentlyContinue
$code = Invoke-Vire "compile-native.vire" "data/pg-redis-wrap.vire" "data/pg-redis-wrap.hex" "pe"
if ($code -ne 0) { throw "PE tls_wrap compile failed" }
$env:VIRE_BUDGET = "5000000"
Assert-PeSchannel (Join-Path $Data "pg-redis-wrap.hex") "tls_wrap"

$pgLib = [IO.File]::ReadAllText((Join-Path $Root "src/rt-pg.vire"))
$pgGuest = [IO.File]::ReadAllText((Join-Path $Root "tests/native/pg-tls.vire"))
$pgGuest = $pgGuest.Replace("PORT_PLACEHOLDER", "55433").Replace("PGUSER_PLACEHOLDER", "vire").Replace("PGDB_PLACEHOLDER", "vire").Replace("PGSECRET_PLACEHOLDER", "x")
[IO.File]::WriteAllText((Join-Path $Data "pg-tls-pe.vire"), $pgLib + "`n" + $pgGuest, $utf8nb)
Remove-Item Env:VIRE_BUDGET -ErrorAction SilentlyContinue
$code = Invoke-Vire "compile-native.vire" "data/pg-tls-pe.vire" "data/pg-tls-pe.hex" "pe"
if ($code -ne 0) { throw "PE pg_open_ssl compile failed" }
$env:VIRE_BUDGET = "5000000"
Assert-PeSchannel (Join-Path $Data "pg-tls-pe.hex") "pg_tls"

$rdLib = [IO.File]::ReadAllText((Join-Path $Root "src/rt-redis.vire"))
$rdGuest = [IO.File]::ReadAllText((Join-Path $Root "tests/native/redis-tls.vire"))
$rdGuest = $rdGuest.Replace("SECRET_PLACEHOLDER", "x").Replace("TLS_PORT_PLACEHOLDER", "16380")
[IO.File]::WriteAllText((Join-Path $Data "redis-tls-pe.vire"), $rdLib + "`n" + $rdGuest, $utf8nb)
Remove-Item Env:VIRE_BUDGET -ErrorAction SilentlyContinue
$code = Invoke-Vire "compile-native.vire" "data/redis-tls-pe.vire" "data/redis-tls-pe.hex" "pe"
if ($code -ne 0) { throw "PE rediss compile failed" }
$env:VIRE_BUDGET = "5000000"
Assert-PeSchannel (Join-Path $Data "redis-tls-pe.hex") "redis_tls"

if (-not $IsWindows) {
    Write-Output "pe_execute_skipped linux agent cannot run PE; CouchStation must run this script"
    Write-Output "PASS_AFTER compile-only: wrap/pg/redis PE import SChannel"
    Write-Output "pg_redis_tls_windows compile_ok"
    exit 0
}

Add-Type -AssemblyName System.Security
Add-Type -TypeDefinition @"
using System;
using System.IO;
using System.Net;
using System.Net.Security;
using System.Net.Sockets;
using System.Security.Authentication;
using System.Security.Cryptography;
using System.Security.Cryptography.X509Certificates;
using System.Text;
using System.Threading;
public static class VirePgRedisTlsFix {
    public static X509Certificate2 WritePfx(string pfxPath, string cerPath, string password) {
        using (RSA rsa = RSA.Create(2048)) {
            CertificateRequest req = new CertificateRequest("CN=localhost", rsa, HashAlgorithmName.SHA256, RSASignaturePadding.Pkcs1);
            SubjectAlternativeNameBuilder san = new SubjectAlternativeNameBuilder();
            san.AddDnsName("localhost");
            san.AddIpAddress(IPAddress.Loopback);
            req.CertificateExtensions.Add(san.Build());
            X509Certificate2 cert = req.CreateSelfSigned(DateTimeOffset.UtcNow.AddDays(-1), DateTimeOffset.UtcNow.AddDays(7));
            File.WriteAllBytes(pfxPath, cert.Export(X509ContentType.Pfx, password));
            File.WriteAllText(cerPath, "-----BEGIN CERTIFICATE-----`n" + Convert.ToBase64String(cert.RawData, Base64FormattingOptions.InsertLineBreaks) + "`n-----END CERTIFICATE-----`n");
            return new X509Certificate2(File.ReadAllBytes(pfxPath), password, X509KeyStorageFlags.Exportable);
        }
    }
    public static TcpListener Listen(X509Certificate2 cert, out int port) {
        TcpListener l = new TcpListener(IPAddress.Loopback, 0);
        l.Start();
        port = ((IPEndPoint)l.LocalEndpoint).Port;
        Thread t = new Thread(() => {
            try {
                while (true) {
                    TcpClient c = l.AcceptTcpClient();
                    Thread inner = new Thread(() => Serve(c, cert));
                    inner.IsBackground = true;
                    inner.Start();
                }
            } catch { }
        });
        t.IsBackground = true;
        t.Start();
        return l;
    }
    static void Serve(TcpClient c, X509Certificate2 cert) {
        try {
            using (c)
            using (SslStream s = new SslStream(c.GetStream(), false)) {
                s.AuthenticateAsServer(new SslServerAuthenticationOptions {
                    ServerCertificate = cert,
                    EnabledSslProtocols = SslProtocols.Tls12 | SslProtocols.Tls13
                });
                byte[] buf = new byte[256];
                int n = s.Read(buf, 0, buf.Length);
                byte[] pong = Encoding.ASCII.GetBytes("PONG");
                s.Write(pong, 0, pong.Length);
            }
        } catch { }
    }
}
"@

$pfx = Join-Path $Data "pg-redis-tls.pfx"
$cer = Join-Path $Data "pg-redis-tls.pem"
$cert = [VirePgRedisTlsFix]::WritePfx($pfx, $cer, "x")
$port = 0
$listener = [VirePgRedisTlsFix]::Listen($cert, [ref]$port)
Write-Output "tls_loopback_listen 127.0.0.1:$port"

$wrapRun = @"
define main
  let h be connect with "127.0.0.1", $port
  tls_wrap with h, "localhost", "data/pg-redis-tls.pem", 1
  tls_send with h, "PING"
  let got be tls_recv with h, 16
  tls_close with h
  say got
end
"@
[IO.File]::WriteAllText((Join-Path $Data "pg-redis-wrap-run.vire"), $wrapRun, $utf8nb)
Remove-Item Env:VIRE_BUDGET -ErrorAction SilentlyContinue
$code = Invoke-Vire "compile-native.vire" "data/pg-redis-wrap-run.vire" "data/pg-redis-wrap-run.hex" "pe"
if ($code -ne 0) { throw "PE wrap-run compile failed" }
$env:VIRE_BUDGET = "5000000"
Convert-HexToExe (Join-Path $Data "pg-redis-wrap-run.hex") (Join-Path $Data "pg-redis-wrap-run.exe")
$wrapOut = & (Join-Path $Data "pg-redis-wrap-run.exe")
Write-Output $wrapOut
if ("$wrapOut" -notmatch "PONG") { throw "PE tls_wrap ping missing PONG" }
Write-Output "pe_tls_wrap_ping_ok"

$bad = @"
define main
  let h be connect with "127.0.0.1", $port
  tls_wrap with h, "evil.example", "data/pg-redis-tls.pem", 1
end
"@
[IO.File]::WriteAllText((Join-Path $Data "pg-redis-wrap-mismatch.vire"), $bad, $utf8nb)
Remove-Item Env:VIRE_BUDGET -ErrorAction SilentlyContinue
$code = Invoke-Vire "compile-native.vire" "data/pg-redis-wrap-mismatch.vire" "data/pg-redis-wrap-mismatch.hex" "pe"
Convert-HexToExe (Join-Path $Data "pg-redis-wrap-mismatch.hex") (Join-Path $Data "pg-redis-wrap-mismatch.exe")
$env:VIRE_BUDGET = "5000000"
$mm = & (Join-Path $Data "pg-redis-wrap-mismatch.exe") 2>&1 | Out-String
if ($LASTEXITCODE -eq 0) { throw "hostname mismatch must fail closed" }
Write-Output "pe_hostname_mismatch_fail_closed"

$ut = @"
define main
  let h be connect with "127.0.0.1", $port
  tls_wrap with h, "localhost", "", 1
end
"@
[IO.File]::WriteAllText((Join-Path $Data "pg-redis-wrap-untrusted.vire"), $ut, $utf8nb)
Remove-Item Env:VIRE_BUDGET -ErrorAction SilentlyContinue
$code = Invoke-Vire "compile-native.vire" "data/pg-redis-wrap-untrusted.vire" "data/pg-redis-wrap-untrusted.hex" "pe"
Convert-HexToExe (Join-Path $Data "pg-redis-wrap-untrusted.hex") (Join-Path $Data "pg-redis-wrap-untrusted.exe")
$env:VIRE_BUDGET = "5000000"
$uo = & (Join-Path $Data "pg-redis-wrap-untrusted.exe") 2>&1 | Out-String
if ($LASTEXITCODE -eq 0) { throw "untrusted CA must fail closed" }
Write-Output "pe_untrusted_ca_fail_closed"

try { $listener.Stop() } catch { }
Write-Output "PASS_AFTER at $AfterSha PE wrap/pg/redis import SChannel; wrap ping; hostname mismatch and untrusted CA fail closed"
Write-Output "pg_redis_tls_windows ok"
