# Vire

Vire is a small programming language with its own syntax. Programs are `.vire` files. `vire.exe` runs them. A program can compute, store data, read and write files in its own folder, load local packages, and open a window.

The full guide for people and for coding agents is [GUIDE.md](GUIDE.md).

## Run on Windows, Linux, or macOS

The desktop window runner is `vire.exe` on Windows. Everywhere else, Vire runs in the terminal. Start a program with `term` if you are using `vire.exe` and do not want a window. The other runners are already in terminal mode.

Self-contained runners are in `dist` after a publish:

| Machine | File |
| --- | --- |
| Linux, 64-bit Intel | `dist/linux-x64/vire` |
| Linux, 64-bit ARM | `dist/linux-arm64/vire` |
| macOS, Intel | `dist/osx-x64/vire` |
| macOS, Apple silicon | `dist/osx-arm64/vire` |
| Windows, 64-bit | `dist/win-x64/vire.exe` |

```text
./dist/linux-x64/vire tests.vire
```

Build them again with the .NET 8 SDK:

```text
dotnet publish -c Release -r linux-x64 --self-contained true -p:PublishSingleFile=true -o dist/linux-x64
```

Use `linux-arm64`, `osx-x64`, `osx-arm64`, or `win-x64` the same way. These runners do not open a desktop window. `tests.vire` prints `pass` on them, including the sheet check.

```text
vire.exe work.vire
```

That opens a window titled "Vire tasks". Save writes `data/note.txt`. `board.vire` draws on a sheet. `tests.vire` loads `checks/core.vire` and prints `pass` when the checks hold.

Build the runner on Windows from the source in this repo:

```text
C:\Windows\Microsoft.NET\Framework64\v4.0.30319\csc.exe /nologo /r:System.Windows.Forms.dll /r:System.Drawing.dll /out:vire.exe Vire.cs
```

## License

MIT. See [LICENSE](LICENSE).
