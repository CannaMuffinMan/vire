# Vire

Vire is a small programming language. Programs are `.vire` files.

**Host** is the .NET interpreter. Anyone with Docker or the .NET 10 SDK can run `.vire` files that way. That runner is not a native compiler.

**Native** is a Windows PE emitted by `compile-native.vire`. The PE is x64 Windows only. It does not use .NET. Standing on its own means a gen1 PE compiles `compile-native.vire` to a gen2 PE whose hex matches gen1.

The language manual is [docs/LANGUAGE.md](docs/LANGUAGE.md). The older tour is [GUIDE.md](GUIDE.md). Binaries are not stored in git. GitHub Actions uploads single-file host builds as workflow artifacts.

## Clean machine (native only)

On a Windows machine that already has `gen1.exe` (a PE of `compile-native.vire`) and this source tree, you do not need .NET on PATH.

```text
REM PATH must not contain dotnet
where dotnet
REM expected: INFO: Could not find files for the given pattern(s).

gen1.exe data\compile-native.vire data\gen2.hex
```

`tools/clean-machine-native.ps1` strips `dotnet` from PATH, then runs `gen1.exe` on a guest under `data/`. CI job `clean-machine` in `.github/workflows/lang-types-caps.yml` proves that recipe.

## Run with Docker

This does not depend on a Windows PC.

```text
docker build -t vire .
docker run --rm vire tests.vire
```

`tests.vire` is inside the image. It should print `pass`.

To run your own program, mount the folder that contains it:

```text
docker run --rm -v "$PWD":/work vire my.vire
```

On Windows PowerShell, if Docker cannot mount the drive, copy the program into a folder on `C:` or keep using the files already in the image: `tests.vire`, `count.vire`, `term.vire`, and `vault.vire`.

## Run with .NET 10

```text
dotnet build -c Release
dotnet test tests/Vire.Tests/Vire.Tests.csproj -c Release
dotnet run -c Release -- tests.vire
```

That runner uses the terminal. `open` and `show` do not draw a desktop window.

Publish a single file for another machine:

```text
dotnet publish -c Release -r linux-x64 --self-contained true -p:PublishSingleFile=true -o dist/linux-x64
dotnet publish -c Release -r linux-arm64 --self-contained true -p:PublishSingleFile=true -o dist/linux-arm64
dotnet publish -c Release -r osx-x64 --self-contained true -p:PublishSingleFile=true -o dist/osx-x64
dotnet publish -c Release -r osx-arm64 --self-contained true -p:PublishSingleFile=true -o dist/osx-arm64
dotnet publish -c Release -r win-x64 --self-contained true -p:PublishSingleFile=true -o dist/win-x64
```

## Windows desktop window

`vire.windows.csproj` opens a real window for `work.vire` and `board.vire`. Build it with:

```text
dotnet build windows/vire.windows.csproj -c Release
dotnet publish windows/vire.windows.csproj -c Release -r win-x64 --self-contained true -p:PublishSingleFile=true -o dist/win-x64-windows
```

## License

MIT. See [LICENSE](LICENSE).
