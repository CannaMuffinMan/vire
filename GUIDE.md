# Vire guide

This is the manual for Vire. A person or a coding agent can follow it from a blank folder to a working program.

Vire is one language. Source files use the extension `.vire`. The runner is `vire.exe`. Definitions, data, packages, and windows are all written in Vire.

## 1. What a program is

A program is one or more definitions. A run starts at `define main` and stops at the matching `end`. `~` starts a comment that lasts until the end of the line.

```vire
~ prints 1 through 5
define main
  let n be 1
  while n <= 5
    say n
    let n be n + 1
  end
end
```

Run it from the folder that contains `vire.exe`:

```text
vire.exe count.vire
```

If `main` is missing, Vire stops before running anything.

## 2. Step by step: first program

1. Install nothing beyond Windows. The built `vire.exe` is the runner.
2. Create `hello.vire` in the same folder as `vire.exe`.
3. Put this in the file:

```vire
define main
  say "hello from vire"
end
```

4. Open a terminal in that folder.
5. Run `vire.exe hello.vire`.
6. The terminal prints `hello from vire`.

To rebuild the runner from source:

```text
C:\Windows\Microsoft.NET\Framework64\v4.0.30319\csc.exe /nologo /define:WINDOWS /r:System.Windows.Forms.dll /r:System.Drawing.dll /r:System.Net.Http.dll /out:vire.exe Vire.cs
```

## 3. Names and values

Create a name with `let` and `be`.

```vire
let n be 3
let who be "ada"
let ready be true
let empty be none
```

Values are numbers (whole or decimal), text in double quotes, `true`, `false`, and `none`.

Text escapes: `\"` `\\` `\n` `\t`.

Arithmetic: `+ - * / %`. `/` is ordinary division, so `5 / 2` is `2.5`. Comparisons: `== != < > <= >=`. Logic: `and`, `or`, `not`. Parentheses group expressions: `(1 + 2) * 3`.

`+` joins text, and also joins two lists. A call argument stops before `+`, so this prints `Vire</p>`:

```vire
say escape with "Vire" + "</p>"
```

Use parentheses when a single argument itself contains `+`: `area with (1 + 2), 4`.

`say` prints a line. `ask with "Name? "` reads one line from the terminal.

## 4. Decisions and loops

```vire
if n < 0
  say "negative"
else if n == 0
  say "zero"
else
  say "positive"
end

while n < 3
  say n
  let n be n + 1
end

for item in [1, 2, 3]
  if item == 2
    skip
  end
  say item
end
```

`skip` goes to the next pass of `while` or `for`. `stop` leaves the loop. Both are valid only inside a loop. A `while` that would run more than 100,000 passes is stopped. A program that performs more than 1,000,000 steps is stopped.

## 5. Definitions

```vire
define area with w, h
  return w * h
end

define main
  say area with 3, 4
end
```

Call a definition with `with`. Separate arguments with commas. `return` hands a value back. Without `return`, a definition yields `0`. Calls cannot nest more than 64 deep. Each definition has its own names.

## 6. Lists and maps

```vire
let nums be [9, 2, 3]
push with nums, 4
put 1 into nums at 0
say nums at 0
say length with nums

let person be {"name": "ada", "year": 1815}
say person at "name"
say has with person, "year"
```

`at` reads a list, a text character, or a map entry. `put ... into name at index` writes into a list or a map. Lists and maps cannot grow past 100,000 items.

Useful operations:

| Call | Result |
| --- | --- |
| `length with value` | size of text, a list, or a map |
| `push with list, item` | appends and returns the list |
| `drop with list` | removes and returns the last item |
| `slice with value, start, end` | a copy of that range |
| `keys with map` | a list of keys |
| `has with map, key` | `true` when the key exists |
| `join with list, "-"` | text joined by the separator |
| `split with text, ","` | a list of pieces |
| `find with text, "a"` | index, or `-1` |
| `lower with text` / `upper with text` | letter case |
| `sort with list` | a new list of numbers, low to high |
| `span with 1, 3` | `[1, 2, 3]` |
| `abs with n` / `min with a, b` / `max with a, b` | numbers |
| `text with value` / `number with text` | convert |
| `kind with value` | `number`, `text`, `list`, `map`, `bool`, or `none` |
| `replace with text, "a", "b"` | text with each `a` changed to `b` |
| `begins with text, "vi"` / `ends with text, "re"` | `true` or `false` |
| `round with 2.5` | nearest whole number |
| `pick with 4` | a whole number from 0 through 3 |
| `exists with "data/log.txt"` | `true` when that file or folder is in the program folder |
| `folders with "."` | folder names in a directory |
| `append with "data/log.txt", "two"` | adds text to the end of a file |
| `copy with "a.txt", "b.txt"` | copies inside the program folder |
| `erase with "data/log.txt"` | deletes a file in the program folder |
| `clear` | removes every mark on the current sheet |

`for name in map` walks the keys. `for name in text` walks characters.

## 7. Failures

```vire
try
  say number with "nope"
miss problem
  say problem
end
```

`miss` runs when a Vire error happens inside `try`. The name after `miss` receives the message.

## 8. Files

`read` and `write` stay inside the program folder. Absolute paths and `..` are refused. Vire will not write `.exe`, `.dll`, `.bat`, `.cmd`, `.ps1`, `.com`, `.scr`, `.vbs`, or `.msi`. A single file it reads or writes cannot exceed 1,000,000 characters. `write` creates missing folders under the program folder.

```vire
write with "data/note.txt", "hello"
say read with "data/note.txt"
say files with "data"
```

`files with "data"` returns the file names in that folder, not a tree of the whole disk.

## 9. Data, time, and the network

```vire
let tasks be [{"title": "Write Vire", "done": true}]
write with "data/tasks.json", json with tasks
let loaded be parse with read with "data/tasks.json"
say now
```

`json` turns a Vire value into text. `parse` turns that text back into a value. `now` is the local time as `yyyy-MM-dd HH:mm:ss`, and it is a word of the language, so you can write `say now`. A definition that ends without `return` yields `none`. A definition with no parameters can be used by its bare name.

`fetch with "https://example.com"` performs one HTTP GET. The address must start with `http://` or `https://`. The wait is at most 5 seconds, and the body is at most 1,000,000 bytes.

## 10. Packages

A package is a folder under `deps`. Its code lives in `lib.vire`. The package name is a word of letters, digits, and underscores.

`deps/ui/lib.vire`:

```vire
define page with title, body
  return "<p>" + (escape with title) + "</p>" + body
end
```

Program:

```vire
need "ui"

define main
  say page with "Hello", "<p>Body</p>"
end
```

`use "math.vire"` loads another file in the program folder. `use` only opens `.vire` files, refuses `..`, and refuses a loop of files. At most 32 files are loaded.

## 11. Step by step: a window

`work.vire` is the sample application. It does not use another programming language.

```vire
define save_note
  write with "data/note.txt", value with "note"
  line with "Saved"
end

define main
  open with "Vire tasks"
  line with "Write Vire — done"
  line with "Open the site — open"
  field with "note"
  button with "Save", "save_note"
  show
end
```

1. `open` creates the window and sets its title.
2. `line` adds a line of text.
3. `field` adds an editable box. The name is how you read it later.
4. `button` adds a button. The second argument is the definition to call when it is clicked.
5. `value with "note"` reads that box.
6. `show` displays the window and waits until it is closed.
7. `place with 16, 80` sets where the next line, field, or button goes.
8. `sheet with 420, 260` adds a white drawing surface.
9. `ink with 176, 98, 58` chooses the color for later drawing. The numbers run from 0 to 255.
10. `fill` paints a rectangle. `stroke` paints a line. `dot with x, y, 6` paints a circle.
11. `watch with "tapped"` calls that definition with the click's x and y. The definition draws by calling `ink` and `dot` again. `board.vire` is that program.

Start a window program with `term` when it should run in the terminal instead of a desktop window. The same `open`, `line`, `field`, `button`, `sheet`, `ink`, `fill`, `stroke`, `dot`, and `show` words apply. Without `term`, Windows opens a desktop window. `term.vire` is the terminal sample. `screen` returns the lines added so far.

`marks` returns the sheet's drawings as a list of maps, without `show`. `picture` in `checks/core.vire` checks that list. A build of the runner without a desktop window still runs that check.

Run `vire.exe work.vire`. Type in the box, press Save, and look at `data/note.txt`.

## 12. Step by step: a local site

Vire writes the browser files, then serves that one folder on this computer only. Browsers read HTML, CSS, and JavaScript, so those files are the output. The program that creates them is Vire.

`vault.vire` is the one-shot local experiment:

1. Run `vire.exe vault.vire`.
2. It lists `site/videos` with `files`, keeps names that end in `.mp4`, `.webm`, or `.ogv`, and writes `site/catalog.json`.
3. It writes `site/index.html`, `site/vault.css`, and `site/vault.js`. The page has a player, a playlist, and a search box. The script loads the catalog and points the player at `videos/` plus the file name.
4. It also writes a branching story (`site/story.html`, `site/story.json`) that remembers the last room in the browser, and a dashboard (`site/dash.html`, `site/data.json`) that loads its numbers with `fetch`.
5. Run `vire.exe serve.vire` and open `http://127.0.0.1:8080/`.
6. Press Ctrl+C to stop the server.

Put real clips in `site/videos`, run `vault.vire` again, and the playlist matches the folder. The server allows `.html`, `.css`, `.js`, `.svg`, `.json`, `.txt`, `.mp4`, `.webm`, and `.ogv`. Video files may be up to 512 MB and are read from disk in pieces, including a byte range for seeking. Other files stay at 1 MB. The listener is `127.0.0.1` only. A run prints a key. Open `http://127.0.0.1:8080/?key=` plus that key. The browser then sends the key as a cookie. A request without the key is refused, including a post to `/inbox`. `fetch` and `post` refuse localhost and private network addresses. `read`, `write`, `append`, `copy`, `erase`, `files`, and `folders` work only in `data` and `site`. A link or junction in the folder is refused. `..` is refused. The port must be from 1024 through 65535.

The window in section 11 stays inside Vire. The site path is for a browser.

## 13. Use cases

1. Print a sequence or a total, as `count.vire` does.
2. Convert units in a definition that takes a number and returns a number.
3. Ask a question in the terminal and branch with `if`.
4. Keep records in a map and look them up with `at`.
5. Walk a list of scores, `skip` the blanks, and add the rest.
6. Clean text with `split`, `lower`, `join`, and `sort`.
7. Save a note with `write` and load it with `read`.
8. Share helpers through `need` and `deps/<name>/lib.vire`.
9. Catch a bad conversion with `try` and `miss`.
10. Open a small desktop tool with `open`, `field`, `button`, and `show`, as `work.vire` does.
11. Save a list of records as JSON, then build a page from those records.
12. Serve that page on this computer with `serve`.
13. Build a private media vault, a branching story, and a dashboard in one run with `vault.vire`, then open them through `serve`.
14. Run the small systems under `systems/`: a block chain, a tiny expression language, a page reader, a search index, a file-system image, an in-memory frame, and a virtual CPU that schedules two guests.

## 14. Rules an agent should follow

- Put every program in the folder with `vire.exe`, or pass a path to a `.vire` file. The file's folder is the sandbox root.
- Start every runnable file with definitions, and include `define main` in the file you pass to `vire.exe`. Packages must not require their own `main`.
- Call definitions as `name with arg`. A bare name with no parameters, and the words `now` and `show`, run with no `with`.
- A call argument stops before `+`. Parenthesize an argument that itself uses `+`.
- Keep paths relative. Do not invent `..` or drive letters.
- Do not ask Vire to write an executable or a script. That is refused.
- Prefer the window operations for an application. Use `serve` only when the result must be a browser page.
- After changing `Vire.cs`, rebuild `vire.exe` with the `csc` command in section 2 before running samples.

## 15. Limits

Vire is a general-purpose language for programs, files, packages, windows, and a local site. It does not ship a public package index, a phone store, or device-driver tooling. File and package access stays in the program folder so a sample cannot wander across the disk.
