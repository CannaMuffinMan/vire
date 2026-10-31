using System;
using System.Collections.Generic;
using System.Text;
using System.Text.RegularExpressions;
using Xunit;

public class CompiledParityTests
{
    [Fact]
    public void BuiltinArityMatchesInBothModesForEveryBuiltin()
    {
        List<string> names = new List<string>(Machine.Builtins);
        names.Sort(StringComparer.Ordinal);
        Assert.True(names.Count >= 50, "expected the full builtin table, got " + names.Count);
        StringBuilder report = new StringBuilder();
        foreach (string name in names)
        {
            int need = Machine.BuiltinNeed(name);
            if (need > 0)
            {
                CheckInProcess(name, need - 1, need, report);
                CheckArityCase(name, need - 1, need, report);
            }
            CheckInProcess(name, need + 1, need, report);
            if (name == "now")
                continue;
            CheckArityCase(name, need + 1, need, report);
        }
        Assert.True(report.Length == 0, report.ToString());
    }

    [Fact]
    public void UserDefinedArityErrorUsesRealLineAndColumnInBothModes()
    {
        string src = string.Join("\n", new string[]
        {
            "define twice with n",
            "  return n * 2",
            "end",
            "define main",
            "  say twice with 1, 2",
            "end",
            ""
        });
        DualMode.DualRun both = DualMode.RunSource(src, null);
        Assert.True(both.Matched, "user-call arity should match\n i " + both.InterpErr + "\n c " + both.CompErr);
        Assert.Equal(1, both.InterpCode);
        Assert.Contains("twice takes 1 values, got 2", both.InterpErr);
        Assert.Contains("twice takes 1 values, got 2", both.CompErr);
        Assert.Contains("line 5 col ", both.InterpErr);
        Assert.Contains("line 5 col ", both.CompErr);
        Assert.DoesNotContain("argument count", both.CompErr);
        Match icol = Regex.Match(both.InterpErr, @"line 5 col (\d+)");
        Match ccol = Regex.Match(both.CompErr, @"line 5 col (\d+)");
        Assert.True(icol.Success && ccol.Success, both.InterpErr + both.CompErr);
        Assert.Equal(icol.Groups[1].Value, ccol.Groups[1].Value);
        Assert.True(int.Parse(icol.Groups[1].Value) > 1, both.InterpErr);
    }

    [Fact]
    public void StepBudgetMessageHasNoLocationInBothModes()
    {
        string src = string.Join("\n", new string[]
        {
            "define main",
            "  let n be 1",
            "  while n == 1",
            "    let n be 1",
            "  end",
            "end",
            ""
        });
        DualMode.DualRun both = RunWithBudget(src, "20");
        Assert.True(both.Matched, "budget message should match\n i " + both.InterpErr + "\n c " + both.CompErr);
        Assert.Equal(1, both.InterpCode);
        Assert.Equal("vire: program ran too long and was stopped\n", DualMode.Norm(both.InterpErr));
        Assert.Equal("vire: program ran too long and was stopped\n", DualMode.Norm(both.CompErr));
        Assert.DoesNotContain("line", DualMode.Norm(both.InterpErr));
        Assert.DoesNotContain("col", DualMode.Norm(both.CompErr));
    }

    static void CheckInProcess(string name, int given, int need, StringBuilder report)
    {
        List<object> args = new List<object>();
        for (int i = 0; i < given; i++) args.Add(1);
        string want = name + " takes " + need + " values, got " + given;
        string interpMsg = InvokeInterp(name, args);
        string compMsg = InvokeCompiled(name, args);
        if (interpMsg != want)
            report.Append(name).Append(" interp in-process given ").Append(given).Append(": ").Append(interpMsg).Append("\n");
        if (compMsg != want)
            report.Append(name).Append(" compiled in-process given ").Append(given).Append(": ").Append(compMsg).Append("\n");
    }

    static string InvokeInterp(string name, List<object> args)
    {
        try
        {
            Machine machine = new Machine(new Dictionary<string, Func>(), ".");
            machine.UseBudget(500000);
            machine.Call(name, args, 2, 3);
            return "no error";
        }
        catch (VireError err) { return err.Message; }
        catch (Exception ex) { return ex.GetType().Name + ": " + ex.Message; }
    }

    static string InvokeCompiled(string name, List<object> args)
    {
        try
        {
            Budget budget = new Budget();
            budget.ApplyStepLimit(500000);
            CompiledMachine machine = new CompiledMachine(new Dictionary<string, object>(), ".", new List<object>(), budget);
            machine.Call(name, args, 2, 3);
            return "no error";
        }
        catch (VireError err) { return err.Message; }
        catch (Exception ex) { return ex.GetType().Name + ": " + ex.Message; }
    }

    static void CheckArityCase(string name, int given, int need, StringBuilder report)
    {
        DualMode.DualRun both = DualMode.RunSource(ArityProgram(name, given), null);
        string want = name + " takes " + need + " values, got " + given;
        if (!both.Matched)
            report.Append(name).Append(" given ").Append(given).Append(" outputs differed\n i ").Append(both.InterpErr).Append("\n c ").Append(both.CompErr).Append("\n");
        if (both.InterpCode != 1 || both.CompCode != 1)
            report.Append(name).Append(" given ").Append(given).Append(" expected exit 1, got ").Append(both.InterpCode).Append("/").Append(both.CompCode).Append("\n");
        if (DualMode.Norm(both.InterpErr).IndexOf(want, StringComparison.Ordinal) < 0)
            report.Append(name).Append(" interpreter missed '").Append(want).Append("': ").Append(both.InterpErr).Append("\n");
        if (DualMode.Norm(both.CompErr).IndexOf(want, StringComparison.Ordinal) < 0)
            report.Append(name).Append(" compiled missed '").Append(want).Append("': ").Append(both.CompErr).Append("\n");
        if (DualMode.Norm(both.InterpOut).Trim().Length > 0 || DualMode.Norm(both.CompOut).Trim().Length > 0)
            report.Append(name).Append(" given ").Append(given).Append(" should not print a value\n");
    }

    static string ArityProgram(string name, int given)
    {
        if (given == 0)
            return "define main\n  " + name + "\nend\n";
        StringBuilder args = new StringBuilder();
        for (int i = 0; i < given; i++)
        {
            if (i > 0) args.Append(", ");
            args.Append("1");
        }
        return "define main\n  " + name + " with " + args + "\nend\n";
    }

    static DualMode.DualRun RunWithBudget(string sourceText, string budget)
    {
        string root = DualMode.FindRoot();
        string work = System.IO.Path.Combine(root, "data", "conformance", Guid.NewGuid().ToString("N"));
        System.IO.Directory.CreateDirectory(work);
        try
        {
            string dest = System.IO.Path.Combine(work, "prog.vire");
            System.IO.File.WriteAllText(dest, sourceText);
            DualMode.Proc interp = DualMode.RunVire(root, new string[] { "prog.vire" }, work, budget);
            string relDir = System.IO.Path.Combine("data", "conformance", System.IO.Path.GetFileName(work));
            string relSrc = System.IO.Path.Combine(relDir, "prog.vire").Replace('\\', '/');
            string relVc = System.IO.Path.Combine(relDir, "prog.vc").Replace('\\', '/');
            DualMode.Proc compile = DualMode.RunVire(root, new string[] { "compiler.vire", relSrc, relVc }, root, "5000000");
            if (compile.Code != 0)
                return new DualMode.DualRun(false, interp.Code, compile.Code, interp.Out, compile.Out, interp.Err, compile.Err);
            DualMode.Proc compiled = DualMode.RunVire(root, new string[] { "run", relVc }, root, budget);
            bool matched = interp.Code == compiled.Code
                && DualMode.Norm(interp.Out) == DualMode.Norm(compiled.Out)
                && DualMode.Norm(interp.Err) == DualMode.Norm(compiled.Err);
            return new DualMode.DualRun(matched, interp.Code, compiled.Code, interp.Out, compiled.Out, interp.Err, compiled.Err);
        }
        finally
        {
            try { System.IO.Directory.Delete(work, true); } catch (System.IO.IOException) { }
        }
    }
}
