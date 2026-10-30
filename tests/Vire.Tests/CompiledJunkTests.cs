using System;
using System.Collections.Generic;
using System.IO;
using Xunit;

public class CompiledJunkTests
{
    [Fact]
    public void LoaderRejectsBadOpcodeOperandJumpAndUnderflow()
    {
        VireError badOp = Assert.Throws<VireError>(() => Check(MainFunc(Step(1, Num(1)))));
        Assert.Contains("bad compiled opcode type", badOp.Message);

        VireError unknown = Assert.Throws<VireError>(() => Check(MainFunc(Step("xyzzy", Num(1)))));
        Assert.Contains("unknown compiled step", unknown.Message);

        VireError underflow = Assert.Throws<VireError>(() => Check(MainFunc(new List<object> { "let" })));
        Assert.Contains("compiled stack underflow", underflow.Message);

        VireError operand = Assert.Throws<VireError>(() => Check(MainFunc(new List<object> { "let", 9, Num(1) })));
        Assert.Contains("bad compiled operand type", operand.Message);

        VireError jump = Assert.Throws<VireError>(() => Check(MainFunc(new List<object> { "jump", 99, 1, 1 })));
        Assert.Contains("compiled jump is out of range", jump.Message);
    }

    [Fact]
    public void ExecutionRejectsJunkWithoutThrowingClrExceptions()
    {
        Budget budget = Fresh();
        VireError underflow = Assert.Throws<VireError>(() =>
        {
            CompiledMachine machine = new CompiledMachine(Raw(MainFunc(new List<object> { "let" })), ".", new List<object>(), budget);
            machine.Call("main", new List<object>());
        });
        Assert.Contains("compiled stack underflow", underflow.Message);

        VireError jump = Assert.Throws<VireError>(() =>
        {
            CompiledMachine machine = new CompiledMachine(Raw(MainFunc(new List<object> { "jump", 99 })), ".", new List<object>(), Fresh());
            machine.Call("main", new List<object>());
        });
        Assert.Contains("compiled jump is out of range", jump.Message);

        VireError opcode = Assert.Throws<VireError>(() =>
        {
            CompiledMachine machine = new CompiledMachine(Raw(MainFunc(Step(false, Num(1)))), ".", new List<object>(), Fresh());
            machine.Call("main", new List<object>());
        });
        Assert.Contains("bad compiled opcode type", opcode.Message);
    }

    [Fact]
    public void SealedJunkVcIsRejectedCleanly()
    {
        string previous = Environment.GetEnvironmentVariable("VIRE_SEAL_KEY");
        Environment.SetEnvironmentVariable("VIRE_SEAL_KEY", DualMode.TestKeyB64());
        VireSeal.LoadFromEnvironment();
        string dir = Path.Combine(Path.GetTempPath(), "vire-junk-" + Guid.NewGuid().ToString("N"));
        Directory.CreateDirectory(dir);
        try
        {
            Dictionary<string, object> root = new Dictionary<string, object>();
            List<object> funcs = new List<object>();
            funcs.Add(Func("main", new List<object>(), new List<object> { new List<object> { "jump", 8 } }));
            root["funcs"] = funcs;
            byte[] packed = VireSeal.SealBytes(System.Text.Encoding.UTF8.GetBytes(Json.Write(root)));
            string vc = Path.Combine(dir, "junk.vc");
            File.WriteAllBytes(vc, packed);
            VireError err = Assert.Throws<VireError>(() => CompiledProgram.Run(vc, dir, new List<object>()));
            Assert.Contains("compiled jump is out of range", err.Message);
        }
        finally
        {
            VireSeal.ClearKey();
            Environment.SetEnvironmentVariable("VIRE_SEAL_KEY", previous);
            try { Directory.Delete(dir, true); } catch (IOException) { }
        }
    }

    [Fact]
    public void SeededFuzzNeverThrowsClrExceptions()
    {
        Random rng = new Random(20261030);
        int cases = 0;
        for (int i = 0; i < 250; i++)
        {
            Dictionary<string, object> funcs = Raw(MainFunc(RandomStep(rng, 0)));
            try
            {
                CompiledCheck.Program(funcs);
            }
            catch (VireError)
            {
                cases++;
                continue;
            }
            try
            {
                CompiledMachine machine = new CompiledMachine(funcs, ".", new List<object>(), Fresh());
                machine.Call("main", new List<object>());
            }
            catch (VireError)
            {
                cases++;
            }
            cases++;
        }
        Assert.True(cases >= 250);
    }

    static void Check(Dictionary<string, object> func)
    {
        CompiledCheck.Program(Raw(func));
    }

    static Dictionary<string, object> Raw(Dictionary<string, object> func)
    {
        Dictionary<string, object> table = new Dictionary<string, object>();
        table[(string)func["name"]] = func;
        return table;
    }

    static Dictionary<string, object> Func(string name, List<object> parameters, List<object> body)
    {
        Dictionary<string, object> func = new Dictionary<string, object>();
        func["name"] = name;
        func["params"] = parameters;
        func["body"] = body;
        return func;
    }

    static Dictionary<string, object> MainFunc(List<object> step)
    {
        return Func("main", new List<object>(), new List<object> { step });
    }

    static List<object> Step(object op, List<object> expr)
    {
        return new List<object> { op, expr };
    }

    static List<object> Num(int value)
    {
        return new List<object> { "num", value, 1, 1 };
    }

    static List<object> RandomStep(Random rng, int depth)
    {
        if (depth > 4) return new List<object> { "say", Num(1), 1, 1 };
        int pick = rng.Next(0, 10);
        if (pick == 0) return new List<object> { rng.Next(0, 5) == 0 ? (object)rng.Next(0, 50) : "xyzzy" };
        if (pick == 1) return new List<object> { "let" };
        if (pick == 2) return new List<object> { "let", rng.Next(0, 2) == 0 ? (object)"n" : 3, RandomExpr(rng, depth) };
        if (pick == 3) return new List<object> { "jump", rng.Next(-4, 40) };
        if (pick == 4) return new List<object> { "goto", rng.Next(0, 8) };
        if (pick == 5) return new List<object> { "say", RandomExpr(rng, depth) };
        if (pick == 6) return new List<object> { "if", RandomExpr(rng, depth), "nope" };
        if (pick == 7) return new List<object> { "call", rng.Next(0, 2) == 0 ? (object)"length" : 1, new List<object>() };
        if (pick == 8) return new List<object> { "while", RandomExpr(rng, depth), new List<object> { RandomStep(rng, depth + 1) } };
        return new List<object> { "say", Num(1), 1, 1 };
    }

    static List<object> RandomExpr(Random rng, int depth)
    {
        if (depth > 3) return Num(rng.Next(-3, 4));
        int pick = rng.Next(0, 6);
        if (pick == 0) return new List<object> { "+" };
        if (pick == 1) return new List<object> { 9, Num(1) };
        if (pick == 2) return new List<object> { "call", "length", new List<object>() };
        if (pick == 3) return new List<object> { "/", Num(1), Num(0) };
        if (pick == 4) return new List<object> { "at", new List<object> { "list", new List<object>() }, Num(9) };
        return Num(rng.Next(0, 3));
    }

    static Budget Fresh()
    {
        Budget budget = new Budget();
        budget.ApplyStepLimit(2000);
        return budget;
    }
}
