# Vire

Vire is a small programming language. Programs are `.vire` files.

The usual way to run them is the C# interpreter (.NET 10 SDK, Docker, or a published single-file `vire`). That published file is still CoreCLR. It is not the native compiler.

On Windows, the native compiler is a PE named `gen1.exe`. The first copy of that PE is emitted by the interpreter (`dotnet exec … compile-native.vire`). After that, `gen1.exe` compiles guests and rebuilds the compiler. See [NATIVE-COMPILER.md](NATIVE-COMPILER.md) and [docs/native-clean-machine.md](docs/native-clean-machine.md). Linux Unicorn is not the Windows proof.

A Windows desktop build can also open a window. Binaries are not stored in git. GitHub Actions uploads single-file interpreter builds as workflow artifacts. The clean-machine zip is an artifact too, not a git blob.

The manual is [GUIDE.md](GUIDE.md).

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
