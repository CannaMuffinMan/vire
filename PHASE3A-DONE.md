# Phase 3A done-criteria map

Each Phase 3A done-criterion from `VIRE-ROADMAP.md` is listed with the test or CI job that proves it.

| Done-criterion | Proof |
|---|---|
| compiler.vire understands `for`, `else if`, `try/miss`, `use/need`, map literals, and decimals | `ConformanceTests.GrammarProgramsMatchInBothModes` (`tests/conformance/else-if.vire`, `for-skip.vire`, `try-miss.vire`, `map-decimal.vire`, `use_main.vire`, `span-sort-drop.vire`, `files-folders.vire`) |
| CompiledMachine reports the real line **and** column | `ConformanceTests.CompiledDivisionErrorUsesRealLineAndColumn` (`tests/conformance/boom.vire`); `ConformanceTests.ErrorProgramsAssertLineAndColumnInBothModes` (`tests/conformance/errors/*.vire` each carries `~ expect line N col M`) |
| One shared conformance suite: ~60 harness tests plus `tests.vire`, `checks/`, `systems/` | `dotnet test tests/Vire.Tests/Vire.Tests.csproj` (linux `test` job). Suite programs: `ConformanceTests.SuiteProgramsMatchInBothModes` and `SuiteTests.InterpreterSuitePasses`. Grammar programs as above. |
| 100% of that suite passes in interpreter mode and compiled `.vc` mode | `ConformanceTests.SuiteProgramsMatchInBothModes` and `GrammarProgramsMatchInBothModes` require exit code 0 in both modes |
| Interpreter and `.vc` **raw** stdout and stderr are identical | `DualMode.CompareFile` compares un-normalized-except-newlines stdout and stderr (`DualMode.Norm` only maps `\r\n` → `\n`). Every dual-mode test uses `both.Matched` |
| Every crash test runs in both modes and never kills the process | `CrashTests.CrashFixturesStayAlive`, `WhilePassLimitFollowsStepBudget`, `RunawayWhileIsStillStopped` (process dual-run); in-process `CompiledWhilePassLimitFollowsStepBudget` and `JsonAndShowRefuseAdversarialValuesInProcess`. Dual-run asserts exit code is not 3 (internal error) |
| Well-shaped junk `.vc` steps (bad opcodes, bad operand types, out-of-range jumps, stack underflow) are rejected cleanly | `CompiledJunkTests.LoaderRejectsBadOpcodeOperandJumpAndUnderflow`, `ExecutionRejectsJunkWithoutThrowingClrExceptions`, `SealedJunkVcIsRejectedCleanly` |
| Seeded junk-step fuzz in normal `dotnet test` | `CompiledJunkTests.SeededFuzzNeverThrowsClrExceptions` (seed `20261030`, 250 trees) |
| Stage 1 = stage 2 = stage 3 self-host fixpoint | CI jobs `selfhost` (`tools/selfhost-check.sh`) and `selfhost-windows` (`tools/selfhost-check.ps1`) |
| WinForms window builtins that cannot run headless on Linux | Covered by CI job `windows-gui` (`dotnet build windows/vire.windows.csproj` and `dotnet test tests/Vire.Windows.Tests`). `WinFormsTests.OpenLineFieldButtonSheetCreateARealFormWithoutShowLoop` builds a real `Form` via `open`/`line`/`field`/`button`/`sheet` without `Application.Run`. Linux uses the terminal (`term`) path; `checks/core.vire` `picture` plus `BuiltinParityTests.TermWindowShowClosesOnZeroInBothModes` cover that path in both modes. Compiled `.vc` never calls `Application.Run` (always `TermShow`) so dual-mode stdout stays identical on Linux CI — listed here, not stubbed. |

## Headless Linux exceptions (reasoned)

1. **WinForms `Application.Run` desktop loop** — requires a Windows message pump and an interactive session. Proven on `windows-gui` / `windows-latest`. Linux and compiled `.vc` use the terminal UI (`term` / `TermShow`).
2. **Native x64 smoke** — already on `native-windows`; not a Phase 3A language-suite item.

## Not in Phase 3A (open owner decisions)

Type checker, capability syntax (`define main with world`), and POST `/block` authorization. Track F (crypto/JSON stdlib) is a separate branch.
