# Vire language (grammar notes)

## `at`

`at` reads a list, a text character, or a map entry (GUIDE §6). Host and gen1 native PE use the same rules:

```
lookup := expr "at" expr
```

- **List or text.** The index must be a whole number (negative wraps from the end). Otherwise both print `an index must be a whole number`.
- **Map / record.** The key must be text or a number (`map keys must be text or numbers`). Text keys work, including `u at "id"` and keys stored with `put value into map at (slice with ...)`. Missing key: `map has no key ` plus the key.
- **Anything else** (`none`, bool, …). Both print `at needs a list, text, or map`.

`put ... into name at index` writes a list slot or a map entry under the same key rules.

Guests still stop at 64 call frames. Arena 32MB, list 100000, and the 5M step budget are unchanged.
