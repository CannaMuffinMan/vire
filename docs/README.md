# Vire reference

This folder describes Vire **as the runner on this branch behaves**. It is not a roadmap. Planned work (a type checker, taint tracking, capability syntax) is called out only as planned.

| Page | What it covers |
| --- | --- |
| [Language](language.md) | Files, tokens, statements, expressions, limits, errors |
| [Standard library](stdlib.md) | Every builtin the interpreter and compiler expose today |
| [CLI](cli.md) | `vire` commands: run source, `run` a `.vc`, `keygen`, payload tools |
| [Security model](security.md) | What is enforced now versus what is planned |
| [Examples](examples/README.md) | Runnable programs checked in both interpreter and compiled mode |

The tutorial-style walkthrough remains [GUIDE.md](../GUIDE.md). The Hello World quickstart lives in a separate change; this reference does not repeat it.
