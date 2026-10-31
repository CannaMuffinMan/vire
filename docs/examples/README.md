# Checked examples

Each program here is a `.vire` file with sibling expectation files. CI job `docs-examples` (and `tools/check-docs-examples.sh`) runs every example twice:

1. Interpreter: `vire <file> [args]`
2. Compiled: `compiler.vire` writes a `.vc`, then `vire run <file.vc> [args]`

Stdout, stderr, and exit code must match the siblings in both modes.

| Sibling | Meaning |
| --- | --- |
| `name.stdout` | Exact stdout after normalizing `\r\n` to `\n` |
| `name.stderr` | Exact stderr (optional; default empty) |
| `name.exit` | Exit code (optional; default `0`) |
| `name.args` | Extra CLI arguments, one per line (optional) |

Files under `helpers/` and `deps/` are imports, not examples.

Do not put `now`, `pick`, `seal`, `ask`, `listen`, `fetch`, or `post` in a checked example: those are time, random, nonce, interactive, or network dependent.
