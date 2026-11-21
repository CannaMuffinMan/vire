# Native compiler notes

## Status: self-host proof closed

The gen1 = gen2 identical-binary self-host proof is done. The native compiler compiles itself and the second generation is byte-identical to the first, on both targets:

- Windows (PE): first proven in CI at PR #40 (merged 7c7c8ea), re-proven on security and Windows PE lanes since.
- Linux (ELF): re-proven on this tree; hello and compiler hex must match across two generations.

The rule stays the same: no merge without proof on real machines. Do not reopen self-host as a feature lane.

The Nov 5 work log, Phase 0 close-out map, Track D fuzz log, Windows handoff, integrate-38 notes, emit/compile probe timings, and the dedicated security-audit writeup are archived in [docs/history.md](docs/history.md). Live security evidence is [FINDINGS-LEDGER.md](FINDINGS-LEDGER.md). Live fuzz campaign notes are [FUZZ-CAMPAIGN.md](FUZZ-CAMPAIGN.md).

Caps unchanged: native arena 33554432, host list 100000, compiler itemCap 1e6, steps 5000000.
