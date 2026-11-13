# Vire language reference

This page describes what the compilers in this repository accept **today**.
Every runnable snippet lives under [`site/vire/examples/`](../site/vire/examples/)
and is executed by [`.github/workflows/site-vire.yml`](../.github/workflows/site-vire.yml).

There are two compilers:

| Compiler | Source | Output |
| --- | --- | --- |
| Host interpreter | C# runner + `compiler.vire` (sealed `.vc` path) | Runs `.vire` directly; can emit `.vc` |
| Native compiler | `compile-native.vire` | Windows x64 PE hex, no outside C compiler |

If a construct is host-only, it is marked. Native guests must stay inside the
native grammar and builtin list or `compile-native.vire` prints `compile failed`.

## 1. A program

A program is one or more `define` blocks. Execution starts at `define main`.
`~` starts a comment to the end of the line. Files use the `.vire` suffix.

```vire
~ Hero sample: a complete Vire program.
define greet with who
  return "hello, " + who
end

define main
  say greet with "vire"
end
```

Source: [`hello.vire`](../site/vire/examples/hello.vire). Output: `hello, vire`.

If `main` is missing, both compilers stop (`a vire program needs define main`).
That is why [`mod-lib.vire`](../site/vire/examples/mod-lib.vire) is a library, not a program.

## 2. Syntax

### 2.1 Names and literals

Create a name with `let` / `be`. Names are letters, digits, and `_`, and must
start with a letter or `_`.

Values:

- Integers (both compilers). Digits only; a leading `.` is rejected by the native tokenizer (`that number is not ready`).
- Decimals such as `2.5` — **host interpreter only**.
- Text in double quotes. Escapes: `\"` `\\` `\n` `\t` (native also accepts `\r`).
- `true`, `false`, `none`.
- Lists `[1, 2, 3]` and maps `{"name": "ada", "year": 1815}`.

### 2.2 Operators

Arithmetic: `+ - * / %`. `/` is ordinary division on the host (`5 / 2` is `2.5`).
Native integer division of two wholes uses `idiv` when you need a whole result.
`+` concatenates text and concatenates lists.

Comparisons: `== != < > <= >=`. Logic: `and`, `or`, `not`. Parentheses group.

A call argument stops before `+`. Write `area with (1 + 2), 4` when the argument
itself uses `+`. Unary minus in a call argument is not a statement; bind it first
(see [`defs.vire`](../site/vire/examples/defs.vire)).

### 2.3 Control

`if` / `else if` / `else` / `end`. `while` / `end`. `for name in list` / `end`.
`skip` and `stop` are valid only inside `while` or `for`.

```vire
~ Tour: else if, for, skip, stop.
define main
  let n be 2
  if n == 1
    say "one"
  else if n == 2
    say "two"
  else
    say "other"
  end
  let total be 0
  for item in [1, 2, 3, 4]
    if item == 2
      skip
    end
    if item == 4
      stop
    end
    let total be total + item
  end
  say total
end
```

Source: [`control.vire`](../site/vire/examples/control.vire). Output:

```
two
4
```

### 2.4 Definitions

```vire
define area with w, h
  return w * h
end
```

Call with `name with arg, arg`. A definition with no parameters can be used as a
bare name (`say helper`). Without `return`, a native/host function yields `none`
on the native path after the body (the host interpreter historically yielded `0`
in some older notes; current GUIDE says `none` for a bare end).

Host call depth cap: 64. Host expression depth cap: 256.

### 2.5 Failures

```vire
try
  say number with "nope"
miss problem
  say "caught"
end
```

Source: [`try-miss.vire`](../site/vire/examples/try-miss.vire). `miss` runs on a
Vire error inside `try`. The name after `miss` receives the message.

## 3. Types (gradual, optional, incomplete)

There are **no type annotations** in the grammar. A line such as
`let n be 3 : number` is not accepted.

Runtime values have a kind. On the **host**, `kind with value` returns
`number`, `text`, `list`, `map`, `bool`, or `none`. That builtin is **not** in
`compile-native.vire`’s `builtinArity` table.

Some programs (for example `schema-prove.vire`) check map-shaped schemas at
runtime. That is a library pattern, not a typechecker.

## 4. Capabilities (`can` lines)

Vire does **not** parse `can` declarations. A source line `can listen` is a
syntax error.

What is enforced instead:

- Path sandbox: `read` / `write` / `append` / `copy` / `erase` stay inside the
  program folder, under `data/` or `site/` on the host. Rooted paths, `..`,
  device names, and a list of executable extensions are refused.
- `use` and `run` stay out of `data/` and `site/`.
- Native PE imports a fixed kernel32 / ws2_32 allowlist. No `LoadLibraryA`, no
  `GetProcAddress`, no `CreateProcess`.
- `listen` binds `127.0.0.1` by default.
- Native `connect` refuses non-loopback and link-local targets (see
  `tests/native/tcp-client.vire`).

A future `can` line would make those policies explicit in source. It is
**in progress**, not shipping.

## 5. Modules

### 5.1 `use`

`use "mod-lib.vire"` loads another `.vire` file in the same program folder.
Cycles are refused. At most 32 files. The path must end in `.vire` and must not
start with the `data` or `site` segment.

```vire
use "mod-lib.vire"

define main
  say helper
end
```

Sources: [`mod-main.vire`](../site/vire/examples/mod-main.vire),
[`mod-lib.vire`](../site/vire/examples/mod-lib.vire). Output: `9`.

### 5.2 `need`

`need "textkit"` loads `deps/<name>/lib.vire` when a `deps.lock` pin is present.
Package samples live under `samples/` and `deps/`. Homepage CI does not run a
`need` program; lock-file rules are covered by existing tests, not by this page.

## 6. Builtins

### 6.1 Native compiler (`compile-native.vire` `builtinArity`)

| Name | Arity | Notes |
| --- | --- | --- |
| `args` | 0 | Also a bare name |
| `ticks` | 0 | Also a bare name |
| `length` | 1 | Text, list, or map |
| `text` | 1 | Convert |
| `number` | 1 | Convert; fails on junk |
| `halt` | 1 | Exit code |
| `read` | 1 | File, sandboxed |
| `lower` | 1 | |
| `keys` | 1 | Map keys |
| `drop` | 1 | Last list item |
| `hash` | 1 | |
| `hex` | 1 | |
| `shl8` | 1 | |
| `chr` | 1 | |
| `json` | 1 | Turns on native JSON runtime |
| `parse` | 1 | Turns on native JSON runtime |
| `listen` | 1 | Turns on Winsock image |
| `close` | 1 | Socket |
| `push` | 2 | |
| `find` | 2 | |
| `has` | 2 | |
| `write` | 2 | |
| `begins` | 2 | |
| `ends` | 2 | |
| `split` | 2 | |
| `idiv` | 2 | Whole division |
| `join` | 2 | List of **text** |
| `extend` | 2 | |
| `connect` | 2 | Host, port |
| `send` | 2 | |
| `recv` | 2 | |
| `slice` | 3 | |
| `replace` | 3 | |

`bytes` exists as a bare native name (empty buffer), not as `bytes with x`.

[`json.vire`](../site/vire/examples/json.vire) prints `{"ok":true,"n":3}` then `3`.
[`files.vire`](../site/vire/examples/files.vire) writes `data/note.txt` and prints `hello`.
[`text.vire`](../site/vire/examples/text.vire) and [`lists.vire`](../site/vire/examples/lists.vire)
cover the rest of the tour.

`listen` / `connect` are real but start network I/O. They are proven in
`native-net.yml` and `native-windows`, not in the homepage sample set.

### 6.2 Host-only (interpreter / GUIDE)

The host runner implements a larger set, including `sort`, `span`, `abs`,
`min`, `max`, `upper`, `round`, `pick`, `now`, `ask`, `fetch`, `post`, `exists`,
`files`, `folders`, `append`, `copy`, `erase`, `kind`, window words
(`open`, `show`, `line`, …), and `run`. Using them in a native guest fails
lookup (`there is no definition named …`).

## 7. Limits

Do not raise these as a “fix”.

| Cap | Host interpreter | Native PE |
| --- | --- | --- |
| Steps | 1,000,000 default; `VIRE_BUDGET` 1–**5,000,000** | Separate native step budget; compiler mode uses the 5M ceiling |
| `while` passes | 100,000 (raised with `VIRE_BUDGET`) | Native loops are instruction-limited, not the host while cap |
| List items | **100,000** | **100,000** (`rt` emit) |
| Arena / heap | Process heap | **32 MB** mapping (`33554432`) |
| Text | 1,000,000 characters | Native text concat checks 1,000,000 |
| Call depth | 64 | Native frame stack |
| `use` files | 32 | 32 |
| Nested `run` | 8 | n/a on PE guests |

A program cannot grant itself more steps. A `~ budget` comment does nothing.

## 8. Networking (honest)

- **HTTP listen:** `listen with port` on native PE, loopback. Needs a
  `define route with method, path, body` for useful responses (`guest-health.vire`).
- **TCP:** `connect` / `send` / `recv` / `close`, loopback in CI.
- **Postgres:** `pg_open` and friends in `src/rt-pg.vire`. CI uses trust/cleartext
  on loopback. **TLS: in progress. SCRAM: residual under the 5M cap.**
- **TLS server:** not present.
- **Linux ELF:** not emitted.

## 9. What this reference is not

It is not a benchmark. It is not a claim that Vire is the fastest or safest
language. It is not a release. Published single-file runners come from
`check.yml` `publish` artifacts when that job is run; they are not in git.
