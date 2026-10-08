# Vire

Vire is a small programming language with its own syntax. Programs are `.vire` files. `vire.exe` runs them. A program can compute, store data, read and write files in its own folder, load local packages, and open a window.

The full guide for people and for coding agents is [GUIDE.md](GUIDE.md).

## Run

```text
vire.exe work.vire
```

That opens a window titled "Vire tasks". Save writes `data/note.txt`. `board.vire` adds a clickable mark. `tests.vire` prints `pass` when the language checks hold.

Build the runner on Windows from the source in this repo:

```text
C:\Windows\Microsoft.NET\Framework64\v4.0.30319\csc.exe /nologo /r:System.Windows.Forms.dll /r:System.Drawing.dll /out:vire.exe Vire.cs
```

## License

MIT. See [LICENSE](LICENSE).
