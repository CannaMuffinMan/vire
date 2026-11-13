# Vire language (grammar notes)

This file records the exact `if` / `else if` / `else` grammar after the host and `compile-native` parsers bind those chains the same way.

## If, else-if, else

```
if_stmt   := "if" expr then_block else_tail "end"
else_tail := "else" "if" expr then_block else_tail
           | "else" then_block
           | ε
then_block := stmt*
```

`else if` is two tokens (`else` then `if`), not a third keyword. One `end` closes the whole chain.

A nested `if_stmt` inside a `then_block` that has its own `end` keeps its own `else` (if any). A nested `if` that has no `end` before the enclosing chain's `else` does **not** take that `else`; the `else` belongs to the enclosing `if` / `else if` / `else` chain. That keeps the chain's `end` from closing the surrounding `define` too early.

```vire
define decode with n
  if n == 1
    return "one"
  else if n == 2
    if n == 2
      return "two"
  else
    return "params"
  end
end
```

`decode with 3` yields `params`. `decode with 2` yields `two`.

Guests still stop at 64 call frames. Arena 32MB, list 100000, and the 5M step budget are unchanged.
