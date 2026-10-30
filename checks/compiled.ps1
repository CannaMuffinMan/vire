Set-Location -LiteralPath "D:\_scratch\vire"

$programs = @(
    @{ Src = "data/hello.vire"; Want = "hello from vire" },
    @{ Src = "data/count.vire"; Want = "5" },
    @{ Src = "data/loop.vire"; Want = "3" }
)

$failed = $false
foreach ($program in $programs) {
    $src = $program.Src
    $vc = $src.Substring(0, $src.Length - 5) + ".vc"
    & dotnet run -c Release --no-build -- compiler.vire $src $vc | Out-Null
    if ($LASTEXITCODE -ne 0) {
        Write-Output "FAIL $src"
        $failed = $true
        continue
    }
    $lines = & dotnet run -c Release --no-build -- run $vc
    if ($LASTEXITCODE -ne 0) {
        Write-Output "FAIL $src"
        $failed = $true
        continue
    }
    $got = ""
    if ($null -ne $lines) {
        if ($lines -is [System.Array]) {
            $got = (($lines | ForEach-Object { [string]$_ }) -join "`n").Trim()
        } else {
            $got = ([string]$lines).Trim()
        }
    }
    if ($got -eq $program.Want) {
        Write-Output "PASS $src"
    } else {
        Write-Output "FAIL $src"
        $failed = $true
    }
}

if ($failed) { exit 1 }
exit 0
