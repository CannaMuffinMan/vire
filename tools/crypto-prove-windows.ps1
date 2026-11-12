$ErrorActionPreference = "Stop"
$Root = Split-Path -Parent $PSScriptRoot
Set-Location -LiteralPath $Root
$env:VIRE_BUDGET = "5000000"
$env:VIRE_HEADLESS = "1"
$VireDll = Join-Path $Root "bin/Release/net10.0/vire.dll"
if (-not (Test-Path $VireDll)) { throw "missing $VireDll" }

function Convert-HexToExe([string]$HexPath, [string]$ExePath) {
    $hex = [System.IO.File]::ReadAllText($HexPath).Trim()
    if ($hex.Length -eq 0 -or ($hex.Length % 2) -ne 0) { throw "bad hex $HexPath" }
    $bytes = New-Object byte[] ($hex.Length / 2)
    for ($i = 0; $i -lt $bytes.Length; $i++) {
        $bytes[$i] = [Convert]::ToByte($hex.Substring($i * 2, 2), 16)
    }
    [System.IO.File]::WriteAllBytes($ExePath, $bytes)
}

Write-Output "crypto_host_start"
$sw = [System.Diagnostics.Stopwatch]::StartNew()
$hostOut = & dotnet exec $VireDll crypto-prove.vire
$code = $LASTEXITCODE
$sw.Stop()
Write-Output $hostOut
Write-Output "crypto_host_sec $($sw.Elapsed.TotalSeconds.ToString('0.000'))"
Write-Output "crypto_host_exit $code"
if ($code -ne 0) { throw "host crypto-prove exit $code" }
if ("$hostOut" -notmatch "CRYPTO PROVE pass") { throw "host crypto-prove missing pass" }

$sw = [System.Diagnostics.Stopwatch]::StartNew()
$mbOut = & dotnet exec $VireDll crypto-mb.vire
$mbCode = $LASTEXITCODE
$sw.Stop()
Write-Output $mbOut
Write-Output "sha256_1mb_sec $($sw.Elapsed.TotalSeconds.ToString('0.000'))"
Write-Output "sha256_1mb_exit $mbCode"
if ($mbCode -ne 0) { throw "crypto-mb exit $mbCode" }
if ("$mbOut" -notmatch "cdc76e5c9914fb9281a1c7e284d73e67f1809a48a497200e046d39ccc7112cd0") {
    throw "crypto-mb missing FIPS 1M digest"
}

$Data = Join-Path $Root "data"
New-Item -ItemType Directory -Force -Path $Data | Out-Null
$lib = Get-Content -Raw (Join-Path $Root "src/rt-crypto.vire")
$prove = Get-Content -Raw (Join-Path $Root "crypto-prove.vire")
$prove = $prove -replace '(?m)^use "src/rt-crypto.vire"\s*', ''
Set-Content -Path (Join-Path $Data "crypto-prove.vire") -Value ($lib + "`n" + $prove) -NoNewline
$hexRel = "data/crypto-prove.hex"
$sw = [System.Diagnostics.Stopwatch]::StartNew()
$compileOut = & dotnet exec $VireDll --compiler compile-native.vire data/crypto-prove.vire $hexRel
$compileCode = $LASTEXITCODE
$sw.Stop()
Write-Output $compileOut
Write-Output "crypto_pe_compile_sec $($sw.Elapsed.TotalSeconds.ToString('0.000'))"
Write-Output "crypto_pe_compile_exit $compileCode"
if ($compileCode -ne 0) { throw "compile-native crypto-prove exit $compileCode" }
if ("$compileOut" -notmatch "compiled") { throw "compile-native missing compiled" }

$exe = Join-Path $Data "crypto-prove.exe"
Convert-HexToExe (Join-Path $Root $hexRel) $exe
$sw = [System.Diagnostics.Stopwatch]::StartNew()
$peOut = & $exe
$peCode = $LASTEXITCODE
$sw.Stop()
Write-Output $peOut
Write-Output "crypto_pe_sec $($sw.Elapsed.TotalSeconds.ToString('0.000'))"
Write-Output "crypto_pe_exit $peCode"
if ($peCode -ne 0) { throw "crypto PE exit $peCode" }
$hostNorm = (($hostOut | Out-String) -replace '\r','').Trim()
$peNorm = (($peOut | Out-String) -replace '\r','').Trim()
if ($hostNorm -ne $peNorm) {
    Write-Output "HOST_PE_MISMATCH"
    throw "host interpreter and gen1 PE stdout differ"
}
Write-Output "crypto host pe match"

$mbSrc = Get-Content -Raw (Join-Path $Root "crypto-mb.vire")
Set-Content -Path (Join-Path $Data "crypto-mb.vire") -Value $mbSrc -NoNewline
$mbHexRel = "data/crypto-mb.hex"
$sw = [System.Diagnostics.Stopwatch]::StartNew()
$mbCompile = & dotnet exec $VireDll --compiler compile-native.vire data/crypto-mb.vire $mbHexRel
$mbCompileCode = $LASTEXITCODE
$sw.Stop()
Write-Output $mbCompile
Write-Output "crypto_mb_pe_compile_sec $($sw.Elapsed.TotalSeconds.ToString('0.000'))"
Write-Output "crypto_mb_pe_compile_exit $mbCompileCode"
if ($mbCompileCode -ne 0) { throw "compile-native crypto-mb exit $mbCompileCode" }
if ("$mbCompile" -notmatch "compiled") { throw "compile-native crypto-mb missing compiled" }
$mbExe = Join-Path $Data "crypto-mb.exe"
Convert-HexToExe (Join-Path $Root $mbHexRel) $mbExe
$sw = [System.Diagnostics.Stopwatch]::StartNew()
$mbPeOut = & $mbExe
$mbPeCode = $LASTEXITCODE
$sw.Stop()
Write-Output $mbPeOut
Write-Output "crypto_mb_pe_sec $($sw.Elapsed.TotalSeconds.ToString('0.000'))"
Write-Output "crypto_mb_pe_exit $mbPeCode"
if ($mbPeCode -ne 0) { throw "crypto-mb PE exit $mbPeCode" }
if ("$mbPeOut" -notmatch "cdc76e5c9914fb9281a1c7e284d73e67f1809a48a497200e046d39ccc7112cd0") {
    throw "crypto-mb PE missing FIPS 1M digest"
}
Write-Output "crypto mb pe ok"

$shaProg = Join-Path $Root "tests/kdf-sha-password.vire"
$shaOut = (& dotnet exec $VireDll $shaProg | Out-String).Trim()
$bcryptVec = '$2b$04$......................LAtw7/ohmmBAhnXqmkuIz83Rl5Qdjhm'
if ($shaOut -eq $bcryptVec) { throw "SHA-256 unexpectedly equals bcrypt vector" }
$baseCrypto = git -C $Root show d89edb29743c580613816d19cb1e7c749bce71e6:src/rt-crypto.vire
if ($baseCrypto -match "bcrypt") { throw "base rt-crypto already has bcrypt" }
Write-Output "FAIL_BEFORE at d89edb29743c580613816d19cb1e7c749bce71e6: canonical bcrypt vector does not verify (no KDF / SHA-256 $shaOut != $bcryptVec)"

Write-Output "kdf_host_start"
$sw = [System.Diagnostics.Stopwatch]::StartNew()
$kdfHost = & dotnet exec $VireDll kdf-prove.vire
$kdfCode = $LASTEXITCODE
$sw.Stop()
Write-Output $kdfHost
Write-Output "kdf_host_sec $($sw.Elapsed.TotalSeconds.ToString('0.000'))"
Write-Output "kdf_host_exit $kdfCode"
if ($kdfCode -ne 0) { throw "host kdf-prove exit $kdfCode" }
if ("$kdfHost" -notmatch "KDF PROVE pass") { throw "host kdf-prove missing pass" }

$kdfLib = Get-Content -Raw (Join-Path $Root "src/rt-kdf.vire")
$kdfProve = Get-Content -Raw (Join-Path $Root "kdf-prove.vire")
$kdfProve = $kdfProve -replace '(?m)^use "src/rt-kdf.vire"\s*', ''
Set-Content -Path (Join-Path $Data "kdf-prove.vire") -Value ($kdfLib + "`n" + $kdfProve) -NoNewline
$kdfHexRel = "data/kdf-prove.hex"
$sw = [System.Diagnostics.Stopwatch]::StartNew()
$kdfCompile = & dotnet exec $VireDll --compiler compile-native.vire data/kdf-prove.vire $kdfHexRel
$kdfCompileCode = $LASTEXITCODE
$sw.Stop()
Write-Output $kdfCompile
Write-Output "kdf_pe_compile_sec $($sw.Elapsed.TotalSeconds.ToString('0.000'))"
Write-Output "kdf_pe_compile_exit $kdfCompileCode"
if ($kdfCompileCode -ne 0) { throw "compile-native kdf-prove exit $kdfCompileCode" }
if ("$kdfCompile" -notmatch "compiled") { throw "compile-native kdf-prove missing compiled" }
$kdfExe = Join-Path $Data "kdf-prove.exe"
Convert-HexToExe (Join-Path $Root $kdfHexRel) $kdfExe
$sw = [System.Diagnostics.Stopwatch]::StartNew()
$kdfPeOut = & $kdfExe
$kdfPeCode = $LASTEXITCODE
$sw.Stop()
Write-Output $kdfPeOut
Write-Output "kdf_pe_sec $($sw.Elapsed.TotalSeconds.ToString('0.000'))"
Write-Output "kdf_pe_exit $kdfPeCode"
if ($kdfPeCode -ne 0) { throw "kdf PE exit $kdfPeCode" }
$kdfHostNorm = (($kdfHost | Out-String) -replace '\r','').Trim()
$kdfPeNorm = (($kdfPeOut | Out-String) -replace '\r','').Trim()
if ($kdfHostNorm -ne $kdfPeNorm) {
    Write-Output "HOST_PE_MISMATCH"
    throw "host interpreter and gen1 PE kdf stdout differ"
}
Write-Output "PASS_AFTER host and gen1 PE bcrypt outputs identical"
Write-Output "kdf host pe match"
Write-Output "crypto windows prove ok"
