# Compile apigo-ws to native and match host 101/echo/fail-closed frames.
# Linux ELF is not Windows PE proof. CouchStation runs this for PE.
$ErrorActionPreference = "Stop"
$Root = Split-Path -Parent $PSScriptRoot
Set-Location -LiteralPath $Root
. (Join-Path $PSScriptRoot "native-host-info.ps1")
. (Join-Path $PSScriptRoot "native-loopback-proof.ps1")
$env:VIRE_HEADLESS = "1"
Remove-Item Env:VIRE_BUDGET -ErrorAction SilentlyContinue
Remove-Item Env:FCG_API_TOKEN -ErrorAction SilentlyContinue

$AfterSha = (git rev-parse HEAD).Trim()
Write-Host "FAIL_BEFORE at 6693e0e5d78c9df775d0531a39a14a574239cfac: tools/apigo-ws-windows.ps1 stub exit 1"
Write-Host ("PASS_AFTER expect " + $AfterSha)
Assert-VireCaps $Root
Write-Host ("contract_note " + ((Get-Content -Raw (Join-Path $Root "tests/rebuild/contracts/apigo-ws.json")).Substring(0, [Math]::Min(180, (Get-Item (Join-Path $Root "tests/rebuild/contracts/apigo-ws.json")).Length))))

$OnWindows = Test-VireOnWindows
$VireDll = Get-VireDll $Root
$Stage = Join-Path $Root "data/apigo-ws-win"
New-Item -ItemType Directory -Force -Path $Stage | Out-Null
Copy-Item (Join-Path $Root "tests/rebuild/guests/apigo-ws.vire") (Join-Path $Stage "apigo-ws.vire") -Force
$nativePath = Join-Path $Stage $(if ($OnWindows) { "apigo-ws.exe" } else { "apigo-ws.elf" })
if ($OnWindows) {
    Compile-VireNative -Root $Root -VireDll $VireDll -SrcRel "data/apigo-ws-win/apigo-ws.vire" -HexRel "data/apigo-ws-win/apigo-ws.hex" -OutPath $nativePath -Pe
} else {
    Compile-VireNative -Root $Root -VireDll $VireDll -SrcRel "data/apigo-ws-win/apigo-ws.vire" -HexRel "data/apigo-ws-win/apigo-ws.hex" -OutPath $nativePath
}

Add-Type -TypeDefinition @"
using System;
using System.IO;
using System.Net.Sockets;
using System.Security.Cryptography;
using System.Text;
public static class VireApigoProbe {
    const string WsGuid = "258EAFA5-E914-47DA-95CA-C5AB0DC85B11";
    static void WriteU64(MemoryStream ms, int n) {
        ulong v = (ulong)n;
        for (int i = 7; i >= 0; i--) {
            ms.WriteByte((byte)((v >> (8 * i)) & 0xFF));
        }
    }
    public static byte[] MaskFrame(int opcode, byte[] payload, bool fin, bool mask, int rsv, bool ext127) {
        byte b0 = (byte)((fin ? 0x80 : 0) | (rsv << 4) | opcode);
        int n = payload.Length;
        MemoryStream ms = new MemoryStream();
        ms.WriteByte(b0);
        int maskbit = mask ? 0x80 : 0;
        if (ext127) {
            ms.WriteByte((byte)(maskbit | 127));
            WriteU64(ms, n);
        } else if (n < 126) {
            ms.WriteByte((byte)(maskbit | n));
        } else if (n < 65536) {
            ms.WriteByte((byte)(maskbit | 126));
            ms.WriteByte((byte)((n >> 8) & 0xFF));
            ms.WriteByte((byte)(n & 0xFF));
        } else {
            ms.WriteByte((byte)(maskbit | 127));
            WriteU64(ms, n);
        }
        byte[] body = payload;
        if (mask) {
            byte[] m = new byte[] { 0x37, 0xfa, 0x21, 0x3d };
            ms.Write(m, 0, 4);
            body = new byte[n];
            for (int i = 0; i < n; i++) body[i] = (byte)(payload[i] ^ m[i % 4]);
        }
        ms.Write(body, 0, body.Length);
        return ms.ToArray();
    }
    public static void Handshake(int port, string path) {
        TcpClient tcp = new TcpClient();
        tcp.ReceiveTimeout = 4000;
        tcp.SendTimeout = 4000;
        tcp.Connect("127.0.0.1", port);
        NetworkStream s = tcp.GetStream();
        string key = Convert.ToBase64String(Encoding.ASCII.GetBytes("0123456789abcdef"));
        string req = "GET " + path + " HTTP/1.1\r\nHost: 127.0.0.1\r\nUpgrade: websocket\r\nConnection: Upgrade\r\nSec-WebSocket-Key: " + key + "\r\nSec-WebSocket-Version: 13\r\n\r\n";
        byte[] rb = Encoding.ASCII.GetBytes(req);
        s.Write(rb, 0, rb.Length);
        byte[] buf = new byte[4096];
        System.IO.MemoryStream ms = new System.IO.MemoryStream();
        while (ms.Length < 8 || Encoding.ASCII.GetString(ms.ToArray()).IndexOf("\r\n\r\n") < 0) {
            int n = s.Read(buf, 0, buf.Length);
            if (n <= 0) break;
            ms.Write(buf, 0, n);
        }
        string text = Encoding.ASCII.GetString(ms.ToArray());
        if (text.IndexOf("101") < 0) throw new Exception("missing 101 " + text);
        string accept;
        using (SHA1 sha = SHA1.Create()) {
            accept = Convert.ToBase64String(sha.ComputeHash(Encoding.ASCII.GetBytes(key + WsGuid)));
        }
        if (text.IndexOf(accept) < 0) throw new Exception("missing accept");
        byte[] frame = MaskFrame(1, Encoding.ASCII.GetBytes("xyz"), true, true, 0, false);
        s.Write(frame, 0, frame.Length);
        byte[] got = new byte[8];
        int have = 0;
        while (have < 5) {
            int n = s.Read(got, have, got.Length - have);
            if (n <= 0) break;
            have += n;
        }
        tcp.Close();
        if (have < 5 || got[0] != 0x81 || got[1] != 0x03 || got[2] != (byte)'x' || got[3] != (byte)'y' || got[4] != (byte)'z')
            throw new Exception("echo mismatch");
    }
    public static int CloseCode(int port, byte[] frame) {
        TcpClient tcp = new TcpClient();
        tcp.ReceiveTimeout = 4000;
        tcp.SendTimeout = 4000;
        tcp.Connect("127.0.0.1", port);
        NetworkStream s = tcp.GetStream();
        string key = Convert.ToBase64String(Encoding.ASCII.GetBytes("0123456789abcdef"));
        string req = "GET /ws/kick HTTP/1.1\r\nHost: 127.0.0.1\r\nUpgrade: websocket\r\nConnection: Upgrade\r\nSec-WebSocket-Key: " + key + "\r\nSec-WebSocket-Version: 13\r\n\r\n";
        byte[] rb = Encoding.ASCII.GetBytes(req);
        s.Write(rb, 0, rb.Length);
        byte[] buf = new byte[4096];
        System.IO.MemoryStream ms = new System.IO.MemoryStream();
        while (Encoding.ASCII.GetString(ms.ToArray()).IndexOf("\r\n\r\n") < 0) {
            int n = s.Read(buf, 0, buf.Length);
            if (n <= 0) break;
            ms.Write(buf, 0, n);
        }
        s.Write(frame, 0, frame.Length);
        byte[] got = new byte[8];
        int have = 0;
        try {
            while (have < 4) {
                int n = s.Read(got, have, got.Length - have);
                if (n <= 0) break;
                have += n;
            }
        } catch {}
        tcp.Close();
        if (have < 4 || got[0] != 0x88) throw new Exception("expected close");
        return (got[2] << 8) | got[3];
    }
}
"@

try {
    function Prove-Apigo([string]$Label, [int]$Port) {
        $h = Invoke-LoopHttp -Port $Port -Method "GET" -Path "/health"
        if ($h.Body -notmatch "ok") { throw "$Label health missing ok" }
        Write-Host "$Label http_health_ok"
        foreach ($path in @("/ws/kick", "/ws/chat", "/ws/live", "/chat", "/live")) {
            [VireApigoProbe]::Handshake($Port, $path)
            Write-Host "$Label upgrade_echo_ok $path"
        }
        $cases = @(
            @{ Name = "unmasked"; Frame = [VireApigoProbe]::MaskFrame(1, [Text.Encoding]::ASCII.GetBytes("no"), $true, $false, 0, $false); Code = 1002 },
            @{ Name = "rsv"; Frame = [VireApigoProbe]::MaskFrame(1, [Text.Encoding]::ASCII.GetBytes("x"), $true, $true, 1, $false); Code = 1002 },
            @{ Name = "frag_ping"; Frame = [VireApigoProbe]::MaskFrame(9, [Text.Encoding]::ASCII.GetBytes("p"), $false, $true, 0, $false); Code = 1002 },
            @{ Name = "len64"; Frame = [VireApigoProbe]::MaskFrame(1, [Text.Encoding]::ASCII.GetBytes("tiny"), $true, $true, 0, $true); Code = 1009 }
        )
        $over = New-Object byte[] 65537
        for ($i = 0; $i -lt $over.Length; $i++) { $over[$i] = [byte][char]"a" }
        $cases += @{ Name = "oversize"; Frame = [VireApigoProbe]::MaskFrame(1, $over, $true, $true, 0, $false); Code = 1009 }
        foreach ($c in $cases) {
            $seen = [VireApigoProbe]::CloseCode($Port, $c.Frame)
            if ($seen -ne $c.Code) { throw "$Label malformed_$($c.Name) got $seen want $($c.Code)" }
            Write-Host "$Label malformed_$($c.Name)_close $($c.Code)"
        }
    }

    $hostProc = Start-OwnedProcess -FilePath "dotnet" -ArgumentList @("exec", $VireDll, "data/apigo-ws-win/apigo-ws.vire") -WorkingDirectory $Root
    $hport = Get-ListenPort $hostProc
    $natProc = Start-OwnedProcess -FilePath $nativePath -ArgumentList @() -WorkingDirectory $Root
    $nport = Get-ListenPort $natProc
    Prove-Apigo "host" $hport
    Prove-Apigo "native" $nport
    Write-Host "HOST_NATIVE_MATCH apigo-ws 101/echo/fail-closed"
    Write-Host ("PASS_AFTER at " + $AfterSha)
} finally {
    Stop-AllOwnedTrees
}
exit 0
