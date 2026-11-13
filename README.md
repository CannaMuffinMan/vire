# Vire

Vire is a programming language. The compiler is written in Vire and, on
Windows, compiles itself to a native PE. Guests are sandboxed. Types are
dynamic today. Networking (loopback HTTP, TCP, Postgres) is landing.

This README is the front door. The language reference is
[docs/LANGUAGE.md](docs/LANGUAGE.md). The developer homepage (static, no CDN)
is [site/vire/index.html](site/vire/index.html). The longer narrative manual is
[GUIDE.md](GUIDE.md).

[![check](https://github.com/CannaMuffinMan/vire/actions/workflows/check.yml/badge.svg)](https://github.com/CannaMuffinMan/vire/actions/workflows/check.yml)
[![site-vire](https://github.com/CannaMuffinMan/vire/actions/workflows/site-vire.yml/badge.svg)](https://github.com/CannaMuffinMan/vire/actions/workflows/site-vire.yml)
[![native-net](https://github.com/CannaMuffinMan/vire/actions/workflows/native-net.yml/badge.svg)](https://github.com/CannaMuffinMan/vire/actions/workflows/native-net.yml)
[![crypto](https://github.com/CannaMuffinMan/vire/actions/workflows/crypto.yml/badge.svg)](https://github.com/CannaMuffinMan/vire/actions/workflows/crypto.yml)
[![fuzz](https://github.com/CannaMuffinMan/vire/actions/workflows/fuzz.yml/badge.svg)](https://github.com/CannaMuffinMan/vire/actions/workflows/fuzz.yml)

## Hello world

```vire
define greet with who
  return "hello, " + who
end

define main
  say greet with "vire"
end
```

That file is [`site/vire/examples/hello.vire`](site/vire/examples/hello.vire).
It prints `hello, vire`.

## Quick start

You need the [.NET 10 SDK](https://dot.net/). Binaries are not stored in git.

```text
dotnet build vire.csproj -c Release
dotnet exec bin/Release/net10.0/vire.dll site/vire/examples/hello.vire
```

Run the suite the host still uses:

```text
dotnet test tests/Vire.Tests/Vire.Tests.csproj -c Release
dotnet exec bin/Release/net10.0/vire.dll tests.vire
```

Docker (interpreter image, no Windows PE):

```text
docker build -t vire .
docker run --rm vire tests.vire
```

### Native Windows PE

On Windows, after the same `dotnet build`:

```text
dotnet exec bin/Release/net10.0/vire.dll --compiler compile-native.vire data/guest-hello.vire data/guest-hello.hex
```

CI converts that hex to an `.exe` and expects `hello from stage` from
`guest-hello.vire`. The fixed-point proof (gen1 hex = gen2 hex) is
`tools/native-selfhost-handoff.ps1` on `windows-latest`
([check.yml](.github/workflows/check.yml) job `native-selfhost-windows`).

Linux ELF is **in progress** and is not a shipped target.

## What is true today

- Self-host: native gen1 = gen2 is proven in CI on Windows.
- Emit path: Windows PE from Vire, no cl/gcc/rustc.
- Bootstrap: the C# host in this repo still emits the first image.
- Caps: host list 100,000; native arena 32 MB; step budget up to 5,000,000.
- No `can` capability syntax yet. Sandbox + import allowlist + caps.
- No type annotations yet.
- Postgres TLS / SCRAM: in progress (loopback trust/cleartext is what CI proves).

## License

MIT. See [LICENSE](LICENSE).
