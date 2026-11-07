# Local Windows / Grok Build CLI handoff

Do not run this on a cloud agent. Do not touch production, OBS, Station, or secrets. Isolated scratch checkout only.

## Exact ref

- Remote: `https://github.com/CannaMuffinMan/vire`
- Branch: `cursor/integrate-perf-38-0258`
- SHA: see the tip of that branch after fetch (this file is updated when the SHA is known)
- Depends on: PR #38 `e0d70a075147113a1d3ba569fad879f8982224ea` plus the compiler stack through PR #37 `f119db8db2e9ff2b8bad5c35761886dbf76ebf50`
- Do not check out `cursor/native-runtime-32mb-0b9c` to apply these compiler commits. That branch stays PR #38.

## Caps (unchanged)

```text
set VIRE_BUDGET=5000000
```

Native arena 32MB. Host list cap 100000. Do not raise them.

## Isolated workspace

```text
git clone https://github.com/CannaMuffinMan/vire C:\scratch\vire-integrate-38
cd C:\scratch\vire-integrate-38
git fetch origin cursor/integrate-perf-38-0258
git checkout --detach origin/cursor/integrate-perf-38-0258
dotnet build vire.csproj -c Release
```

## Stage compiler sources (read stays data/site)

```text
bash tools/stage-compiler-src.sh
```

If bash is missing, copy `compile-native.vire` to `data\compile-native.vire` and copy `src\asm.vire`, `src\pe.vire`, `src\rt.vire`, `src\rt-more.vire` into `data\src\`. SHA-256 of each pair must match.

## Commands, timeouts, expected

Host emit hello (timeout 30s):

```text
dotnet exec bin\Release\net10.0\vire.dll compile-native.vire data\guest-hello.vire data\guest-hello.hex
```

Expect `compiled` exit 0. Linux integrated tree: about 1.1–1.3s. Do not treat Linux times as Windows.

Run the PE on Windows (timeout 10s):

```text
certutil -hashfile data\guest-hello.hex SHA256
python -c "p=open('data/guest-hello.hex').read().strip(); open('data/guest-hello.exe','wb').write(bytes.fromhex(p))"
data\guest-hello.exe
echo %ERRORLEVEL%
```

Expect stdout `hello from stage` and exit 0. If that fails, stop. Do not fall back to Unicorn as a Win32 proof.

Host emit of the compiler as a `data/` guest (timeout 180s, stop if longer):

```text
dotnet exec bin\Release\net10.0\vire.dll compile-native.vire data\compile-native.vire data\gen1.hex
```

Linux did this in 66s. If it OOMs or exceeds 180s, log the message and stop.

Optional native gen1 run on Windows (timeout 10 minutes, then stop):

```text
python -c "p=open('data/gen1.hex').read().strip(); open('data/gen1.exe','wb').write(bytes.fromhex(p))"
data\gen1.exe data\guest-hello.vire data\gen1-hello.hex
```

Expect `compiled`. Then run the new PE for `hello from stage`. Then:

```text
data\gen1.exe data\compile-native.vire data\gen2.hex
certutil -hashfile data\gen1.hex SHA256
certutil -hashfile data\gen2.hex SHA256
```

gen1 SHA == gen2 SHA is the fixed-point proof. Anything else is not.

## Logs to keep

- stdout/stderr of each command
- SHA-256 of `data\guest-hello.hex`, `data\gen1.hex`, `data\gen2.hex`
- wall times
- first error line if a step fails

## Stop criteria

- Stop at the first missing `data/src` read, 32MB / out of memory, step-budget stop, or timeout.
- Do not run `tools/native-selfhost-proof.ps1` overnight.
- Do not merge, deploy, or change OBS.
- Unicorn on Linux is not this proof.

## Tests that already passed on Linux (not Windows)

`dotnet test tests/Vire.Tests/Vire.Tests.csproj -c Release --filter "FullyQualifiedName~CompilerStage|FullyQualifiedName~NativeExtend|FullyQualifiedName~NativePath|FullyQualifiedName~NativeArena|FullyQualifiedName~NativePe|FullyQualifiedName~Extend|FullyQualifiedName~PathSsrf|FullyQualifiedName~EmitU8|FullyQualifiedName~HexOf|FullyQualifiedName~BudgetCap"`

42 passed on the integrated tree. Re-run on Windows if you want a Windows xUnit log. Do not skip NativePath / Arena.
