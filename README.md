# Vire

Vire is a small programming language. Programs are `.vire` files. Anyone with Docker, or the .NET 10 SDK, can run them. A Windows desktop build can also open a window. Binaries are not stored in git. GitHub Actions uploads single-file builds as workflow artifacts.

The manual is [GUIDE.md](GUIDE.md).

## Quickstart: Hello World

From the repository root, with the .NET 10 SDK:

```text
dotnet build vire.csproj -c Release
dotnet exec bin/Release/net10.0/vire.dll examples/hello/hello.vire
```

That interpreter run prints `Hello, World!` and exits 0.

To compile the same program and run the sealed `.vc`:

1. Set a seal key. Either export `VIRE_SEAL_KEY` as the base64 of exactly 32 random bytes, or run `vire keygen --out` to a file **outside** the program folder and use `--seal-key-file`. Do not print, log, or commit the key.
2. Copy the source into `data/` (the compiler writes `.vc` files there; `data/` is gitignored).
3. Compile, then run the compiled file:

```text
mkdir -p data
cp examples/hello/hello.vire data/hello.vire
dotnet exec bin/Release/net10.0/vire.dll compiler.vire data/hello.vire data/hello.vc
dotnet exec bin/Release/net10.0/vire.dll run data/hello.vc
```

The compiled run also prints `Hello, World!` and exits 0. The compile step prints `compiled` on success. Generate a throwaway key in the shell without echoing it, for example:

```text
export VIRE_SEAL_KEY="$(python3 -c 'import os,base64; print(base64.b64encode(os.urandom(32)).decode())')"
```

Or:

```text
dotnet exec bin/Release/net10.0/vire.dll keygen --out "$HOME/vire.seal.key"
dotnet exec bin/Release/net10.0/vire.dll --seal-key-file "$HOME/vire.seal.key" compiler.vire data/hello.vire data/hello.vc
dotnet exec bin/Release/net10.0/vire.dll --seal-key-file "$HOME/vire.seal.key" run data/hello.vc
```

`keygen` prints only `seal key fingerprint` plus eight hex characters, never the key bytes.

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
