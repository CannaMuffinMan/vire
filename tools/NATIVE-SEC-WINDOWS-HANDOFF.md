# Native Windows security CLI handoff

Local-only recipe for junction / hardlink / path / frame / hello proof that cloud Linux Unicorn cannot clear. Do not run this against production, OBS, or a developer PC from this agent. Grok Build CLI or a throwaway Windows x64 VM is the intended runner.

## Pin

- Task branch: `cursor/native-sec-windows-handoff-0b9c`
- Parent integration (unchanged): PR 38 `e0d70a075147113a1d3ba569fad879f8982224ea`
- Base: `native-compiler` `0f758e7`
- Caps: 32MB arena, list 100000, `VIRE_BUDGET=5000000`

## Prereqs

- Windows 10/11 x64 (not ARM, not WoW64-as-proof)
- .NET SDK 10 matching `global.json` (`10.0.403` pin)
- This git ref checked out; `dotnet build vire.csproj -c Release`
- Create symlink privilege **or** Developer Mode so `mklink /J` and `mklink /H` work
- PowerShell 7 (`pwsh`) or Windows PowerShell 5.1
- Isolated fixture is created under `%TEMP%\vire-native-sec-*`, never under Program Files, the user profile Documents tree, or OBS

## Command

From the repo root, wall clock **180 seconds**:

```
pwsh -File tools/native-sec-windows.ps1
```

Optional keep-on-fail:

```
pwsh -File tools/native-sec-windows.ps1 -KeepOnFail
```

Do **not** pass `-RunSelfHost` unless you accept a separate 600s gen1 hello attempt. Default is off. Native gen1→gen2 hash is **not** in this recipe (blocked: native `read` is `data/`|`site/` only, while `use` files are `src/*.vire`).

## Expected

| Step | Exit | Stdout contains | Fixture preserved |
|---|---|---|---|
| hello.exe in fixture cwd | 0 | `hello from vire` | n/a |
| parent junction `data` → `outside` | nonzero | `files stay inside the program folder` | `outside/secret.txt` still `outside-secret` |
| hardlink `data/alias.txt` → `data/note.txt` | nonzero | `files stay inside the program folder` | both files still `SECRET` |
| `data/../outside.txt` write | nonzero | `files stay inside the program folder` | `outside.txt` still `outside-keep` |
| recursion 65 | nonzero | `definitions called too deeply` | no `survived` |

Exit codes from the script:

- `0` all required steps passed
- `2` BLOCKED (no symlink privilege / `mklink` failed) — not a pass
- `1` failed closed incorrectly or leaked

## Artifacts

Written under the fixture `artifacts\` and copied to `data/native-sec-windows/artifacts\` in the repo (gitignored runtime dir):

- `ref.txt` — `git rev-parse HEAD`
- `results.txt` — per-step lines
- `*.out.txt` — exe stdout/stderr

## Cleanup

On success the `%TEMP%` fixture is deleted. `-KeepOnFail` keeps it. The script does not change PATH, registry, firewall, credentials, or system symlink policy.

## Stop criteria

Stop after this script. Do not chain compiler.vire rebuilds. Do not treat CI `native-windows` hello on an older head as this ref.
