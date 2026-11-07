# Native selfhost checklist

Standing on its own means gen1 (native PE of `compile-native.vire`) compiles `compile-native.vire` plus a guest to gen2, and gen1.hex == gen2.hex. Hello hex equality is not that proof.

This file is the compiler/performance lane. Native path/frame/intern stay PR #35 / PR #31.

## Proof steps

1. Host interprets `compile-native.vire` and emits a PE that includes `rt_extend` (this PR). `compile-native` must accept `extend` as a 2-arg builtin. **Host emit of an `extend` guest: required. Running that PE: Windows-only.**
2. Copy compiler sources under `data/` (or `data/src/`) so native `read` can load them. **Open.** This tree has no `data/src/`.
3. Windows: host-compile `compile-native.vire` itself (timeout, do not run overnight). **Open. Linux cannot run the PE.**
4. Windows: gen1.exe compiles hello. stdout `hello from stage`, exit 0. **Open.**
5. Windows: gen1.exe compiles `compile-native.vire` to gen2. hex SHA match. **Open. 32MB / intern (PR #31) is the likely arena blocker.**
6. Caps stay 5e6 steps, list 100000 on the host, 32MB native arena. Do not raise them.

## This PR

`extend` was host C# + CompiledMachine only. `compile-native.vire` printed `there is no definition named extend` (measured). That would make gen1 unable to compile `emitList`. Frontend `builtinArity` and native `rt_extend` close that hole. `rt_extend` lives at the end of `emitMore` in `src/rt-more.vire`, after `rt_join`. PR #35 edits earlier `path_ok` / IAT hunks in the same file. Do not copy those.

## Windows recipe

```text
set VIRE_BUDGET=5000000
dotnet exec bin\Release\net10.0\vire.dll compile-native.vire data\extend-guest.vire data\extend-guest.hex
dotnet exec bin\Release\net10.0\vire.dll compile-native.vire data\guest-hello.vire data\guest-hello.hex
```

To run the PE, use a Windows box. Do not run `native-selfhost-proof.ps1` for hours. Stop at the first missing `data/src` read or 32MB fail.
