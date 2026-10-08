# Vire

Vire is a small programming language. Programs are `.vire` files. Anyone with Docker, or the .NET 8 SDK, can run them. A Windows desktop build can also open a window.

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

## Run with .NET 8

```text
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

`vire.exe` in a Windows build opens a real window for `work.vire` and `board.vire`. Build it with:

```text
C:\Windows\Microsoft.NET\Framework64\v4.0.30319\csc.exe /nologo /define:WINDOWS /r:System.Windows.Forms.dll /r:System.Drawing.dll /r:System.Net.Http.dll /out:vire.exe Vire.cs
```

## License

MIT. See [LICENSE](LICENSE).
