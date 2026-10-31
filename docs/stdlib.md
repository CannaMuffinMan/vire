# Standard library reference

Builtins are names reserved in the interpreter’s builtin set. User `define` cannot reuse them as functions that hide the builtin (the builtin is tried first). Arity is exact in the interpreter (`name takes N values, got M`). Failure messages below are the interpreter’s wording unless noted.

Return values that are `0` in the table are the whole number zero, not `none`.

## Values and conversion

| Call | Arity | Result / failure |
| --- | --- | --- |
| `kind with v` | 1 | `"number"` `"text"` `"list"` `"map"` `"bool"` `"none"` |
| `text with v` | 1 | `Show(v)` (lists like `[1, 2]`, maps like `{a: 1}`, `none` → `none`) |
| `number with v` | 1 | Number unchanged; text parsed as int or invariant float; else `that text is not a number` / `number needs text or a number` |
| `hash with v` | 1 | Lowercase hex SHA-256 of the text (non-text is shown first) |
| `args` | 0 | List of extra CLI words (text) |

## Numbers

| Call | Arity | Result / failure |
| --- | --- | --- |
| `abs with n` | 1 | Absolute value. `abs` of `int.MinValue` is decimal `2147483648`. |
| `min with a, b` / `max with a, b` | 2 | Numeric compare; keeps original types. |
| `round with n` | 1 | `MidpointRounding.AwayFromZero`. Out of 32-bit range stays decimal. NaN/Inf refused. |
| `pick with n` | 1 | Uniform whole number in `0 .. n-1`. `n` must be a whole number ≥ 1. **Non-deterministic** — not used in checked examples. |
| `span with from, to` | 2 | Inclusive whole-number list. Empty/backwards or > 100,000 items: `span is too large`. |

## Text

| Call | Arity | Result / failure |
| --- | --- | --- |
| `length with v` | 1 | Length of text, list, or map |
| `lower` / `upper` | 1 | Invariant case; need text |
| `find with text, needle` | 2 | Index of first match, or `-1`. Empty needle is `0`. |
| `split with text, sep` | 2 | List of pieces. Empty separator refused. |
| `join with list, sep` | 2 | List must be all text |
| `replace with text, old, new` | 3 | All non-overlapping replacements |
| `begins` / `ends` | 2 | Prefix / suffix |
| `slice with v, start, end` | 3 | Text or list; start/end whole numbers; negative start clamped to 0; `end < start` becomes empty |
| `escape with v` | 1 | `& < > "` → HTML entities (non-text is shown first) |

`at` on text returns a one-character string.

## Lists and maps

| Call | Arity | Result / failure |
| --- | --- | --- |
| `push with list, item` | 2 | Mutates and returns the same list. Cap 100,000. |
| `drop with list` | 1 | Removes and returns the last item. Empty list refused. |
| `sort with list` | 1 | **New** list, numbers only, ascending. |
| `keys with map` | 1 | List of keys (insertion order). |
| `has with map, key` | 2 | `true`/`false`. Key must be text or number. |

## JSON and time

| Call | Arity | Result / failure |
| --- | --- | --- |
| `json with v` | 1 | JSON text. Depth 256. Cycles refused. NaN/Inf refused. Output cap 1,000,000. `none` → `null`. |
| `parse with text` | 1 | Inverse. Extra text, bad escapes, depth, and size are errors. |
| `now` | 0 | Local `yyyy-MM-dd HH:mm:ss`. **Non-deterministic.** |

## Files (sandbox)

Paths are relative, `data/` or `site/` only, through `SafeName` (see [security.md](security.md)).

| Call | Arity | Result / failure |
| --- | --- | --- |
| `read with path` | 1 | Entire file as text; too large / IO → error |
| `write with path, value` | 2 | `Show(value)` written; creates parent dirs; returns the value. `.vc` is packed bytes via the seal helper. |
| `append with path, value` | 2 | Append shown text; returns that text |
| `copy with from, to` | 2 | Copy file; returns `to` |
| `erase with path` | 1 | Delete file; returns `true` |
| `exists with path` | 1 | File or directory exists |
| `files with dir` | 1 | File names (not recursive). Order is OS-dependent. |
| `folders with dir` | 1 | Directory names. Order is OS-dependent. |
| `sources with name` | 1 | `*.vire` names in one **single-segment** folder that is not `data`/`site`. Used by `tests.vire`. |

## Process composition

| Call | Arity | Result / failure |
| --- | --- | --- |
| `run with "file.vire"` | 1 | Nested program, shared budget, stdout captured then replayed; returns last non-empty line. Stays out of `data/`/`site/`. Max 8 deep. |
| `halt with code` | 1 | Whole-number process exit. Not catchable by `try`. |
| `seal with text` | 1 | `VC2` envelope as a Latin-1-ish byte string for `write` of `.vc`. Needs a seal key. **Non-deterministic** (random nonce). Non-text is an error (`seal needs text`). |

## HTTP client

| Call | Arity | Result / failure |
| --- | --- | --- |
| `fetch with url` | 1 | GET body as text |
| `post with url, body` | 2 | POST body as text |

See [security.md](security.md) for URL rules. Failures: `fetch needs an http or https address`, `could not fetch that address`, and the SSRF/path messages from `VireNet`.

## HTTP server (`listen`)

`listen with port` (0 or 1024–65535, not reserved). Requires `define route with method, path, body`. Blocks until Ctrl+C. Prints `listening on 127.0.0.1:port`. Returns `none`.

`serve` is removed: `serve was removed; use listen`.

## Terminal / window (optional)

On this Linux runner there is no WinForms window. `open`, `line`, `field`, `button`, `place`, `mark`, `sheet`, `ink`, `stroke`, `fill`, `dot`, `watch`, `value`, `show`, `term`, `screen`, `marks`, `clear` still exist:

- `term` switches to the terminal UI (`desk`).
- Without a Windows build, `show` uses the terminal UI (`TermShow`): prints the title and lines, reads field values, then a button number or `0` to close.
- `open` needs a text title. Drawing ops need `open` then `sheet`.
- `marks` returns a list of maps of strokes without calling `show`.

These are covered by unit tests, not by the docs-examples job (interactive).

## Removed / absent

- No `compile` builtin — compilation is `compiler.vire`.
- No type, taint, or capability builtins.
- No `eval` of arbitrary strings as source except loading `.vire` files through `use`/`need`/`run`.
