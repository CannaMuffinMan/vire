using System;
using System.Collections.Generic;
using System.IO;
using Xunit;

public class BudgetCapTests
{
    [Fact]
    public void EnvBudgetCannotExceedProgramCap()
    {
        string previous = Environment.GetEnvironmentVariable("VIRE_BUDGET");
        try
        {
            Environment.SetEnvironmentVariable("VIRE_BUDGET", "5000001");
            VireError err = Assert.Throws<VireError>(() => Program.BudgetOf("define main\nend\n"));
            Assert.Contains("5000000", err.Message);
            Environment.SetEnvironmentVariable("VIRE_BUDGET", "5000000");
            Assert.Equal(5000000, Program.BudgetOf("define main\nend\n"));
        }
        finally
        {
            Environment.SetEnvironmentVariable("VIRE_BUDGET", previous);
        }
    }

    [Fact]
    public void EndlessLoopStillStopsAtProgramCap()
    {
        string dir = Path.Combine(Path.GetTempPath(), "vire-budget-" + Guid.NewGuid().ToString("N"));
        Directory.CreateDirectory(dir);
        string previous = Environment.GetEnvironmentVariable("VIRE_BUDGET");
        try
        {
            File.WriteAllText(Path.Combine(dir, "loop.vire"), "define main\n  while true\n  end\nend\n");
            Environment.SetEnvironmentVariable("VIRE_BUDGET", "100000");
            string cwd = Directory.GetCurrentDirectory();
            Directory.SetCurrentDirectory(dir);
            try
            {
                int code = Program.Execute(new string[] { "loop.vire" });
                Assert.NotEqual(0, code);
            }
            finally
            {
                Directory.SetCurrentDirectory(cwd);
            }
        }
        finally
        {
            Environment.SetEnvironmentVariable("VIRE_BUDGET", previous);
            try { Directory.Delete(dir, true); } catch (IOException) { }
        }
    }

    [Fact]
    public void NormalListStillStopsAtOneHundredThousand()
    {
        string dir = Path.Combine(Path.GetTempPath(), "vire-budget-" + Guid.NewGuid().ToString("N"));
        Directory.CreateDirectory(dir);
        try
        {
            File.WriteAllText(Path.Combine(dir, "prog.vire"), "define main\nend\n");
            Machine machine = new Machine(Program.Load(Path.Combine(dir, "prog.vire"), dir, new System.Collections.Generic.HashSet<string>()), dir);
            List<object> list = new List<object>();
            for (int i = 0; i < 100000; i++) machine.Call("push", new List<object> { list, 1 }, 1, 1);
            VireError err = Assert.Throws<VireError>(() => machine.Call("push", new List<object> { list, 1 }, 1, 1));
            Assert.Contains("too large", err.Message);
        }
        finally
        {
            try { Directory.Delete(dir, true); } catch (IOException) { }
        }
    }

    [Fact]
    public void LargeJobFinishesUnderProgramStepCap()
    {
        string source = "define main\n  let n be 0\n  let s be 0\n  while n < 200000\n    let n be n + 1\n    let s be s + n\n  end\n  let items be []\n  let i be 0\n  while i < 10000\n    let row be {\"a\": i, \"b\": i + 1}\n    push with items, row\n    let i be i + 1\n  end\n  say s\n  say length with items\nend\n";
        string dir = Path.Combine(Path.GetTempPath(), "vire-budget-" + Guid.NewGuid().ToString("N"));
        Directory.CreateDirectory(dir);
        try
        {
            string path = Path.Combine(dir, "job.vire");
            File.WriteAllText(path, source);
            Machine machine = new Machine(Program.Load(path, dir, new HashSet<string>()), dir);
            machine.UseBudget(Program.ProgramStepCap);
            machine.Run();
            Assert.True(machine.budget.Steps < 5000000, "steps " + machine.budget.Steps);
            Assert.True(machine.budget.Steps > 0);
            Assert.True(machine.budget.WhilePasses <= 210000, "passes " + machine.budget.WhilePasses);
        }
        finally
        {
            try { Directory.Delete(dir, true); } catch (IOException) { }
        }
    }

    [Fact]
    public void EndlessStatementLoopStillStopsAtProgramCap()
    {
        string dir = Path.Combine(Path.GetTempPath(), "vire-budget-" + Guid.NewGuid().ToString("N"));
        Directory.CreateDirectory(dir);
        try
        {
            string path = Path.Combine(dir, "loop.vire");
            File.WriteAllText(path, "define main\n  let n be 0\n  while true\n    let n be n + 1\n  end\nend\n");
            Machine machine = new Machine(Program.Load(path, dir, new HashSet<string>()), dir);
            machine.UseBudget(Program.ProgramStepCap);
            VireError err = Assert.Throws<VireError>(() => machine.Run());
            Assert.True(
                err.Message.Contains("too long") || err.Message.Contains("was stopped"),
                err.Message);
            Assert.True(machine.budget.Steps <= Program.ProgramStepCap);
            Assert.True(machine.budget.WhilePasses <= Program.ProgramStepCap + 1);
        }
        finally
        {
            try { Directory.Delete(dir, true); } catch (IOException) { }
        }
    }

    [Fact]
    public void RenamedLoopDoesNotGetCompilerBudget()
    {
        string dir = Path.Combine(Path.GetTempPath(), "vire-budget-" + Guid.NewGuid().ToString("N"));
        Directory.CreateDirectory(dir);
        try
        {
            File.WriteAllText(Path.Combine(dir, "compile-native.vire"), "define main\n  while true\n  end\nend\n");
            Assert.Equal(1000000, Program.BudgetFor(Path.Combine(dir, "compile-native.vire")));
        }
        finally
        {
            try { Directory.Delete(dir, true); } catch (IOException) { }
        }
    }
}
