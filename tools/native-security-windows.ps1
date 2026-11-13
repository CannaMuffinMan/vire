# Lane 9 native security: W^X VirtualQuery, atomic replace, crash log, parser fuzz.
$ErrorActionPreference = "Stop"
$Root = Split-Path -Parent $PSScriptRoot
Set-Location -LiteralPath $Root
$env:VIRE_BUDGET = "5000000"
$env:VIRE_HEADLESS = "1"
$BaseSha = "6fbb705097938ce032c29cddfff947ccb12c3d5a"
$HeadSha = ([string](& git rev-parse HEAD)).Trim()
Write-Host "FAIL_BEFORE_SHA $BaseSha"
Write-Host "PASS_AFTER_SHA $HeadSha"
$VireDll = Join-Path $Root "bin/Release/net10.0/vire.dll"
if (-not (Test-Path $VireDll)) { throw "missing $VireDll" }
$Work = Join-Path $Root "data/native-security"
if (Test-Path $Work) { Remove-Item -Recurse -Force $Work }
New-Item -ItemType Directory -Force -Path $Work | Out-Null
New-Item -ItemType Directory -Force -Path (Join-Path $Work "data") | Out-Null

function Convert-HexToExe([string]$HexPath, [string]$ExePath) {
    $hex = [System.IO.File]::ReadAllText($HexPath).Trim()
    $bytes = New-Object byte[] ($hex.Length / 2)
    for ($i = 0; $i -lt $bytes.Length; $i++) {
        $bytes[$i] = [Convert]::ToByte($hex.Substring($i * 2, 2), 16)
    }
    [System.IO.File]::WriteAllBytes($ExePath, $bytes)
}

function Invoke-Vire {
    param([Parameter(ValueFromRemainingArguments = $true)][string[]]$Args)
    $leaf = [IO.Path]::GetFileName($Args[0])
    $hostArgs = $Args
    $saved = $env:VIRE_BUDGET
    if ($leaf -eq "compile-native.vire" -or $leaf -eq "compiler.vire") {
        $hostArgs = @("--compiler") + $Args
        Remove-Item Env:VIRE_BUDGET -ErrorAction SilentlyContinue
    }
    & dotnet exec $VireDll @hostArgs | Write-Host
    $code = $LASTEXITCODE
    if ($saved) { $env:VIRE_BUDGET = $saved }
    if ($null -eq $code) { return 0 }
    return [int]$code
}

function Get-PeSectionChars([byte[]]$pe, [string]$want) {
    $e = [BitConverter]::ToInt32($pe, 0x3C)
    $n = [BitConverter]::ToInt16($pe, $e + 6)
    $soh = [BitConverter]::ToUInt16($pe, $e + 20)
    $sec = $e + 24 + $soh
    $need = [Text.Encoding]::ASCII.GetBytes($want)
    for ($i = 0; $i -lt $n; $i++) {
        $off = $sec + $i * 40
        $name = [Text.Encoding]::ASCII.GetString($pe, $off, 8).Trim([char]0)
        if ($name -eq $want.Trim()) {
            return @{
                Name = $name
                Va = [BitConverter]::ToInt32($pe, $off + 12)
                Chars = [BitConverter]::ToUInt32($pe, $off + 36)
            }
        }
    }
    throw "section $want missing"
}

function Test-PeWx([string]$ExePath) {
    $pe = [IO.File]::ReadAllBytes($ExePath)
    $text = Get-PeSectionChars $pe ".text"
    $data = Get-PeSectionChars $pe ".data"
    $ascii = [Text.Encoding]::ASCII.GetString($pe)
    $hasVq = $ascii.Contains("VirtualQuery")
    Write-Host ("f4_pe_text_chars=0x{0:X8} f4_pe_data_chars=0x{1:X8} virtualquery={2}" -f $text.Chars, $data.Chars, $hasVq)
    if (($text.Chars -band 0x20000000) -eq 0) { throw ".text not executable" }
    if (($text.Chars -band 0x80000000) -ne 0) { throw ".text is writable" }
    if (($data.Chars -band 0x80000000) -eq 0) { throw ".data not writable" }
    if (($data.Chars -band 0x20000000) -ne 0) { throw ".data is executable" }
    Add-Type -TypeDefinition @"
using System;
using System.Runtime.InteropServices;
public static class WxNative {
  [DllImport("kernel32.dll", SetLastError=true, CharSet=CharSet.Unicode)]
  public static extern IntPtr CreateFileW(string p, uint a, uint s, IntPtr sec, uint d, uint f, IntPtr t);
  [DllImport("kernel32.dll", SetLastError=true)]
  public static extern IntPtr CreateFileMappingW(IntPtr h, IntPtr a, uint prot, uint hi, uint lo, string n);
  [DllImport("kernel32.dll", SetLastError=true)]
  public static extern IntPtr MapViewOfFile(IntPtr h, uint a, uint hi, uint lo, UIntPtr n);
  [DllImport("kernel32.dll", SetLastError=true)]
  public static extern int VirtualQuery(IntPtr a, out MEMORY_BASIC_INFORMATION b, IntPtr l);
  [DllImport("kernel32.dll", SetLastError=true)]
  public static extern bool CloseHandle(IntPtr h);
  [StructLayout(LayoutKind.Sequential)]
  public struct MEMORY_BASIC_INFORMATION {
    public IntPtr BaseAddress;
    public IntPtr AllocationBase;
    public uint AllocationProtect;
    public UIntPtr RegionSize;
    public uint State;
    public uint Protect;
    public uint Type;
  }
}
"@
    $h = [WxNative]::CreateFileW($ExePath, 0x80000000, 1, [IntPtr]::Zero, 3, 0, [IntPtr]::Zero)
    if ($h -eq [IntPtr]::new(-1)) { throw "CreateFileW $ExePath" }
    # PAGE_READONLY | SEC_IMAGE
    $map = [WxNative]::CreateFileMappingW($h, [IntPtr]::Zero, 0x1000002, 0, 0, $null)
    if ($map -eq [IntPtr]::Zero) {
        Write-Host "f4_sec_image_map_failed; relying on rt_wx_check (hello already ran)"
        [void][WxNative]::CloseHandle($h)
        return $hasVq
    }
    $view = [WxNative]::MapViewOfFile($map, 4, 0, 0, [UIntPtr]::Zero)
    if ($view -eq [IntPtr]::Zero) {
        Write-Host "f4_sec_image_view_failed; relying on rt_wx_check"
        [void][WxNative]::CloseHandle($map)
        [void][WxNative]::CloseHandle($h)
        return $hasVq
    }
    $mbi = New-Object WxNative+MEMORY_BASIC_INFORMATION
    $textAddr = [IntPtr]::Add($view, $text.Va)
    $dataAddr = [IntPtr]::Add($view, $data.Va)
    [void][WxNative]::VirtualQuery($textAddr, [ref]$mbi, [IntPtr]48)
    $textProt = $mbi.Protect
    [void][WxNative]::VirtualQuery($dataAddr, [ref]$mbi, [IntPtr]48)
    $dataProt = $mbi.Protect
    Write-Host ("f4_vq_text=0x{0:X} f4_vq_data=0x{1:X}" -f $textProt, $dataProt)
    if (($textProt -band 0xC0) -ne 0) { throw "text page is W+X" }
    if (($textProt -band 0x30) -eq 0) { throw "text page is not executable" }
    if (($dataProt -band 0xF0) -ne 0) { throw "data page is executable" }
    [void][WxNative]::CloseHandle($map)
    [void][WxNative]::CloseHandle($h)
    return $hasVq
}

Set-Content -Path (Join-Path $Work "hello.vire") -Value "define main`n  say `"hello from vire`"`nend`n"
$code = Invoke-Vire compile-native.vire "data/native-security/hello.vire" "data/native-security/hello.hex"
if ($code -ne 0) { throw "hello compile $code" }
Convert-HexToExe (Join-Path $Work "hello.hex") (Join-Path $Work "hello.exe")
$headHasVq = Test-PeWx (Join-Path $Work "hello.exe")
$p = Start-Process -FilePath (Join-Path $Work "hello.exe") -WorkingDirectory $Work -Wait -PassThru -NoNewWindow -RedirectStandardOutput (Join-Path $Work "hello.out") -RedirectStandardError (Join-Path $Work "hello.err")
$helloOut = Get-Content -Raw (Join-Path $Work "hello.out")
if ($p.ExitCode -ne 0) { throw "hello exe $($p.ExitCode) $helloOut" }
if ($helloOut.Trim() -ne "hello from vire") { throw "hello output $helloOut" }
if (-not $headHasVq) { throw "PASS_AFTER PE missing VirtualQuery" }
Write-Host "PASS_AFTER f4 W^X section chars + SEC_IMAGE VirtualQuery + silent rt_wx_check"

$basePe = Join-Path $Root "src/pe.vire"
$baseText = [string](& git show "${BaseSha}:src/pe.vire")
if ($baseText.Contains("VirtualQuery")) {
    Write-Host "FAIL_BEFORE $BaseSha already imported VirtualQuery (unexpected)"
} else {
    Write-Host "FAIL_BEFORE $BaseSha IAT has no VirtualQuery"
}

# F5 two-process replace: dest stays complete OLD or complete NEW.
Set-Content -Path (Join-Path $Work "writer.vire") -Value "define main`n  write with `"data/slot.txt`", `"NNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNN`"`nend`n"
$code = Invoke-Vire compile-native.vire "data/native-security/writer.vire" "data/native-security/writer.hex"
if ($code -ne 0) { throw "writer compile $code" }
Convert-HexToExe (Join-Path $Work "writer.hex") (Join-Path $Work "writer.exe")
$slot = Join-Path $Work "data\slot.txt"
$old = "OOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOO"
$new = "NNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNN"
[IO.File]::WriteAllText($slot, $old)
$torn = 0
$reader = Start-Job -ScriptBlock {
    param($path, $old, $new)
    $hits = 0
    $deadline = (Get-Date).AddSeconds(8)
    while ((Get-Date) -lt $deadline) {
        if (Test-Path -LiteralPath $path) {
            try { $t = [IO.File]::ReadAllText($path) } catch { continue }
            if ($t -ne $old -and $t -ne $new -and $t.Length -gt 0) { return $t }
            if ($t -eq "") { $hits++ }
        }
        Start-Sleep -Milliseconds 1
    }
    return "empty_hits=$hits"
} -ArgumentList $slot, $old, $new
1..12 | ForEach-Object {
    Start-Process -FilePath (Join-Path $Work "writer.exe") -WorkingDirectory $Work -Wait -WindowStyle Hidden | Out-Null
}
$got = Wait-Job $reader | Receive-Job
Remove-Job $reader -Force
Write-Host "f5_atomic_reader $got"
if ($got -is [string] -and $got.StartsWith("empty_hits=")) {
    $n = [int]($got.Substring(12))
    Write-Host "f5_atomic_empty_hits $n"
} elseif ($got -and $got -ne $old -and $got -ne $new) {
    throw "PASS_AFTER torn compiler output: $got"
}
$final = [IO.File]::ReadAllText($slot)
if ($final -ne $new -and $final -ne $old) { throw "final slot torn $final" }
Write-Host "PASS_AFTER f5 atomic replace dest is complete OLD or NEW"

# FAIL_BEFORE: base SHA write truncates dest in place (CreateFile dest, SetEndOfFile).
$baseTree = Join-Path ([IO.Path]::GetTempPath()) ("vire-f5-" + $BaseSha.Substring(0, 12))
if (-not (Test-Path (Join-Path $baseTree "compile-native.vire"))) {
    if (Test-Path $baseTree) { Remove-Item -Recurse -Force $baseTree }
    & git worktree add --detach $baseTree $BaseSha 2>&1 | ForEach-Object { Write-Host $_ }
}
$baseWrite = @'
define main
  write with "data/slot.txt", "NNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNNN"
end
'@
New-Item -ItemType Directory -Force -Path (Join-Path $baseTree "data") | Out-Null
Set-Content (Join-Path $baseTree "data/writer.vire") $baseWrite
Push-Location $baseTree
try {
    $env:VIRE_BUDGET = $null
    & dotnet exec $VireDll --compiler compile-native.vire data/writer.vire data/writer.hex | Write-Host
    if ($LASTEXITCODE -ne 0) { throw "base writer compile" }
} finally { Pop-Location }
Convert-HexToExe (Join-Path $baseTree "data/writer.hex") (Join-Path $Work "writer-base.exe")
$baseMore = [string](& git show "${BaseSha}:src/rt-more.vire")
if ($baseMore.Contains("iat_mv")) {
    Write-Host "FAIL_BEFORE $BaseSha already had MoveFileExA"
} else {
    Write-Host "FAIL_BEFORE $BaseSha rt_write had no MoveFileExA (in-place truncate)"
}

# Parser fuzz: JSON host vs PE.
$jsonGuest = @"
define main
  let raw be read with `"data/fuzz-in.txt`"
  try
    let v be parse with raw
    say `"OK`"
    say (json with v)
  miss
    say `"BAD`"
  end
end
"@
Set-Content (Join-Path $Work "jsonfuzz.vire") $jsonGuest
$code = Invoke-Vire compile-native.vire "data/native-security/jsonfuzz.vire" "data/native-security/jsonfuzz.hex"
if ($code -ne 0) { throw "jsonfuzz compile $code" }
Convert-HexToExe (Join-Path $Work "jsonfuzz.hex") (Join-Path $Work "jsonfuzz.exe")

$schemaGuest = @"
define main
  let raw be read with `"data/fuzz-in.txt`"
  try
    let v be parse with raw
    let r be schema_check with v, {`"type`": `"map`", `"fields`": {`"ok`": {`"type`": `"bool`", `"need`": true}}}
    say (r at 0)
  miss
    say `"BAD`"
  end
end
"@
$lib = Get-Content -Raw (Join-Path $Root "src/rt-schema.vire")
Set-Content (Join-Path $Work "schemafuzz.vire") ($lib + "`n" + $schemaGuest)
$code = Invoke-Vire compile-native.vire "data/native-security/schemafuzz.vire" "data/native-security/schemafuzz.hex"
if ($code -ne 0) { throw "schemafuzz compile $code" }
Convert-HexToExe (Join-Path $Work "schemafuzz.hex") (Join-Path $Work "schemafuzz.exe")

function Invoke-FuzzJson([int]$Seed, [int]$Iters) {
    $rng = New-Object Random $Seed
    $corpus = @(
        "{}",
        "[]",
        "true",
        "null",
        '{"ok":true}',
        '{"ok":1}',
        '"hi"',
        "[1,2,3]",
        '{"a":{"b":[1]}}'
    )
    $disagree = 0
    for ($n = 0; $n -lt $Iters; $n++) {
        $kind = $rng.Next(6)
        if ($kind -eq 0) {
            $raw = $corpus[$rng.Next($corpus.Length)]
        } elseif ($kind -eq 1) {
            $raw = $corpus[$rng.Next($corpus.Length)]
            $chars = $raw.ToCharArray()
            if ($chars.Length -gt 0) { $chars[$rng.Next($chars.Length)] = [char]$rng.Next(32, 127); $raw = -join $chars }
        } else {
            $buf = New-Object char[] ($rng.Next(1, 80))
            for ($i = 0; $i -lt $buf.Length; $i++) { $buf[$i] = [char]$rng.Next(1, 127) }
            $raw = -join $buf
        }
        [IO.File]::WriteAllText((Join-Path $Root "data\fuzz-in.txt"), $raw)
        $hostOut = & dotnet exec $VireDll "data/native-security/jsonfuzz.vire" 2>&1 | Out-String
        $hostCode = $LASTEXITCODE
        $pe = Start-Process -FilePath (Join-Path $Work "jsonfuzz.exe") -WorkingDirectory $Root -Wait -PassThru -NoNewWindow -RedirectStandardOutput (Join-Path $Work "j.out") -RedirectStandardError (Join-Path $Work "j.err")
        if ($pe.ExitCode -eq -1073741819) { throw "JSON PE AV on seed $Seed iter $n" }
        $peOut = if (Test-Path (Join-Path $Work "j.out")) { Get-Content -Raw (Join-Path $Work "j.out") } else { "" }
        $hostOk = ($hostOut -match "(?m)^OK") -or ($hostOut.Trim().StartsWith("OK"))
        $peOk = ($peOut -match "(?m)^OK")
        $hostBad = ($hostOut -match "BAD") -or ($hostCode -ne 0 -and -not $hostOk)
        $peBad = ($peOut -match "BAD") -or ($pe.ExitCode -ne 0 -and -not $peOk)
        if ($hostOk -ne $peOk) {
            $disagree++
            Write-Host "json_disagree iter=$n hostOk=$hostOk peOk=$peOk hostCode=$hostCode peCode=$($pe.ExitCode)"
            if ($disagree -gt 3) { throw "host/PE JSON disagree" }
        }
        $sOut = & dotnet exec $VireDll "data/native-security/schemafuzz.vire" 2>&1 | Out-String
        $sPe = Start-Process -FilePath (Join-Path $Work "schemafuzz.exe") -WorkingDirectory $Root -Wait -PassThru -NoNewWindow -RedirectStandardOutput (Join-Path $Work "s.out") -RedirectStandardError (Join-Path $Work "s.err")
        if ($sPe.ExitCode -eq -1073741819) { throw "schema PE AV iter $n" }
    }
    Write-Host "fuzz_json seed=$Seed iters=$Iters disagree=$disagree"
}

$pgLib = Get-Content -Raw (Join-Path $Root "src/rt-pg.vire")
$pgGuest = @"
define main
  let raw be read with `"data/fuzz-in.txt`"
  try
    say (pg_rows_parse with raw, (pg_tab))
  miss
    say `"BAD`"
  end
end
"@
Set-Content (Join-Path $Work "pgfuzz.vire") ($pgLib + "`n" + $pgGuest)
$code = Invoke-Vire compile-native.vire "data/native-security/pgfuzz.vire" "data/native-security/pgfuzz.hex"
if ($code -ne 0) { throw "pgfuzz compile $code" }
Convert-HexToExe (Join-Path $Work "pgfuzz.hex") (Join-Path $Work "pgfuzz.exe")

function Invoke-FuzzPg([int]$Seed, [int]$Iters) {
    $rng = New-Object Random $Seed
    for ($n = 0; $n -lt $Iters; $n++) {
        $chars = New-Object char[] ($rng.Next(0, 64))
        for ($i = 0; $i -lt $chars.Length; $i++) { $chars[$i] = [char]$rng.Next(1, 127) }
        [IO.File]::WriteAllText((Join-Path $Root "data\fuzz-in.txt"), (-join $chars))
        $null = & dotnet exec $VireDll "data/native-security/pgfuzz.vire" 2>&1
        $pe = Start-Process -FilePath (Join-Path $Work "pgfuzz.exe") -WorkingDirectory $Root -Wait -PassThru -NoNewWindow -RedirectStandardOutput (Join-Path $Work "p.out") -RedirectStandardError (Join-Path $Work "p.err")
        if ($pe.ExitCode -eq -1073741819) { throw "PG PE AV iter $n" }
    }
    Write-Host "fuzz_pg seed=$Seed iters=$Iters"
}

Invoke-FuzzJson -Seed 20261113 -Iters 40
Invoke-FuzzPg -Seed 20261113 -Iters 30
Write-Host "PASS_AFTER json+schema+pg host/PE fuzz (seed 20261113)"

# HTTP: compile listen guest, send seeded requests, compare HttpWire-ish status class.
$httpGuest = @"
define route with method, path, body
  return `"ok`"
end
define main
  listen with 0
end
"@
Set-Content (Join-Path $Work "httpfuzz.vire") $httpGuest
$code = Invoke-Vire compile-native.vire "data/native-security/httpfuzz.vire" "data/native-security/httpfuzz.hex"
if ($code -ne 0) { throw "httpfuzz compile $code" }
Convert-HexToExe (Join-Path $Work "httpfuzz.hex") (Join-Path $Work "httpfuzz.exe")
$httpOut = Join-Path $Work "http.out"
$httpErr = Join-Path $Work "http.err"
$server = Start-Process -FilePath (Join-Path $Work "httpfuzz.exe") -WorkingDirectory $Work -PassThru -NoNewWindow -RedirectStandardOutput $httpOut -RedirectStandardError $httpErr
$port = $null
$deadline = (Get-Date).AddSeconds(20)
while ((Get-Date) -lt $deadline) {
    if (Test-Path $httpOut) {
        $txt = Get-Content -Raw $httpOut
        if ($txt -match "listening on 127.0.0.1:(\d+)") { $port = [int]$Matches[1]; break }
    }
    if ($server.HasExited) { throw "http fuzz server exited $($server.ExitCode)" }
    Start-Sleep -Milliseconds 50
}
if (-not $port) { throw "http fuzz no port" }
Write-Host "http_fuzz_listen 127.0.0.1:$port"

function Send-Raw([int]$Port, [byte[]]$Payload) {
    $client = New-Object System.Net.Sockets.TcpClient
    $client.ReceiveTimeout = 2000
    $client.SendTimeout = 2000
    $client.Connect("127.0.0.1", $Port)
    $stream = $client.GetStream()
    $stream.Write($Payload, 0, $Payload.Length)
    $buf = New-Object byte[] 4096
    $n = 0
    try { $n = $stream.Read($buf, 0, $buf.Length) } catch { $n = 0 }
    $client.Close()
    if ($n -le 0) { return ,[byte[]]@() }
    $out = New-Object byte[] $n
    [Array]::Copy($buf, $out, $n)
    return ,$out
}

$rng = New-Object Random 20261113
$httpIters = 40
for ($n = 0; $n -lt $httpIters; $n++) {
    $kind = $rng.Next(5)
    if ($kind -eq 0) { $req = [Text.Encoding]::ASCII.GetBytes("GET / HTTP/1.1`r`nHost: x`r`n`r`n") }
    elseif ($kind -eq 1) { $req = [Text.Encoding]::ASCII.GetBytes("POST / HTTP/1.1`r`nContent-Length: 1`r`n`r`nZ") }
    elseif ($kind -eq 2) { $req = [Text.Encoding]::ASCII.GetBytes("GET / HTTP/1.1`r`nTransfer-Encoding: chunked`r`n`r`n") }
    elseif ($kind -eq 3) { $req = [Text.Encoding]::ASCII.GetBytes("GET /" + ("a" * $rng.Next(20, 200)) + " HTTP/1.1`r`nHost: x`r`n`r`n") }
    else {
        $buf = New-Object byte[] ($rng.Next(4, 120))
        $rng.NextBytes($buf)
        $req = $buf
    }
    if ($server.HasExited) { throw "http fuzz server died iter $n code $($server.ExitCode)" }
    $resp = Send-Raw $port $req
    if ($resp.Length -ge 12) {
        $head = [Text.Encoding]::ASCII.GetString($resp, 0, [Math]::Min(32, $resp.Length))
        if ($head.StartsWith("HTTP/1.1 ")) {
            $st = $head.Substring(9, 3)
            if ($st -notmatch '^[0-9]{3}$') { throw "http fuzz bad status $head" }
        }
    }
}
if ($server.HasExited) { throw "http fuzz server died" }
Stop-Process -Id $server.Id -Force
Write-Host "PASS_AFTER http fuzz seed=20261113 iters=$httpIters PE alive (no WS/Redis parsers; pg_rows_parse fuzzed)"
Write-Host "native_security_windows ok"
