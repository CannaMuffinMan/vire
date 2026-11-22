function Write-VireHostInfo {
    Write-Output ("os " + [System.Runtime.InteropServices.RuntimeInformation]::OSDescription)
    Write-Output ("framework " + [System.Runtime.InteropServices.RuntimeInformation]::FrameworkDescription)
    Write-Output ("cores " + [Environment]::ProcessorCount)
    $cpu = ""
    try {
        $cpu = (Get-CimInstance -ClassName Win32_Processor | Select-Object -First 1).Name
    } catch {
        $cpu = $env:PROCESSOR_IDENTIFIER
    }
    if (-not $cpu) { $cpu = "unknown" }
    Write-Output ("cpu " + $cpu.Trim())
    $dotnet = $null
    try { $dotnet = (& dotnet --version 2>$null | Out-String).Trim() } catch { }
    if ($dotnet) { Write-Output ("dotnet_sdk " + $dotnet) }
    Write-Output ("DOTNET_TieredCompilation=" + $(if ($null -eq $env:DOTNET_TieredCompilation) { "unset(default on)" } else { $env:DOTNET_TieredCompilation }))
    Write-Output ("DOTNET_TieredPGO=" + $(if ($null -eq $env:DOTNET_TieredPGO) { "unset" } else { $env:DOTNET_TieredPGO }))
    Write-Output ("DOTNET_ReadyToRun=" + $(if ($null -eq $env:DOTNET_ReadyToRun) { "unset" } else { $env:DOTNET_ReadyToRun }))
    Write-Output "heartbeat: still running steps=N every 2s wall; N is budget.Steps (one per 64 interpreter Step calls). total_steps is the final N, not extra work."
}

function Get-VireProofDll {
    $p = Join-Path $PSScriptRoot "VireProof/bin/Release/net10.0/vire-proof.dll"
    if (-not (Test-Path $p)) {
        $proj = Join-Path $PSScriptRoot "VireProof/VireProof.csproj"
        & dotnet build $proj -c Release --nologo | Out-Host
        if ($LASTEXITCODE -ne 0) { throw "vire-proof build failed" }
    }
    if (-not (Test-Path $p)) { throw "missing $p" }
    return $p
}

function ConvertTo-ProcessArguments([string[]]$Argv) {
    $parts = New-Object System.Collections.Generic.List[string]
    foreach ($a in $Argv) {
        if ($null -eq $a) { continue }
        if ($a -match '[ \t"]') {
            $esc = $a.Replace('\', '\\').Replace('"', '\"')
            [void]$parts.Add('"' + $esc + '"')
        } else {
            [void]$parts.Add($a)
        }
    }
    return ($parts -join ' ')
}

function Read-SharedText([string]$Path) {
    if (-not (Test-Path -LiteralPath $Path)) { return "" }
    $fs = [IO.File]::Open($Path, [IO.FileMode]::Open, [IO.FileAccess]::Read, [IO.FileShare]::ReadWrite)
    try {
        $sr = New-Object IO.StreamReader($fs)
        return $sr.ReadToEnd()
    } finally {
        $fs.Dispose()
    }
}

function Test-VireRstException($err) {
    $cur = $err
    while ($null -ne $cur) {
        $msg = ""
        try { $msg = "$($cur.Message)" } catch { }
        if ($msg -match "forcibly closed|10054|WSAECONNRESET|connection reset") { return $true }
        if ($cur -is [System.IO.IOException]) { return $true }
        if ($cur -is [System.Net.Sockets.SocketException]) { return $true }
        try { $cur = $cur.InnerException } catch { break }
    }
    return $false
}

function Read-VireHttpStream([System.Net.Sockets.NetworkStream]$Stream) {
    $ms = New-Object System.IO.MemoryStream
    $buf = New-Object byte[] 4096
    try {
        while (($n = $Stream.Read($buf, 0, $buf.Length)) -gt 0) { $ms.Write($buf, 0, $n) }
    } catch {
        if ($ms.Length -eq 0 -and -not (Test-VireRstException $_.Exception)) { throw }
    }
    return $ms.ToArray()
}

function Get-ChildExitCode {
    param(
        [Parameter(Mandatory = $true)][System.Diagnostics.Process]$Proc,
        [int]$TimeoutMs = 0
    )
    $null = $Proc.Handle
    if ($TimeoutMs -gt 0) {
        if (-not $Proc.WaitForExit($TimeoutMs)) { throw "ERROR process wait timeout" }
    } else {
        $Proc.WaitForExit()
    }
    $Proc.WaitForExit()
    if (-not $Proc.HasExited) { throw "ERROR process still running after WaitForExit" }
    if ($null -eq $Proc.ExitCode) { throw "ERROR unknown exit code" }
    return [int]$Proc.ExitCode
}

function Start-VireProcess {
    param(
        [Parameter(Mandatory = $true)][string]$FilePath,
        [string[]]$ArgumentList,
        [string]$WorkingDirectory
    )
    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = $FilePath
    if ($ArgumentList) { $psi.Arguments = ConvertTo-ProcessArguments $ArgumentList }
    $psi.WorkingDirectory = $(if ($WorkingDirectory) { $WorkingDirectory } else { (Get-Location).Path })
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    $psi.UseShellExecute = $false
    $psi.CreateNoWindow = $true
    return [System.Diagnostics.Process]::Start($psi)
}

function Get-ListenPort {
    param(
        [Parameter(Mandatory = $true)][System.Diagnostics.Process]$Proc,
        [int]$Seconds = 12
    )
    $deadline = [DateTime]::UtcNow.AddSeconds($Seconds)
    $buf = New-Object System.Text.StringBuilder
    while ([DateTime]::UtcNow -lt $deadline) {
        if ($Proc.HasExited) {
            $tail = ""
            try { $tail = $Proc.StandardOutput.ReadToEnd() } catch { }
            $err = ""
            try { $err = $Proc.StandardError.ReadToEnd() } catch { }
            throw ("no listen port (exited $($Proc.ExitCode)): $buf $tail $err")
        }
        $ms = [int]($deadline - [DateTime]::UtcNow).TotalMilliseconds
        if ($ms -lt 1) { break }
        $task = $Proc.StandardOutput.ReadLineAsync()
        if (-not $task.Wait($ms)) { break }
        $line = $task.Result
        if ($null -eq $line) { Start-Sleep -Milliseconds 50; continue }
        [void]$buf.AppendLine($line)
        if ($line -match "listening on 127.0.0.1:(\d+)") { return [int]$Matches[1] }
    }
    $err = ""
    try { $err = $Proc.StandardError.ReadToEnd() } catch { }
    throw "no listen port: $buf $err"
}

