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
            Assert.Equal(Program.CompilerStepCap, Program.BudgetFor(Path.Combine(dir, "compile-native.vire"), true));
        }
        finally
        {
            try { Directory.Delete(dir, true); } catch (IOException) { }
        }
    }

    [Fact]
    public void GuestNamedCompilerVireDoesNotGetCompilerCap()
    {
        string dir = Path.Combine(Path.GetTempPath(), "vire-compiler-claim-" + Guid.NewGuid().ToString("N"));
        Directory.CreateDirectory(dir);
        string previous = Environment.GetEnvironmentVariable("VIRE_BUDGET");
        try
        {
            string body = "define main\n  let n be 0\n  while n < 100\n    let n be n + 1\n  end\n  say \"emitU8\"\nend\n";
            File.WriteAllText(Path.Combine(dir, "hello.vire"), body);
            File.WriteAllText(Path.Combine(dir, "compiler.vire"), body);
            Environment.SetEnvironmentVariable("VIRE_BUDGET", "10");
            string cwd = Directory.GetCurrentDirectory();
            Directory.SetCurrentDirectory(dir);
            try
            {
                int hello = Program.Execute(new string[] { "hello.vire" });
                int guest = Program.Execute(new string[] { "compiler.vire" });
                int flagged = Program.Execute(new string[] { "--compiler", "compiler.vire" });
                Console.WriteLine("compiler_claim_pass_after hello=" + hello + " guest=" + guest + " flagged=" + flagged);
                Assert.Equal(1, hello);
                Assert.Equal(1, guest);
                Assert.Equal(1, flagged);
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
    public void FrozenHeadIsCompilerProgramSniffsFilename()
    {
        string root = DualMode.FindRoot();
        var info = new System.Diagnostics.ProcessStartInfo
        {
            FileName = "git",
            WorkingDirectory = root,
            RedirectStandardOutput = true,
            UseShellExecute = false
        };
        info.ArgumentList.Add("show");
        info.ArgumentList.Add("dee819a7f0a256c70faa042b048fb4f8e542ab44:Vire.cs");
        System.Diagnostics.Process p = System.Diagnostics.Process.Start(info);
        string old = p.StandardOutput.ReadToEnd();
        p.WaitForExit(15000);
        string now = File.ReadAllText(Path.Combine(root, "Vire.cs"));
        Assert.DoesNotContain("static bool IsCompilerProgram", now);
        Assert.Contains("\"--compiler\"", now);
        if (p.ExitCode == 0 && old.Length > 0)
        {
            Assert.Contains("static bool IsCompilerProgram", old);
            Assert.Contains("text.Contains(\"emitU8\")", old);
            Console.WriteLine("compiler_claim_fail_before dee819a IsCompilerProgram=true");
        }
        Console.WriteLine("compiler_claim_pass_after --compiler host flag");
    }
}
