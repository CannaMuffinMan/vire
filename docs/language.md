# Language reference

Vire source files use the `.vire` extension. A run starts at `define main` in the file passed to the runner. Comments start with `~` and last until the end of the line. A `~ budget …` comment does **not** change the step cap; only `VIRE_BUDGET` does.

This page lists forms the **interpreter** (`Vire.cs`) and the **Vire compiler** (`compiler.vire` + `Compiled.cs`) both accept on this branch, except where a difference is called out.

## Program layout

Top level, in any order among themselves:

- `use "relative.vire"` — load another `.vire` file in the program folder (not under `data/` or `site/`). At most 32 files. A cycle is an error (`use went in a circle at …` in the interpreter; the compiler prints `use went in a circle`).
- `need "package"` — load `deps/<package>/lib.vire`. The package name is letters, digits, and `_` only.
- `define name` or `define name with a, b` … `end` — a definition. Duplicate names are errors (`name is already defined`).

`use` and `need` must appear at the top of a file, not inside a definition. The file passed to the runner must define `main`. Packages should not define `main` if the importing file also does.

## Tokens

- Names: letter or `_`, then letters, digits, `_`. Keywords cannot be names.
- Keywords: `define` `with` `end` `let` `be` `say` `while` `if` `else` `return` `and` `or` `not` `true` `false` `for` `in` `at` `put` `into` `try` `miss` `stop` `skip` `none` `now` `use` `need`
- Numbers: digits, optional `.` plus digits. Whole numbers that fit in signed 32-bit `int` stay whole; larger digit strings become IEEE decimals. A number that cannot be parsed is `that number is too large`.
- Text: `"…"` on one line. Escapes: `\"` `\\` `\n` `\r` `\t`. Unknown escapes and missing quotes are errors.
- Operators: `+ - * / % == != < > <= >=` and punctuation `() [] {} , :`
- Unexpected characters are errors (`unexpected character '…'`).

## Definitions and calls

```vire
define area with w, h
  return w * h
end
```

Call with `name with arg, arg`. A definition with no parameters may be used as a bare name in an expression (it runs immediately). `now`, `show`, `term`, `screen`, `marks`, `clear`, and `args` are the same: a bare name with no `with` is a zero-argument builtin.

Without `return`, a definition yields `none` (C# `null`), not `0`. Calls may nest 64 deep (`definitions called too deeply`). Argument count must match (`name takes N values, got M` in the interpreter).

A call argument is parsed as a product (`* / %` and unary), **not** a sum. `say escape with "Vire" + "</p>"` is `(escape with "Vire") + "</p>"`. Parenthesize: `area with (1 + 2), 4`.

## Statements

| Form | Behavior |
| --- | --- |
| `let name be expr` | Bind or rebind `name` in the current definition. |
| `put expr into name at index` | Write a list slot or map key. Text cannot be changed in place. |
| `say expr` | Print `Show(expr)` and a newline. Cyclic lists/maps print `[...]` / `{...}` instead of hanging. Output longer than 1,000,000 characters is an error. |
| `return expr` | Leave the definition with that value. |
| `if test` … `else if test` … `else` … `end` | `else if` chains. The test uses truthiness (below). |
| `while test` … `end` | Loop. Each pass counts toward the while-pass cap. |
| `for name in expr` … `end` | Walk a list (items), a map (keys), or text (one-character strings). |
| `skip` / `stop` | Next pass / leave the nearest `while` or `for`. Outside a loop: `skip is only valid inside while or for` (same for `stop`). |
| `try` … `miss name` … `end` | `miss` runs on a `VireError` in `try`. `name` receives the message text. `HaltSignal` is not caught. `miss` without a name is allowed. |
| `name with …` | Statement-level call; the result is discarded. |

A block nested more than 256 `if`/`try`/definition bodies is `block is nested too deeply`. A missing `end` is `block is missing end`. Anything else at statement position is `line does not start a statement`.

## Expressions

Precedence, tightest first: unary `not` / `-`; `* / %`; `+ -`; `== != < > <= >=`; `and`; `or`. `at` binds to a primary (`xs at 0 at 1`).

- Literals: number, `"text"`, `true`, `false`, `none`, `now` (local `yyyy-MM-dd HH:mm:ss`)
- List: `[a, b]` trailing comma allowed. Cap 100,000 items.
- Map: `{key: value}` keys must be text or numbers (stored as text). Cap 100,000 entries. Trailing comma allowed.
- Parsed expressions nest at most 256 levels (`expression is too deep`). Compiled evaluation uses the same 256 cap **per evaluation**.

### Arithmetic and logic

`+ - *` on two whole numbers that overflow 32-bit `int` become decimals instead of wrapping. `/` is float division (`5 / 2` is `2.5`). `%` of two whole numbers uses integer remainder; remainder of `n % -1` is `0`, including `int.MinValue`. Division or remainder by zero is `division by zero`.

`+` also concatenates text (either side text → both shown as text) and concatenates two lists.

`and` / `or` short-circuit and use truthiness. `not` negates truthiness.

Comparisons `< > <= >=` need two numbers. `==` / `!=` compare numbers by numeric value, `none` with `none`, otherwise `.Equals`.

Unary minus of `int.MinValue` is the decimal `2147483648`.

### Truthiness

False: `none`, `false`, `0`, `0.0`, `""`, `[]`, `{}`. Everything else is true, including `"0"` and `[0]`.

### Indexing (`at` / `put`)

List and text indexes are whole numbers. A negative index counts from the end. Out of range: `index is outside the value`. Map missing key: `map has no key …`.

## Errors and process exit

Vire errors print `vire: line N col M: message` (when line/column are known) to stderr and exit **1**.

`halt with n` (whole number) exits with that code and does not print a Vire error.

A missing or invalid seal key on compile/run of `.vc` exits **2** with `vire: a seal key is required (set VIRE_SEAL_KEY or --seal-key-file)`.

Unexpected .NET exceptions print `vire: internal error (TypeName)` and exit **3**, unless `VIRE_DEBUG=1` prints a stack trace.

`try`/`miss` only sees Vire errors, not halt and not exit 3.

## Limits (runner)

| Cap | Default | Notes |
| --- | --- | --- |
| Steps | 1,000,000 | `VIRE_BUDGET` from 1 to 5,000,000 raises this (and while passes). |
| While passes | same as steps | Message `while ran too long`. |
| Call depth | 64 | |
| Nested `run` | 8 | `run went too deep` |
| Text / `say` / file bytes | 1,000,000 characters | |
| List/map items | 100,000 | |
| Source files (`use`/`need`) | 32 | |
| Expression / JSON / block nest | 256 | |
| Source file size | 1,000,000 bytes | `that file is too large to run` |

`listen` requests get a **fresh** copy of that budget and a 5 second wall-clock deadline (`request ran too long`).

## Interpreter vs compiled

`compiler.vire` reads source from `data/` or `site/` (the `read` builtin), writes a `VC2` `.vc` via `seal` + `write`, and prints `compiled`. Running the `.vc` is `vire run file.vc`.

Known mismatches that are **not** claimed to match are listed in the pull request “Left” section (argument-count checks on several compiled builtins; some compiled user-call errors still say `argument count` at line 1). Trivial mismatches fixed on this branch: compiled `seal` requires text; compiled `halt` requires exactly one whole number, same messages as the interpreter.
