# CLI reference

The published binary is `vire` (Linux/macOS) or `vire.exe` (Windows). From this repo:

```text
dotnet build -c Release
dotnet exec bin/Release/net10.0/vire.dll …
```

There is no separate `vire compile` or `vire listen` verb. Compile by running `compiler.vire`. Listen by running a program that calls the `listen` builtin.

`--seal-key-file <path>` may appear anywhere among the arguments. The path must be **outside** the program folder. The file is 32 raw bytes or base64 of 32 bytes. All-zero keys are refused. Environment `VIRE_SEAL_KEY` is base64 of exactly 32 bytes.

## Commands

### Source program (default)

```text
vire program.vire [args…]
```

Loads `program.vire` from disk (must end in `.vire`), uses that file’s directory as the sandbox root, binds extra CLI words to the `args` builtin, and runs `main`. Missing `main`: `a vire program needs define main`.

Exit 0 on success, or see [language.md](language.md) for 1/2/3/`halt`.

### Run a compiled program

```text
vire run file.vc [args…]
```

Opens a `VC2` envelope with the current seal key and executes it. The sandbox root is the directory that contains `file.vc`. Old XOR `VIRE1` files: `this .vc uses the old seal; recompile it`. Damaged/wrong-key files: `sealed program is damaged`.

### Compile source to `.vc`

Not a CLI verb. The compiler is a Vire program:

```text
export VIRE_SEAL_KEY='…'   # or --seal-key-file
vire compiler.vire data/app.vire data/app.vc
```

`compiler.vire` uses `read`/`write`, so both paths must sit under `data/` or `site/` relative to the **compiler’s** program folder (the repo root when you invoke `compiler.vire` from there). On success it prints `compiled`. On parse failure it prints a diagnostic and `compile failed`, then `halt with 1`.

Native Windows PE emission (`compile-native.vire`) is a separate, narrower compiler. It is not the dual-mode path CI uses.

### Key generation

```text
vire keygen --out /path/outside/program
```

Writes 32 random bytes, owner-only permissions on Unix (`0600`), prints `seal key fingerprint` plus 8 hex characters of SHA-256 of the key. Missing path: usage on stderr, exit 2. The key material is never printed.

### Payload tools (self-host / CI)

```text
vire payload-sha256 file.vc
vire payload-write file.vc dest.bin
```

Decrypt the envelope and print SHA-256 of the UTF-8 payload, or write the raw payload bytes. Used by `tools/selfhost-check.sh` so stage 1 = 2 = 3 compares **unsealed** bytes (GCM nonces make sealed files differ).

## Usage errors

No arguments prints:

```text
usage: vire program.vire [args...]
       vire run file.vc [args...]
       vire keygen --out <path>
```

and exits 2.

## Environment

| Variable | Effect |
| --- | --- |
| `VIRE_SEAL_KEY` | Base64 32-byte seal key |
| `VIRE_BUDGET` | Integer 1…5,000,000 (invalid: Vire error) |
| `VIRE_DEBUG` | `1` prints .NET stack traces on exit 3 |
| `VIRE_BIND` | `public` makes `listen` bind `0.0.0.0` (requires `FCG_API_TOKEN` ≥ 16 chars) |
| `FCG_API_TOKEN` | Token for non-loopback `listen`; compared via SHA-256 of header `X-FCG-Token` |
| `PORT` | Overrides the port argument to `listen` if set |

## Docker

```text
docker build -t vire .
docker run --rm vire tests.vire
```

The image entrypoint is the runner. Mount a folder to run other programs (`-v "$PWD":/work`).
