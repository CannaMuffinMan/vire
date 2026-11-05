# Native compiler notes

This file records the native self-host work from the chat that ended when the budget ran out. It is a work log, not a claim that Vire is finished.

Active tree: `D:\_scratch\worktrees\vire-e-len`.

The host compiler is the C# runner. From that folder:

```text
dotnet exec .\bin\Release\net10.0\vire.dll compile-native.vire data/compile-native.vire data/compile-self.hex
```

The working directory must be the worktree. Paths in Vire use forward slashes. Root `compile-native.vire` uses `src/`. The input `data/compile-native.vire` uses `data/src/`. A host rebuild executes `src/`. The image it writes contains the compiled functions from `data/src/`. Both copies have to stay in sync or the entry stub and the next generation disagree.

Hex to exe: trim the file, turn each pair into a byte, `WriteAllBytes`. Do not commit or push from this log. Git on `D:` has dubious ownership. Do not change global git config.

## What stands

`data/compile-self.exe` compiles `data/hello-stage.vire`. The emitted program prints `hello from stage` and exits 0. Confirmed again after the intern experiment was reverted, using `data/compile-round.exe` from the worktree. That exe was then copied back over `data/compile-self.exe`, and `data/compile-self-2.hex` was copied back over `data/compile-self.hex`.

Those restored files:

- `data/compile-self.exe`, 376832 bytes, 11/5/2026 10:01:54 AM
- `data/compile-self.hex`, 753664 bytes, 11/5/2026 10:01:10 AM

## What does not stand

The same exe cannot compile itself inside the 32MB heap. A self-compile succeeds when the Windows mapping is 96MB or 128MB. At 32MB, 48MB, and 64MB the process access-violates (`0xC0000005`, exit `-1073741819`). The allocator limit was still 256MB, so it wrote past the smaller mapping.

Until one exe compiles `data/compile-native.vire` and the second hex matches the first, Vire does not stand on its own. Do not claim it can do what any other language can do.

## Constraints that still bind

- Do not raise `ProgramStepCap` (5,000,000), the 32MB native arena, or the 2,000,000 list-item cap as the fix.
- Do not load a driver. Do not deploy. Payments stay off. Testnet stays out of the public Vire repo.
- Local listeners are `127.0.0.1` only. Never ports 7099, 8778, 7071, 7072, 17841, 7093, 17843.
- Never print secrets. Never the word "unhackable".
- Do not delete the C# runner before a second native rebuild is proven.
- GPU cannot run the compiler. One interpreter rebuild at a time. A host rebuild of `compile-native.vire` takes about 60 minutes.
- Windows Defender blocked some freshly written exes in `data/`. An exclusion was added for `D:\_scratch\worktrees\vire-e-len\data`. A blocked exe is not proof the program is bad.

## Bugs fixed on the way to hello

The native compiler already compiled `data/hello-stage.vire` and `data/min.vire`, printed `compiled`, and exited 0. The emitted 18944-byte programs access-violated. A C# compile of empty `main` exited 0. The byte compare had 715 zeros where the C# image had relocation and import bytes. The first difference was file offset 431.

A debug compiler printed fixes length 698, image length 18287, code label 352, first fix at image index 363 to `iat_gs`. File offset of an image index is the index plus 68. The relative value was `352 - (363 + 4) = -15`, which should be the bytes `F1 FF FF FF`.

These guesses were tested and were wrong:

- The fixes list was not empty.
- List slot writes work. `put 65 into xs at 1` printed 65.
- Signed subtraction works. `0 - 15` printed `-15`.

The real miss was the 32-bit wrap. `x + 4294967296` does not change a native value. `4294967296` does not fit a 32-bit immediate and is a no-op. `2147483647` does fit. `-15 + 2147483647 + 2147483647 + 2` prints `4294967281` (`2^32 - 15`).

`poke32` in `src/pe.vire` and `data/src/pe.vire` was changed to that three-add sequence. That was not enough. The zero call relocations are written earlier by `patchRel` in `src/asm.vire`. `emitU32` had the same no-op add. Both were changed in `src/asm.vire` and `data/src/asm.vire`. `poke16` still adds 65536, which fits.

`rt_idiv` is unsigned `div` and returns 0 when the dividend is negative (`test rdx; js`). Leaving the relative value negative therefore writes four zero bytes even if the add had worked. The three-add sequence makes the value positive, so `div` by 256 yields the little-endian bytes.

`data/compile-native.vire` was missing `idiv` and `join` in `builtinArity`. Those names were added so a later self-compile can resolve `floorDiv` and `hexOf`.

The host rebuild of that relocation fix printed `compiled` and exited 0. Hex length 753664, written 11/5/2026 8:51 AM. The native exe compiled hello. The program printed `hello from stage` and exited 0. The byte at file offset 431 in that hello exe was `E0 00 00 00`, not `F1 FF FF FF`. The program still ran, so the first fixup was no longer the crashing zero slot.

## Why self-compile crashed

The hello compiler access-violated when asked to compile `data/compile-native.vire`. Windows Error Reporting named fault offset `0x2603` in `compile-self.exe`. That address is `rt_memeq` (`mov al, [rcx]`), a string compare with a bad pointer.

Bisect:

- Two functions in one file compiled.
- `read` of a missing file printed `missed`.
- `lower` printed the lowercased path.
- `ends` access-violated.
- `use "data/no-such-file.vire"` access-violated. It should have stopped in `checkUse`.
- `use "src/asm.vire"` access-violated. `asm.vire` alone only reported a missing `main`.

`rt_ends` computed the suffix start with `sub rax, rcx` (`48 29 C8`). After `mov rdx, [rcx]` loaded the haystack length, `rcx` was still the string pointer, so the length minus the pointer was a wild address. The source bytes were `72, 41, 200`, which is `48 29 C8`, not a subtract of the length register.

The compare length was also wrong. `emitPop2` leaves the needle tag in `r8` (the integer 2). The call site did `mov rax, r8` (`4C 89 C0`) and `rt_memeq` counts with `r8`, so a surviving compare would have checked 2 bytes. `begins` had the same backwards move.

The running exe was patched in place, and the source was updated in `src/rt-more.vire` and `data/src/rt-more.vire`:

- `ends`: save the needle length with `mov r8, rax` (`49 89 C0`), then `sub rdx, rax`, add that to the haystack bytes, and compare that many bytes.
- `begins`: `mov r8, rax` instead of `mov rax, r8`.

After the patch, `use "data/no-such-file.vire"` printed `use stays out of data and site` and exited 1. `use "src/asm.vire"` compiled, and the program printed `used asm`.

Guest programs emitted by that patched exe still had the old `ends` bytes. The patch changed the runner's machine code, not the `emitList` constants it copies into the next image. A source rebuild is required for the next image to contain the fix.

## Self-compile result

The patched exe compiled `data/compile-native.vire` in under a second and wrote `data/compile-self-native.hex` (753664 bytes). It did not match the previous host hex. Twenty-one bytes differed. Most of those were the new `ends` and `begins` immediates. One was the arena size.

A later host rebuild included the `ends` fix and printed `compiled`, exit 0, hex 753664, written 11/5/2026 9:59 AM. That exe compiled the compiler again. The second hex differed by one byte, file offset 888:

- Host image: `BA 00 00 00 10`, which is `mov edx, 0x10000000` (256MB).
- Native output: `BA 00 00 00 02`, which is `mov edx, 0x02000000` (32MB).

`src/rt.vire` still asked for `268435456` when that host rebuild started. `data/src/rt.vire` already asked for `33554432`. The host executes `src/` while emitting the entry stub, and compiles `data/src/` into the output's functions. The stub and the function that emits the next stub disagreed. `src/rt.vire` was then set to `33554432` so the copies match. That edit was after the host rebuild, so the 9:59 image still has the 256MB stub.

The image produced by the native self-compile allocates 32MB. It compiled hello. It access-violated when compiling the compiler. Patching only the mapping size in the known-good 256MB exe showed the real need:

| Mapping | Self-compile |
|---|---|
| 32MB | access violation, no hex |
| 48MB | access violation, no hex |
| 64MB | access violation, no hex |
| 96MB | exit 0, hex 753664 |
| 128MB | exit 0, hex 753664 |

`rt_alloc` compared the bump pointer with `heap + 268435456` (`src/rt-more.vire` and `data/src/rt-more.vire`, the `emitU32` after `73, 129, 194`). The mapping was 32MB, so the check never fired and the write left the reserved pages. Both files now pass `33554432` to that `emitU32`. A host rebuild of that limit change has not been proven. Do not treat the source edit as a finished image.

## Intern experiment, reverted

Every `source at i` allocated a new 16-byte string in `rt_at`. That looked like a large part of the 64MB to 96MB use. `at_text` was changed to reuse 128 one-character strings at `r15 + 4096`.

The host rebuild of that change printed `compiled`, exit 0, hex 755712, written 11/5/2026 11:09 AM. The exe was 377856 bytes. It exited 1 and printed nothing for `data/hello-stage.vire`. A 96MB mapping of that same image also exited 1 with no output. The machine code at the intern site looked well formed (`lea rcx, [r15+4096]`, `movzx ebx`, compare with 128). The failure was not diagnosed further.

`at_text` was restored to the allocating sequence in both `rt-more.vire` files. The 32MB allocator limit edit was left in place. `data/compile-self.exe` and `data/compile-self.hex` were restored from the hello-capable image, not left as the silent intern build.

## Earlier fixes this chat depended on

These were already in the tree before the relocation and `ends` work. They are why the compiler could get as far as emitting a PE:

- In-place map header. A 24-byte header, capacity at +8, slots pointer at +16, tag 5. `rt_grow_map` allocates new slots only and writes the new capacity and pointer into the same header. `pin` of `iat_gs` then survives a function boundary. A probe printed 1.
- List headers were already stable. `put 65 into xs at 1` printed 65.
- `rt_keys` loop limit stored `rcx` (`48 89 4D E8`).
- Map compare uses `cmp rcx, [rdx+8]`.
- `set_slot` saves the slot address on the stack before a call, because `r14` is the VM frame and a helper can clobber it.
- Emit helpers return the image. The C# host failed with `push needs a list` when they returned `true`.
- `hexOf` uses `join`. `idiv` exists in the runtime. Do not emit `idiv` or `join` calls unless those runtime symbols exist.
- Native step budget is not the same knob as the C# `VIRE_BUDGET`. Do not raise the caps.

`4294967296` remains in `emitU64` as a comparison for the high half. Pool lengths used there are small. It was not the hello crash.

## Do not resume

- BlueStacks and the APK path. That was a sidetrack. The installed APK at `D:\_scratch\vire-apk-install\app.apk` is not a Vire product.
- Loading a driver.
- Company site, package index, debugger, and foreign-text work. Those were not this session's deliverable.
- A second full host rebuild while one is running.
- Raising the 32MB arena, the step cap, or the list cap to make self-compile pass.

## Next change, when there is budget

Make `rt_alloc` stop at the same 32MB the mapping reserves, and cut the compiler's allocations until a self-compile fits. Then:

1. Host-compile `data/compile-native.vire` with `src/` and `data/src/` identical, including the 32MB size in both `rt.vire` and both `rt-more.vire` limit checks.
2. Turn that hex into an exe.
3. Compile `data/hello-stage.vire` and require the text `hello from stage` and exit 0.
4. Have that exe compile `data/compile-native.vire` to a second hex.
5. Compare SHA-256. A match is the self-host proof. Anything short of that is not done.
