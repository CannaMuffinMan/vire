# Fail-before / pass-after: PE rt_push list gate matches host 100000.
# Does not raise the 32MB arena, 2e6 spin cap, 5e6 step cap, or the list cap.
$ErrorActionPreference = "Stop"
$Root = Split-Path -Parent $PSScriptRoot
Set-Location -LiteralPath $Root
$env:VIRE_BUDGET = "5000000"
git fetch origin native-compiler
$BaseSha = "5b10ea5fa5eea46859f17a52b36037d9d088c01d"
$AfterSha = (git rev-parse HEAD).Trim()
Write-Output "fail_before_sha $BaseSha"
Write-Output "pass_after_sha $AfterSha"

$VireDll = Join-Path $Root "bin/Release/net10.0/vire.dll"
function Invoke-Vire {
    param([Parameter(ValueFromRemainingArguments = $true)][string[]]$Args)
    $leaf = [IO.Path]::GetFileName($Args[0])
    $savedBudget = $env:VIRE_BUDGET
    if ($leaf -eq "compile-native.vire" -or $leaf -eq "compiler.vire") {
        $Args = @("--compiler") + $Args
        Remove-Item Env:VIRE_BUDGET -ErrorAction SilentlyContinue
    }
    $outFile = Join-Path $Root ("data/native-list-cap/invoke-" + [guid]::NewGuid().ToString("N") + ".out")
    $errFile = "$outFile.err"
    try {
        $p = Start-Process -FilePath "dotnet" -ArgumentList (@("exec", $VireDll) + $Args) -WorkingDirectory $Root -NoNewWindow -PassThru -Wait -RedirectStandardOutput $outFile -RedirectStandardError $errFile
        $stdout = if (Test-Path $outFile) { Get-Content -Raw $outFile } else { "" }
        $stderr = if (Test-Path $errFile) { Get-Content -Raw $errFile } else { "" }
        if ($stdout) { Write-Host $stdout.TrimEnd() }
        if ($stderr) { Write-Host $stderr.TrimEnd() }
        $code = $p.ExitCode
        if ($null -eq $code) { $code = 0 }
        return @{ Exit = [int]$code; Out = "$stdout".Trim(); Err = "$stderr".Trim() }
    } finally {
        if ($savedBudget) { $env:VIRE_BUDGET = $savedBudget }
        if (Test-Path $outFile) { Remove-Item -Force $outFile }
        if (Test-Path $errFile) { Remove-Item -Force $errFile }
    }
}

function Convert-HexToExe {
    param([string]$HexPath, [string]$ExePath)
    $hex = [System.IO.File]::ReadAllText($HexPath).Trim()
    $bytes = New-Object byte[] ($hex.Length / 2)
    for ($i = 0; $i -lt $bytes.Length; $i++) {
        $bytes[$i] = [Convert]::ToByte($hex.Substring($i * 2, 2), 16)
    }
    [System.IO.File]::WriteAllBytes($ExePath, $bytes)
}

function Compile-Run {
    param([string]$Name, [string]$Src)
    $work = Join-Path $Root "data/native-list-cap"
    New-Item -ItemType Directory -Force -Path $work | Out-Null
    $srcRel = "data/native-list-cap/$Name.vire"
    $hexRel = "data/native-list-cap/$Name.hex"
    $body = [IO.File]::ReadAllText($Src)
    $cn = [IO.File]::ReadAllText((Join-Path $Root "compile-native.vire"))
    if ($cn -notmatch '(?m)^can ') {
        $body = [regex]::Replace($body, '(?m)^can .*\r?\n?', "")
    }
    [IO.File]::WriteAllText((Join-Path $Root $srcRel), $body)
    $compiled = Invoke-Vire compile-native.vire $srcRel $hexRel
    if ($compiled.Exit -ne 0) { throw "compile $Name failed exit=$($compiled.Exit)" }
    $exe = Join-Path $work "$Name.exe"
    Convert-HexToExe (Join-Path $Root $hexRel) $exe
    $outFile = Join-Path $work "$Name.out.txt"
    $errFile = Join-Path $work "$Name.err.txt"
    $inFile = Join-Path $work "$Name.in.txt"
    Set-Content -Path $inFile -Value "" -NoNewline
    if (Test-Path $outFile) { Remove-Item -Force $outFile }
    if (Test-Path $errFile) { Remove-Item -Force $errFile }
    $p = Start-Process -FilePath $exe -WorkingDirectory $Root -NoNewWindow -PassThru -Wait -RedirectStandardInput $inFile -RedirectStandardOutput $outFile -RedirectStandardError $errFile
    $got = if (Test-Path $outFile) { (Get-Content -Raw $outFile) } else { "" }
    $err = if (Test-Path $errFile) { (Get-Content -Raw $errFile) } else { "" }
    return @{ Exit = [int]$p.ExitCode; Out = "$got".Trim(); Err = "$err".Trim(); Exe = $exe }
}

function Restore-RuntimeFrom {
    param([string]$Sha)
    git cat-file -e "$Sha^{commit}" 2>$null
    if ($LASTEXITCODE -ne 0) {
        git fetch --depth 1 origin $Sha
        git cat-file -e "$Sha^{commit}" 2>$null
        if ($LASTEXITCODE -ne 0) { throw "missing commit $Sha" }
    }
    git checkout $Sha -- src/rt.vire src/rt-more.vire data/src/rt.vire data/src/rt-more.vire compile-native.vire data/compile-native.vire
    if ($LASTEXITCODE -ne 0) { throw "checkout runtime from $Sha failed" }
}

function Host-Message {
    param([string]$Err)
    $line = "$Err".Trim()
    if ($line -match "list is too large") {
        return "list is too large"
    }
    return $line
}

$Work = Join-Path $Root "data/native-list-cap"
if (Test-Path $Work) { Remove-Item -Recurse -Force $Work }
New-Item -ItemType Directory -Path $Work | Out-Null
$Src = Join-Path $Root "tests/native/list-cap.vire"

Write-Output "phase fail-before $BaseSha"
Restore-RuntimeFrom $BaseSha
$before = Compile-Run "list-cap-before" $Src
Write-Output "before_pe exit=$($before.Exit) out=$($before.Out)"
if ($before.Exit -eq 0 -and $before.Out -eq "100001") {
    Write-Output "FAIL_BEFORE at ${BaseSha}: 100001 pushes succeed"
} else {
    throw "fail-before expected PE length 100001 exit 0, got exit=$($before.Exit) out=$($before.Out)"
}

Write-Output "phase pass-after $AfterSha"
Restore-RuntimeFrom $AfterSha
$after = Compile-Run "list-cap-after" $Src
Write-Output "after_pe exit=$($after.Exit) out=$($after.Out) err=$($after.Err)"
if (-not ($after.Exit -eq 1 -and ($after.Out.Contains("list is too large") -or $after.Err.Contains("list is too large")) -and -not $after.Out.Contains("crash rip="))) {
    throw "pass-after PE expected list is too large exit 1, got exit=$($after.Exit) out=$($after.Out) err=$($after.Err)"
}

$hostRun = Invoke-Vire $Src
Write-Output "after_host exit=$($hostRun.Exit) out=$($hostRun.Out) err=$($hostRun.Err)"
if ($hostRun.Exit -ne 1) { throw "pass-after host expected exit 1, got $($hostRun.Exit)" }
$hostMsg = Host-Message $hostRun.Err
if ($hostMsg -ne "list is too large") { throw "pass-after host message $hostMsg" }
$peMsg = Host-Message $(if ($after.Out.Contains("list is too large")) { $after.Out } else { $after.Err })
if ($hostMsg -ne $peMsg) { throw "host stdout != gen1 PE stdout host=$hostMsg pe=$peMsg" }
Write-Output "host stdout == gen1 PE stdout"
Write-Output "PASS_AFTER at ${AfterSha}: push 100001 rejected same as host"
Write-Output "native list-cap proof ok"
exit 0
