# Shared CouchStation helpers for host-vs-native loopback proofs.
# PowerShell 5.1: never read ExitCode until Handle+WaitForExit; null is unknown.
# Kill only PIDs this script started. Child logs: FileShare.ReadWrite.
$script:VireOwnedPids = New-Object System.Collections.Generic.List[int]

function Test-VireOnWindows {
    if ($env:OS -eq "Windows_NT") { return $true }
    if (Get-Variable -Name IsWindows -ErrorAction SilentlyContinue) {
        if ($IsWindows) { return $true }
    }
    return $false
}

function Assert-VireCaps {
    param([string]$Root)
    $rt = Get-Content -Raw (Join-Path $Root "src/rt.vire")
    if ($rt -notmatch "33554432") { throw "arena cap drifted" }
    $cs = Get-Content -Raw (Join-Path $Root "Vire.cs")
    if ($cs -notmatch "100000") { throw "list cap missing" }
    if ($cs -notmatch "5000000") { throw "step cap missing" }
    Write-Host "caps_src_ok arena=33554432 list=100000 steps=5000000"
}

function Get-VireDll([string]$Root) {
    $dll = Join-Path $Root "bin/Release/net10.0/vire.dll"
    if (-not (Test-Path $dll)) {
        & dotnet build (Join-Path $Root "vire.csproj") -c Release --nologo
        if ($LASTEXITCODE -ne 0) { throw "build failed" }
    }
    if (-not (Test-Path $dll)) { throw "missing $dll" }
    return $dll
}

function Convert-VireHexToFile([string]$HexPath, [string]$OutPath) {
    $hex = [IO.File]::ReadAllText($HexPath).Trim()
    if ($hex.Length -eq 0 -or ($hex.Length % 2) -ne 0) { throw "bad hex $HexPath" }
    $bytes = New-Object byte[] ($hex.Length / 2)
    for ($i = 0; $i -lt $bytes.Length; $i++) {
        $bytes[$i] = [Convert]::ToByte($hex.Substring($i * 2, 2), 16)
    }
    [IO.File]::WriteAllBytes($OutPath, $bytes)
}

function Stop-OwnedProcessTree([int]$Id) {
    if ($Id -le 0) { return }
    if (Test-VireOnWindows) {
        try { & taskkill.exe /PID $Id /T /F 2>$null | Out-Null } catch { }
    } else {
        try { & kill -TERM -$Id 2>$null } catch { }
        try { & kill -TERM $Id 2>$null } catch { }
    }
    try { Stop-Process -Id $Id -Force -ErrorAction SilentlyContinue } catch { }
}

function Register-OwnedPid([int]$Id) {
    if ($Id -gt 0 -and -not $script:VireOwnedPids.Contains($Id)) {
        [void]$script:VireOwnedPids.Add($Id)
    }
}

function Stop-AllOwnedTrees {
    $i = $script:VireOwnedPids.Count - 1
    while ($i -ge 0) {
        Stop-OwnedProcessTree $script:VireOwnedPids[$i]
        $i = $i - 1
    }
    $script:VireOwnedPids.Clear()
}

function Get-OwnedExitCode {
    param(
        [Parameter(Mandatory = $true)][System.Diagnostics.Process]$Proc,
        [int]$TimeoutMs = 120000
    )
    $null = $Proc.Handle
    if ($TimeoutMs -gt 0) {
        if (-not $Proc.WaitForExit($TimeoutMs)) {
            Stop-OwnedProcessTree $Proc.Id
            throw "ERROR process wait timeout pid=$($Proc.Id)"
        }
    } else {
        $Proc.WaitForExit()
    }
    $Proc.WaitForExit()
    if (-not $Proc.HasExited) { throw "ERROR process still running after WaitForExit" }
    if ($null -eq $Proc.ExitCode) { throw "ERROR unknown exit code" }
    return [int]$Proc.ExitCode
}

function Start-OwnedProcess {
    param(
        [Parameter(Mandatory = $true)][string]$FilePath,
        [string[]]$ArgumentList,
        [string]$WorkingDirectory,
        [string]$OutLog,
        [string]$ErrLog
    )
    $argLine = ""
    if ($ArgumentList) { $argLine = ConvertTo-ProcessArguments $ArgumentList }
    $p = $null
    if ($OutLog) {
        New-Item -ItemType Directory -Force -Path (Split-Path -Parent $OutLog) | Out-Null
        if ($argLine) {
            $p = Start-Process -FilePath $FilePath -ArgumentList $argLine -WorkingDirectory $WorkingDirectory -NoNewWindow -PassThru -RedirectStandardOutput $OutLog -RedirectStandardError $ErrLog
        } else {
            $p = Start-Process -FilePath $FilePath -WorkingDirectory $WorkingDirectory -NoNewWindow -PassThru -RedirectStandardOutput $OutLog -RedirectStandardError $ErrLog
        }
    } else {
        $p = Start-VireProcess -FilePath $FilePath -ArgumentList $ArgumentList -WorkingDirectory $WorkingDirectory
    }
    Register-OwnedPid $p.Id
    return $p
}

function Read-OwnedLog([string]$Path) {
    return (Read-SharedText $Path)
}

function Invoke-OwnedCli {
    param(
        [Parameter(Mandatory = $true)][string]$FilePath,
        [string[]]$ArgumentList,
        [string]$WorkingDirectory,
        [string]$Stage
    )
    $stamp = [Guid]::NewGuid().ToString("N")
    $outLog = Join-Path $Stage ("cli-" + $stamp + ".out")
    $errLog = $outLog + ".err"
    $p = Start-OwnedProcess -FilePath $FilePath -ArgumentList $ArgumentList -WorkingDirectory $WorkingDirectory -OutLog $outLog -ErrLog $errLog
    $code = Get-OwnedExitCode $p
    $text = (Read-OwnedLog $outLog).Trim()
    $err = (Read-OwnedLog $errLog).Trim()
    if ($err) { $text = ($text + "`n" + $err).Trim() }
    return @{ Code = $code; Text = $text }
}

function Compile-VireNative {
    param(
        [Parameter(Mandatory = $true)][string]$Root,
        [Parameter(Mandatory = $true)][string]$VireDll,
        [Parameter(Mandatory = $true)][string]$SrcRel,
        [Parameter(Mandatory = $true)][string]$HexRel,
        [Parameter(Mandatory = $true)][string]$OutPath,
        [switch]$Pe
    )
    New-Item -ItemType Directory -Force -Path (Join-Path $Root "data") | Out-Null
    if (Test-Path (Join-Path $Root $HexRel)) { Remove-Item -Force (Join-Path $Root $HexRel) }
    $args = New-Object System.Collections.Generic.List[string]
    [void]$args.Add("exec"); [void]$args.Add($VireDll); [void]$args.Add("--compiler")
    [void]$args.Add("compile-native.vire"); [void]$args.Add($SrcRel); [void]$args.Add($HexRel)
    if ($Pe) { [void]$args.Add("pe") }
    $stamp = [Guid]::NewGuid().ToString("N")
    $outLog = Join-Path $Root ("data/compile-" + $stamp + ".out")
    $errLog = $outLog + ".err"
    $p = Start-OwnedProcess -FilePath "dotnet" -ArgumentList $args.ToArray() -WorkingDirectory $Root -OutLog $outLog -ErrLog $errLog
    $code = Get-OwnedExitCode $p
    if ($code -ne 0) {
        Write-Host (Read-OwnedLog $outLog)
        Write-Host (Read-OwnedLog $errLog)
        throw "compile exit $code $SrcRel"
    }
    Convert-VireHexToFile (Join-Path $Root $HexRel) $OutPath
    if ($Pe) {
        $pe = [IO.File]::ReadAllBytes($OutPath)
        if ($pe[0] -ne 0x4d -or $pe[1] -ne 0x5a) { throw "PE missing MZ $OutPath" }
    } else {
        $elf = [IO.File]::ReadAllBytes($OutPath)
        if ($elf.Length -lt 4 -or $elf[0] -ne 0x7f -or $elf[1] -ne 0x45 -or $elf[2] -ne 0x4c -or $elf[3] -ne 0x46) {
            throw "ELF missing magic $OutPath"
        }
        try { & chmod +x $OutPath } catch { }
    }
}

function Invoke-LoopHttp {
    param(
        [Parameter(Mandatory = $true)][int]$Port,
        [Parameter(Mandatory = $true)][string]$Method,
        [Parameter(Mandatory = $true)][string]$Path,
        [string]$Body = "",
        [string]$Cookie = "",
        [int]$TimeoutMs = 8000
    )
    $payload = [Text.Encoding]::UTF8.GetBytes($Body)
    $sb = New-Object Text.StringBuilder
    [void]$sb.Append("$Method $Path HTTP/1.1`r`nHost: 127.0.0.1`r`nConnection: close`r`n")
    if ($Cookie) { [void]$sb.Append("Cookie: $Cookie`r`n") }
    if ($Method -eq "POST" -or $Method -eq "PUT") {
        [void]$sb.Append("Content-Length: $($payload.Length)`r`n")
    }
    [void]$sb.Append("`r`n")
    $head = [Text.Encoding]::ASCII.GetBytes($sb.ToString())
    $req = New-Object byte[] ($head.Length + $payload.Length)
    [Array]::Copy($head, 0, $req, 0, $head.Length)
    if ($payload.Length -gt 0) { [Array]::Copy($payload, 0, $req, $head.Length, $payload.Length) }
    $tcp = New-Object System.Net.Sockets.TcpClient
    $tcp.ReceiveTimeout = $TimeoutMs
    $tcp.SendTimeout = $TimeoutMs
    $tcp.Connect("127.0.0.1", $Port)
    $st = $tcp.GetStream()
    $st.Write($req, 0, $req.Length)
    $st.Flush()
    $rawBytes = Read-VireHttpStream $st
    try { $tcp.Close() } catch { }
    $text = [Text.Encoding]::UTF8.GetString($rawBytes)
    if ($text -notmatch "^HTTP/") { throw "empty/bad http $Port $Path $($text.Substring(0, [Math]::Min(80, $text.Length)))" }
    $split = $text.IndexOf("`r`n`r`n")
    $add = 4
    if ($split -lt 0) { $split = $text.IndexOf("`n`n"); $add = 2 }
    if ($split -lt 0) { throw "missing header terminator: $text" }
    $start = $text.Substring(0, $split)
    $bodyText = $text.Substring($split + $add)
    $status = [int]($start.Split(" ")[1])
    $headers = @{}
    $lines = $start -split "`r`n"
    $hi = 1
    while ($hi -lt $lines.Count) {
        $line = $lines[$hi]
        if ($line -match "^([^:]+):\s*(.*)$") {
            $headers[$Matches[1].ToLower()] = $Matches[2].Trim()
        }
        $hi = $hi + 1
    }
    return @{ Status = $status; Body = $bodyText; Headers = $headers; Raw = $text }
}

function Assert-HttpContract {
    param(
        [Parameter(Mandatory = $true)][int]$Port,
        [Parameter(Mandatory = $true)][string]$DocPath,
        [Parameter(Mandatory = $true)][string]$Label
    )
    $doc = Get-Content -Raw $DocPath | ConvertFrom-Json
    foreach ($c in $doc.cases) {
        $method = "GET"
        if ($c.method) { $method = [string]$c.method }
        $send = ""
        if ($c.PSObject.Properties["req_body"]) { $send = [string]$c.req_body }
        elseif ($c.PSObject.Properties["post_body"]) { $send = [string]$c.post_body }
        $cookie = ""
        if ($c.PSObject.Properties["cookie"]) { $cookie = [string]$c.cookie }
        $got = Invoke-LoopHttp -Port $Port -Method $method -Path $c.path -Body $send -Cookie $cookie
        if ($got.Status -ne [int]$c.status) {
            throw "$Label $($c.name) status $($got.Status) want $($c.status) body=$($got.Body)"
        }
        if ($got.Body -ne $c.body) {
            throw "$Label $($c.name) body mismatch got=$($got.Body) want=$($c.body)"
        }
        if ($c.headers) {
            foreach ($hp in $c.headers.PSObject.Properties) {
                $hk = $hp.Name.ToLower()
                if ($got.Headers[$hk] -ne $hp.Value) {
                    throw "$Label $($c.name) header $hk got=$($got.Headers[$hk]) want=$($hp.Value)"
                }
            }
        }
    }
}

function Compare-HostNativeHttp {
    param(
        [int]$HostPort,
        [int]$NatPort,
        [string]$Method,
        [string]$Path,
        [string]$Body = "",
        [string]$Cookie = "",
        [int]$WantStatus = -1,
        [string]$WantContains = ""
    )
    $h = Invoke-LoopHttp -Port $HostPort -Method $Method -Path $Path -Body $Body -Cookie $Cookie
    $n = Invoke-LoopHttp -Port $NatPort -Method $Method -Path $Path -Body $Body -Cookie $Cookie
    if ($h.Status -ne $n.Status -or $h.Body -ne $n.Body) {
        throw "HOST_NATIVE_MISMATCH $Method $Path host=$($h.Status)/$($h.Body) pe=$($n.Status)/$($n.Body)"
    }
    if ($WantStatus -ge 0 -and $h.Status -ne $WantStatus) {
        throw "status $Method $Path $($h.Status) want $WantStatus"
    }
    if ($WantContains -and ($h.Body -notmatch [regex]::Escape($WantContains))) {
        throw "missing $WantContains in $Path $($h.Body)"
    }
    return $h
}
