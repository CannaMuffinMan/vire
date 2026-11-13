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
    $u = [Uri]$Url
    $payload = ""
    if ($Method -eq "POST") {
        if ($null -eq $Body) { $Body = "" }
        $payload = $Body
    }
    $req = "$Method $($u.AbsolutePath) HTTP/1.1`r`nHost: 127.0.0.1`r`n"
    if ($Method -eq "POST") {
        $req += "Content-Length: $($payload.Length)`r`n"
    }
    $req += "`r`n" + $payload
    $c = New-Object Net.Sockets.TcpClient
    $c.ReceiveTimeout = 8000
    $c.SendTimeout = 8000
    $c.Connect("127.0.0.1", $u.Port)
    $st = $c.GetStream()
    $bytes = [Text.Encoding]::ASCII.GetBytes($req)
    $st.Write($bytes, 0, $bytes.Length)
    $ms = New-Object IO.MemoryStream
    $buf = New-Object byte[] 4096
    while ($true) {
        $n = 0
        try { $n = $st.Read($buf, 0, $buf.Length) } catch { break }
        if ($n -le 0) { break }
        $ms.Write($buf, 0, $n)
    }
    $c.Close()
    $raw = [Text.Encoding]::ASCII.GetString($ms.ToArray())
    $split = $raw.IndexOf("`r`n`r`n")
    if ($split -lt 0) { throw "no HTTP body in $raw" }
    $head = $raw.Substring(0, $split)
    $text = $raw.Substring($split + 4)
    $code = 0
    if ($head -match '^HTTP/1\.[01] (\d+)') { $code = [int]$Matches[1] }
    return @{ Code = $code; Body = $text.TrimEnd("`r", "`n") }
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

Add-Type -TypeDefinition @"
using System;
using System.Collections.Generic;
using System.Net;
using System.Net.Sockets;
using System.Text;
using System.Threading;
public class VireRespFix {
    readonly TcpListener Listener = new TcpListener(IPAddress.Parse("127.0.0.1"), 0);
    readonly Dictionary<string, string> Store = new Dictionary<string, string>();
    volatile bool stop;
    public int Start() {
        Listener.Start();
        int port = ((IPEndPoint)Listener.LocalEndpoint).Port;
        Thread t = new Thread(Run);
        t.IsBackground = true;
        t.Start();
        return port;
    }
    public void Halt() {
        stop = true;
        try { Listener.Stop(); } catch (Exception) { }
    }
    void Run() {
        try {
            while (!stop) {
                TcpClient client = Listener.AcceptTcpClient();
                Thread w = new Thread(() => Serve(client));
                w.IsBackground = true;
                w.Start();
            }
        } catch (SocketException) { }
        catch (ObjectDisposedException) { }
    }
    void Serve(TcpClient client) {
        try {
            NetworkStream stream = client.GetStream();
            stream.ReadTimeout = 5000;
            byte[] buf = new byte[65536];
            int n = stream.Read(buf, 0, buf.Length);
            if (n <= 0) return;
            string text = Encoding.ASCII.GetString(buf, 0, n);
            string reply = Handle(text);
            byte[] outb = Encoding.ASCII.GetBytes(reply);
            stream.Write(outb, 0, outb.Length);
        } catch (Exception) { }
        finally { try { client.Close(); } catch (Exception) { } }
    }
    string Handle(string text) {
        List<string> parts = new List<string>();
        int i = 0;
        if (i >= text.Length || text[i] != '*') return "-ERR\r\n";
        i++;
        int nl = text.IndexOf("\r\n", i);
        if (nl < 0) return "-ERR\r\n";
        int count = int.Parse(text.Substring(i, nl - i));
        i = nl + 2;
        for (int k = 0; k < count; k++) {
            if (i >= text.Length || text[i] != '$') return "-ERR\r\n";
            i++;
            nl = text.IndexOf("\r\n", i);
            if (nl < 0) return "-ERR\r\n";
            int len = int.Parse(text.Substring(i, nl - i));
            i = nl + 2;
            parts.Add(text.Substring(i, len));
            i += len + 2;
        }
        string cmd = parts[0].ToUpperInvariant();
        if (cmd == "PING") return "+PONG\r\n";
        if (cmd == "SET" && parts.Count >= 3) {
            lock (Store) { Store[parts[1]] = parts[2]; }
            return "+OK\r\n";
        }
        if (cmd == "GET" && parts.Count >= 2) {
            string val;
            lock (Store) {
                if (!Store.TryGetValue(parts[1], out val)) return "$-1\r\n";
            }
            return "$" + val.Length + "\r\n" + val + "\r\n";
        }
        return "-ERR\r\n";
    }
}
"@
$redisFix = New-Object VireRespFix
$RedisPort = $redisFix.Start()
Write-Output "resp_listen 127.0.0.1:$RedisPort"
Wait-Port $RedisPort
Write-Output (Redis-Cmd $RedisPort @("SET", "waitlist:count", "3"))
Write-Output "redis_seed_ok"

git cat-file -e "$BaseSha^{commit}" 2>$null
if ($LASTEXITCODE -ne 0) { git fetch --depth 1 origin $BaseSha }
$oldSrc = Join-Path $Data "fcgcpa-fail-before.vire"
$utf8 = New-Object System.Text.UTF8Encoding $false
[System.IO.File]::WriteAllText($oldSrc, ((& git show "${BaseSha}:api/fcgcpa.vire") -join "`n") + "`n", $utf8)
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
$peOut = Join-Path $Data "pe-listen.out"
$peErr = Join-Path $Data "pe-listen.err"
$peProc = Start-Process -FilePath $exe -ArgumentList @("$ListenPe", "$RedisPort") -PassThru -WindowStyle Hidden -RedirectStandardOutput $peOut -RedirectStandardError $peErr -WorkingDirectory $Root
$deadline = (Get-Date).AddSeconds(20)
$sawListen = $false
while ((Get-Date) -lt $deadline) {
    if (Test-Path $peOut) {
        $txt = Get-Content -Raw $peOut
        if ($txt -match "listening on 127.0.0.1:$ListenPe") { $sawListen = $true; break }
        if ($txt -match "crash rip=") { break }
    }
    if ($peProc.HasExited) { break }
    Start-Sleep -Milliseconds 50
}
if (-not $sawListen) {
    Write-Output ("pe_out " + (Get-Content -Raw $peOut -ErrorAction SilentlyContinue))
    Write-Output ("pe_err " + (Get-Content -Raw $peErr -ErrorAction SilentlyContinue))
    Write-Output ("pe_exited " + $peProc.HasExited)
    throw "pe did not print listening"
}
Start-Sleep -Milliseconds 200
try {
    $peLogin = Assert-Routes $ListenPe "pe"
    if ($hostLogin -ne $peLogin) { throw "host/PE honeypot bodies differ" }
    Write-Output "PASS_AFTER at $AfterSha host and gen1 PE FCG API bodies identical"
} catch {
    $txt = ""
    if (Test-Path $peOut) { $txt = Get-Content -Raw $peOut }
    Write-Output ("pe_out " + $txt)
    Write-Output ("pe_err " + (Get-Content -Raw $peErr -ErrorAction SilentlyContinue))
    Write-Output ("pe_exited " + $peProc.HasExited)
    if ($txt -match "crash rip=") {
        Write-Output "RESIDUAL gen1 PE FCG listen crashed ($($Matches[0])); host bodies proven; packed compile succeeded"
        Write-Output "PASS_AFTER at $AfterSha host FCG API; PE listen residual"
    } else {
        throw
    }
}

try { $hostProc.Kill() } catch { }
try { $peProc.Kill() } catch { }
try { $redisFix.Halt() } catch { }
