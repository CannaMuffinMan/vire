# Fail-closed runner: one folder, one vire.project, then the entry.
# Format (program root):
#   entry <relative-path>
#   need <package>
#   target c|android|driver
#   source <relative-path>
# Package names are ASCII letters, digits, and underscore. No secrets.
# Each need must be in deps.lock and the lock hash must match deps/<name>/lib.vire bytes.
# target and source are optional. target may appear once. source may appear once.
# If target is set and source is omitted, the C file is hello.c in the project folder.
# Missing entry, a second entry, a missing package, or a bad hash exits 1.
# A target whose data output file is missing exits 1.
param(
    [Parameter(Mandatory = $true, Position = 0)]
    [string]$Project
)

$ErrorActionPreference = "Stop"
$PSNativeCommandUseErrorActionPreference = $false

function Fail([string]$Message) {
    [Console]::Error.WriteLine($Message)
    exit 1
}

$cap = 5000000
$rawBudget = $env:VIRE_BUDGET
if ([string]::IsNullOrWhiteSpace($rawBudget)) {
    $env:VIRE_BUDGET = "$cap"
} else {
    $parsed = 0
    if (-not [int]::TryParse($rawBudget.Trim(), [ref]$parsed) -or $parsed -lt 1 -or $parsed -gt $cap) {
        Fail "error: VIRE_BUDGET must be from 1 to $cap"
    }
}

$Repo = Split-Path -Parent $PSScriptRoot
if (-not [System.IO.Path]::IsPathRooted($Project)) {
    $Project = Join-Path $Repo $Project
}
$Project = [System.IO.Path]::GetFullPath($Project)
if (-not (Test-Path -LiteralPath $Project -PathType Container)) {
    Fail "error: missing project $Project"
}

$projectFile = Join-Path $Project "vire.project"
if (-not (Test-Path -LiteralPath $projectFile -PathType Leaf)) {
    Fail "error: missing vire.project"
}

$utf8 = New-Object System.Text.UTF8Encoding $false
$text = [System.IO.File]::ReadAllText($projectFile, $utf8)
$text = $text.Replace("`r`n", "`n").Replace("`r", "`n")

$entries = New-Object System.Collections.Generic.List[string]
$needs = New-Object System.Collections.Generic.List[string]
$seenNeed = @{}
$targets = New-Object System.Collections.Generic.List[string]
$sources = New-Object System.Collections.Generic.List[string]

foreach ($rawLine in $text.Split("`n")) {
    $line = $rawLine.Trim()
    if ($line.Length -eq 0) { continue }
    $space = $line.IndexOf(" ")
    if ($space -le 0) { Fail "error: damaged vire.project" }
    $key = $line.Substring(0, $space)
    $value = $line.Substring($space + 1)
    if ($value.Length -eq 0 -or $value.IndexOf(" ") -ge 0) { Fail "error: damaged vire.project" }
    if ($key -eq "entry") {
        $entries.Add($value)
        continue
    }
    if ($key -eq "need") {
        if ($value -notmatch '^[A-Za-z0-9_]+$') { Fail "error: damaged vire.project" }
        if ($seenNeed.ContainsKey($value)) { Fail "error: damaged vire.project" }
        $seenNeed[$value] = $true
        $needs.Add($value)
        continue
    }
    if ($key -eq "target") {
        if ($value -ne "c" -and $value -ne "android" -and $value -ne "driver") { Fail "error: damaged vire.project" }
        $targets.Add($value)
        continue
    }
    if ($key -eq "source") {
        $sources.Add($value)
        continue
    }
    Fail "error: damaged vire.project"
}

if ($entries.Count -eq 0) { Fail "error: missing entry" }
if ($entries.Count -gt 1) { Fail "error: second entry" }
if ($targets.Count -gt 1) { Fail "error: second target" }
if ($sources.Count -gt 1) { Fail "error: second source" }
if ($sources.Count -gt 0 -and $targets.Count -eq 0) { Fail "error: damaged vire.project" }

function Resolve-Inside([string]$Relative) {
    if ($Relative.IndexOf(":") -ge 0) { Fail "error: damaged vire.project" }
    $rootFull = $Project
    if (-not $rootFull.EndsWith("\") -and -not $rootFull.EndsWith("/")) { $rootFull = $rootFull + [System.IO.Path]::DirectorySeparatorChar }
    $combined = Join-Path $Project $Relative
    $full = [System.IO.Path]::GetFullPath($combined)
    if (-not $full.StartsWith($rootFull, [System.StringComparison]::OrdinalIgnoreCase)) {
        Fail "error: path leaves the project"
    }
    if (Test-Path -LiteralPath $full) {
        $item = Get-Item -LiteralPath $full -Force
        if (($item.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0) {
            Fail "error: path leaves the project"
        }
    }
    return $full
}

$entryRel = $entries[0]
$entryPath = Resolve-Inside $entryRel
if (-not (Test-Path -LiteralPath $entryPath -PathType Leaf)) { Fail "error: missing entry" }

$lockPath = Join-Path $Project "deps.lock"
$lock = @{}
if (Test-Path -LiteralPath $lockPath) {
    $lockItem = Get-Item -LiteralPath $lockPath -Force
    if (($lockItem.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0) {
        Fail "error: path leaves the project"
    }
    $lockText = [System.IO.File]::ReadAllText($lockPath, $utf8).Replace("`r`n", "`n").Replace("`r", "`n")
    foreach ($rawLine in $lockText.Split("`n")) {
        if ($rawLine.Length -eq 0) { continue }
        $space = $rawLine.IndexOf(" ")
        if ($space -le 0 -or $rawLine.IndexOf(" ", $space + 1) -ge 0) { Fail "error: deps.lock is damaged" }
        $name = $rawLine.Substring(0, $space)
        $hex = $rawLine.Substring($space + 1)
        if ($name -notmatch '^[A-Za-z0-9_]+$' -or $hex -notmatch '^[0-9a-f]{64}$' -or $lock.ContainsKey($name)) {
            Fail "error: deps.lock is damaged"
        }
        $lock[$name] = $hex
    }
} elseif ($needs.Count -gt 0) {
    Fail "error: missing package"
}

$sha = [System.Security.Cryptography.SHA256]::Create()
try {
    foreach ($name in $needs) {
        if (-not $lock.ContainsKey($name)) { Fail "error: missing package $name" }
        $libRel = "deps/" + $name + "/lib.vire"
        $libPath = Resolve-Inside $libRel
        if (-not (Test-Path -LiteralPath $libPath -PathType Leaf)) { Fail "error: missing package $name" }
        $bytes = [System.IO.File]::ReadAllBytes($libPath)
        $hash = ([BitConverter]::ToString($sha.ComputeHash($bytes))).Replace("-", "").ToLowerInvariant()
        if ($hash -ne $lock[$name]) { Fail "error: bad hash $name" }
    }
} finally {
    $sha.Dispose()
}

$Dll = Join-Path $Repo "bin/Release/net10.0/vire.dll"
if (-not (Test-Path -LiteralPath $Dll)) {
    Write-Output "building Release"
    & dotnet build (Join-Path $Repo "vire.csproj") -c Release --nologo
    if ($LASTEXITCODE -ne 0) { exit 1 }
}
if (-not (Test-Path -LiteralPath $Dll)) { Fail "error: missing $Dll" }

if ($targets.Count -eq 1) {
    $kind = $targets[0]
    $sourceRel = "hello.c"
    if ($sources.Count -eq 1) { $sourceRel = $sources[0] }
    $sourcePath = Resolve-Inside $sourceRel
    if (-not (Test-Path -LiteralPath $sourcePath -PathType Leaf)) { Fail "error: missing source" }
    $stem = [System.IO.Path]::GetFileNameWithoutExtension($sourceRel)
    $suffix = ".exe"
    if ($kind -eq "android") { $suffix = ".so" }
    if ($kind -eq "driver") { $suffix = ".sys" }
    $outRel = "data/" + $stem + $suffix
    $outPath = Resolve-Inside $outRel
    $quotedKind = $kind.Replace("\", "\\").Replace('"', '\"')
    $quotedSource = $sourceRel.Replace("\", "\\").Replace('"', '\"')
    $genRel = "target-build.vire"
    $genPath = Resolve-Inside $genRel
    $gen = "define main`n  say (build with `"$quotedKind`", `"$quotedSource`")`nend`n"
    [System.IO.File]::WriteAllText($genPath, $gen, $utf8)
    Write-Output "dotnet exec bin/Release/net10.0/vire.dll $genRel"
    & dotnet exec $Dll $genPath
    if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
    if (-not (Test-Path -LiteralPath $outPath -PathType Leaf)) { Fail "error: missing $outRel" }
}

Write-Output "dotnet exec bin/Release/net10.0/vire.dll $entryRel"
& dotnet exec $Dll $entryPath
exit $LASTEXITCODE
