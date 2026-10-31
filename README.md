# Vire

Vire is a small programming language. Programs are `.vire` files. Anyone with Docker, or the .NET 10 SDK, can run them. A Windows desktop build can also open a window. Binaries are not stored in git. GitHub Actions uploads single-file builds as workflow artifacts.

The manual is [GUIDE.md](GUIDE.md). Vendored packages live under `packages/` (or `deps/`) and are pinned by `vire.lock`; `vire pkg lock` and `vire pkg verify` manage that file. There is no package download in this cut.

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
