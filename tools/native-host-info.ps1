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
