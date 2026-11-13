# Windows PE gen1 emits a Linux ELF hello hex for the Ubuntu cross-target job.
$ErrorActionPreference = "Stop"
$Root = Split-Path -Parent $PSScriptRoot
Set-Location -LiteralPath $Root
. (Join-Path $PSScriptRoot "native-host-info.ps1")
$env:VIRE_HEADLESS = "1"
Remove-Item Env:VIRE_BUDGET -ErrorAction SilentlyContinue
$Data = Join-Path $Root "data"
$Src = Join-Path $Data "src"
New-Item -ItemType Directory -Force -Path $Src | Out-Null
$VireDll = Join-Path $Root "bin/Release/net10.0/vire.dll"
if (-not (Test-Path $VireDll)) { throw "missing $VireDll" }

function Convert-HexToBin([string]$HexPath, [string]$BinPath) {
    $hex = [System.IO.File]::ReadAllText($HexPath).Trim()
    if ($hex.Length -eq 0 -or ($hex.Length % 2) -ne 0) { throw "bad hex $HexPath" }
    $bytes = New-Object byte[] ($hex.Length / 2)
    for ($i = 0; $i -lt $bytes.Length; $i++) {
        $bytes[$i] = [Convert]::ToByte($hex.Substring($i * 2, 2), 16)
    }
    [System.IO.File]::WriteAllBytes($BinPath, $bytes)
}

Copy-Item (Join-Path $Root "compile-native.vire") (Join-Path $Data "compile-native.vire") -Force
Copy-Item (Join-Path $Root "src/asm.vire") (Join-Path $Src "asm.vire") -Force
Copy-Item (Join-Path $Root "src/pe.vire") (Join-Path $Src "pe.vire") -Force
Copy-Item (Join-Path $Root "src/rt.vire") (Join-Path $Src "rt.vire") -Force
Copy-Item (Join-Path $Root "src/rt-more.vire") (Join-Path $Src "rt-more.vire") -Force
Copy-Item (Join-Path $Root "src/rt-net.vire") (Join-Path $Src "rt-net.vire") -Force
Copy-Item (Join-Path $Root "src/elf.vire") (Join-Path $Src "elf.vire") -Force
Copy-Item (Join-Path $Root "src/rt-linux.vire") (Join-Path $Src "rt-linux.vire") -Force
foreach ($blob in @(
    "rt-net-blob.txt", "rt-net-pins.txt", "rt-net-fixes.txt",
    "rt-net-json-blob.txt", "rt-net-json-pins.txt", "rt-net-json-fixes.txt"
)) {
    Copy-Item (Join-Path $Root "src/$blob") (Join-Path $Src $blob) -Force
}
Copy-Item (Join-Path $Root "guest-hello.vire") (Join-Path $Data "guest-hello.vire") -Force

$gen1Hex = Join-Path $Data "win-gen1.hex"
$gen1Exe = Join-Path $Data "win-gen1.exe"
if (Test-Path $gen1Hex) { Remove-Item -Force $gen1Hex }
Write-Output "win_gen1_host_start"
& dotnet exec $VireDll --compiler compile-native.vire data/compile-native.vire data/win-gen1.hex
if ($LASTEXITCODE -ne 0) { throw "win gen1 host exit $LASTEXITCODE" }
Convert-HexToBin $gen1Hex $gen1Exe
Write-Output ("win_gen1_exe_bytes " + (Get-Item $gen1Exe).Length)
try { Unblock-File -Path $gen1Exe } catch { }

$helloHex = Join-Path $Data "win-linux-hello.hex"
if (Test-Path $helloHex) { Remove-Item -Force $helloHex }
Write-Output "win_gen1_elf_hello_start"
& $gen1Exe data/guest-hello.vire data/win-linux-hello.hex elf
if ($LASTEXITCODE -ne 0) { throw "win gen1 elf hello exit $LASTEXITCODE" }
$hex = [System.IO.File]::ReadAllText($helloHex).Trim()
if ($hex.Substring(0, 8) -ne "7f454c46") { throw "win linux hello is not ELF hex" }
Write-Output ("win_linux_hello_hex_bytes " + ($hex.Length / 2))
Write-Output "win_pe_compiler_emitted_real_elf_hello"
