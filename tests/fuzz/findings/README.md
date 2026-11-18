Minimized reproducers from the fuzz campaign live here (`*.vire` / `*.txt` plus a `*.md` note).

Recorded after merging `native-compiler` `6e969fc2` (Linux Unicorn PE, compile-native `pe` flag):

- `native-pe-json-map.vire` — native `json` of a map faults Unicorn (`UC_ERR_READ_UNMAPPED`)
- `native-pe-parse-array.vire` — native `parse` of `[1,true,null]` faults Unicorn (`UC_ERR_WRITE_UNMAPPED`)

Do not delete a reproducer that is listed in `FUZZ-CAMPAIGN.md`. Binary blobs and sealed `.vc` files stay out of this folder. Product code is not patched in the fuzz PR.
