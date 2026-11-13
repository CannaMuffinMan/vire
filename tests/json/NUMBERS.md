# JSON number representation (host and native gen1 PE)

`json_decode` in `src/rt-json.vire` is the API-server decoder. Builtin `parse` is unchanged.

- A JSON integer whose magnitude fits in a signed 32-bit whole number becomes a Vire whole number. `-0` becomes `0`.
- Any JSON number with a fraction, an exponent (`e`/`E`), or a magnitude above `2147483647` becomes a one-key map `{"$n": "<token>"}`. `<token>` is the number spelling from the input (no surrounding whitespace). `json_encode` writes that token unquoted.
- `$n` is reserved for that box. A user object that only contains `$n` is encoded as a number.
- Duplicate object keys: last value wins.
- Max nesting depth is 16 (same as `schema_check`, stricter than host `parse` at 256). Call depth on host is 64; 16 keeps decode inside that cap. Walking uses the 100000 while-pass cap, so huge tokens fail closed.
