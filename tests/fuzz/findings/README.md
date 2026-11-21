Minimized reproducers from the fuzz campaign live here (`*.vire` / `*.txt` plus a `*.md` note).

Recorded after merging `native-compiler` `6e969fc2` (Linux Unicorn PE, compile-native `pe` flag), then fixed on the same line. Keep the guests as regressions:

- `native-pe-json-map.vire` — was native `json` of a map Unicorn `UC_ERR_READ_UNMAPPED`; host and native must print `{"a": 2}`
- `native-pe-parse-array.vire` — was native `parse` of `[1,true,null]` Unicorn `UC_ERR_WRITE_UNMAPPED`; host and native must succeed

Do not delete a reproducer that is listed in `FUZZ-CAMPAIGN.md`. Binary blobs and sealed `.vc` files stay out of this folder.
