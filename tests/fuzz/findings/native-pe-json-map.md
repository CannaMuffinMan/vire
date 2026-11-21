# Native PE Unicorn: `json` of a map

Isolated from Linux Unicorn PE fuzz after merging `native-compiler` `6e969fc2` (compile-native invoked with the `pe` format flag).

Replay:

```
dotnet exec bin/Release/net10.0/vire.dll --compiler compile-native.vire tests/fuzz/findings/native-pe-json-map.vire /tmp/json-map.hex pe
python3 tools/native-pe-emu.py /tmp/json-map.hex
```

Observed: `UC_ERR_READ_UNMAPPED` at `0x140000010` range (emu: `5368724496`), `EXIT None`, empty stdout. Host interpreter of the same guest prints `{"a": 2}`.

Fixed on native-compiler: `rt_buf_finish` / `rt_int_text` now return the text object in rax, and the JSON blob reloads the encode buffer in rcx before writing `:`. Caps unchanged.
