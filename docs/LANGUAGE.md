# Vire language

Vire is one language with two executions:

- **Host** is the .NET interpreter (`dotnet exec vire.dll program.vire`). It runs `.vire` source on any OS that has the .NET 10 runtime.
- **Native** is a Windows PE produced by `compile-native.vire`. That compiler is itself Vire. The PE does not use .NET.

Untyped programs stay valid. Types and capabilities are optional until you write them down.

## Syntax

A program is `use`, `need`, `can`, then `define` blocks. Run starts at `define main`. `~` comments run to the end of the line.

```vire
can clock
define main
  let n: number be 1
  say n
end
```

`let NAME [: TYPE] be EXPR` binds a name. `define NAME [with P [: TYPE], ...] [as TYPE]` names a function. `as TYPE` is the return type.

Values: whole and decimal numbers, `"text"` with `\"` `\\` `\n` `\t`, `true`, `false`, `none`, lists `[1, 2]`, maps `{"k": 1}`.

Arithmetic `+ - * / %`. `/` is ordinary division. Logic `and or not`. Compare `== != < > <= >=`. `at` indexes lists, maps, and text.

## Gradual types

Allowed type names: `number`, `text`, `bool`, `list`, `map`, `none`, `any`.

No annotation means `any`. The checker only errors when both sides have a known type and they disagree. Untyped code still compiles.

```vire
define add with a: number, b: number as number
  return a + b
end
```

`let n: number be "x"` is a compile error: `n is number, got text`.

The same message is a compile error on the host interpreter and on `compile-native.vire`.

## Capabilities

A program that uses a gated builtin must declare the capability at the top.

| Declaration | Builtins |
| --- | --- |
| `can clock` | `now`, `ticks` |
| `can net.listen` | `listen` |
| `can net.connect.loopback` | `connect`, `send`, `recv`, `close` |
| `can fs.read data` or `can fs.read site` | `read`, `exists`, `files`, `folders`, `sources` |
| `can fs.write data` or `can fs.write site` | `write`, `erase`, `copy`, `append` |

Using a gated name without a matching `can` is a compile error, for example `read needs capability fs.read`.

`compile-native.vire` prints the declared capabilities:

```text
capabilities: clock, fs.read data
```

or `capabilities: none` when the guest declared none.

Imported `use` / `need` files share the entry file's declarations.

## Standard library

This list is the host builtin table in `Vire.cs` (`Machine.BuiltinNames`). Native `compile-native.vire` implements a subset (see `builtinArity`).

- `abs` — absolute value
- `append` — append text to a file (`fs.write`)
- `args` — program arguments
- `ask` — read a line from the terminal
- `begins` — text prefix
- `build` — host toolchain helper
- `button` — window control
- `bytes` — empty byte list
- `chr` — code point to text
- `clear` — clear the window
- `close` — close a loopback socket (`net.connect.loopback`)
- `connect` — loopback TCP connect (`net.connect.loopback`)
- `copy` — copy a file (`fs.write`)
- `dot` — draw a dot
- `drop` — drop list prefix
- `ends` — text suffix
- `erase` — delete a file (`fs.write`)
- `escape` — HTML escape
- `exists` — file exists (`fs.read`)
- `extend` — append bytes onto a list
- `fetch` — HTTP GET (host)
- `field` — window field
- `files` — list files (`fs.read`)
- `fill` — fill a rectangle
- `find` — index of a piece
- `folders` — list folders (`fs.read`)
- `foreign` — foreign call (host)
- `halt` — exit with a code
- `has` — map has a key
- `hash` — hash text
- `hex` — bytes to hex
- `idiv` — unsigned-style integer divide used by the native compiler
- `ink` — drawing color
- `join` — join text
- `json` — value to JSON
- `keys` — map keys
- `kind` — value kind name
- `length` — length of text, list, or map
- `line` — window line
- `listen` — loopback HTTP listen (`net.listen`)
- `lower` — lowercase
- `mark` — window mark
- `marks` — window marks
- `max` — larger number
- `min` — smaller number
- `now` — local timestamp text (`clock`)
- `number` — parse a number
- `open` — open a window
- `parse` — JSON parse
- `pick` — pick a list item
- `place` — place a window control
- `post` — HTTP POST (host)
- `push` — push onto a list
- `read` — read a data/ or site/ file (`fs.read`)
- `recv` — receive from a socket (`net.connect.loopback`)
- `replace` — replace text
- `result` — thread result
- `round` — round a number
- `run` — run another `.vire` program
- `seal` — seal bytes
- `send` — send on a socket (`net.connect.loopback`)
- `serve` — removed; use `listen`
- `sheet` — drawing sheet
- `shl8` — shift a number by 8 bits
- `show` — show the window
- `slice` — slice text or a list
- `sort` — sort a list of numbers
- `sources` — list `.vire` files (`fs.read`)
- `span` — number range
- `split` — split text
- `start` — start a thread
- `stroke` — draw a line
- `term` — terminal kind
- `screen` — window screen
- `text` — value as text
- `ticks` — millisecond ticks (`clock`)
- `upper` — uppercase
- `value` — window field value
- `wait` — wait for a thread
- `watch` — watch a name
- `write` — write a data/ or site/ file (`fs.write`)
