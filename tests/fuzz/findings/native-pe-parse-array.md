# Native PE Unicorn: `parse` of a JSON array

Isolated from Linux Unicorn PE fuzz after merging `native-compiler` `6e969fc2` (compile-native invoked with the `pe` format flag).

Replay:

```
dotnet exec bin/Release/net10.0/vire.dll --compiler compile-native.vire tests/fuzz/findings/native-pe-parse-array.vire /tmp/parse-array.hex pe
python3 tools/native-pe-emu.py /tmp/parse-array.hex
```

Observed: `UC_ERR_WRITE_UNMAPPED` at `5368745172`, `EXIT None`. Host interpreter of the same guest succeeds.

The campaign `grammar-builtins.vire` seed hits this after printing split/at/cat/text/has, then faults on `parse`/`json`.

Fixed on native-compiler: parse cursor is `{ptr, end}` (not length-as-pointer), skip reloads the cursor from `[rbp-8]`, and cmp/movzx walk the text pointer. Caps unchanged.
