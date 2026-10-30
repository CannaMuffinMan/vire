using System;
using System.Collections.Generic;
using System.IO;
using Xunit;

public class CrashTests
{
    [Fact]
    public void CrashFixturesStayAlive()
    {
        DualMode.DualRun cycle = DualFile("cycle-say.vire", null, null);
        Alive(cycle, 0);
        Assert.Contains("[...]", DualMode.Norm(cycle.InterpOut));

        DualMode.DualRun json = DualFile("cycle-json.vire", null, null);
        Alive(json, 1);
        Assert.Contains("json can't write a list or map that contains itself", json.InterpErr);

        DualMode.DualRun deep = DualMode.RunSource(
            "define main\n  parse with \"" + new string('[', 100000) + new string(']', 100000) + "\"\n  say \"lived\"\nend\n",
            null);
        Alive(deep, 1);
        Assert.Contains("json is nested too deeply", deep.InterpErr);

        DualMode.DualRun arith = DualFile("arith.vire", null, null);
        Alive(arith, 0);
        Assert.Equal("0\n2147483648\n2147483648\n2147483648\n", DualMode.Norm(arith.InterpOut));

        DualMode.DualRun self = DualFile("self-run.vire", null, null);
        Alive(self, 1);
        Assert.Contains("run went too deep", self.InterpErr);

        DualMode.DualRun nested = DualFile("nest-run.vire", new string[] { "burn.vire" }, "50");
        Alive(nested, 1);
        Assert.Contains("program ran too long", nested.InterpErr);
        Assert.DoesNotContain("parent", nested.InterpOut);

        DualMode.DualRun wide = DualMode.RunSource(
            "define main\n  say " + new string('(', 5) + "1" + new string(')', 5) + "\nend\n", null);
        Alive(wide, 0);
        Assert.Contains("1", wide.InterpOut);

        DualMode.DualRun tooWide = DualMode.RunSource(
            "define main\n  say " + new string('(', 10000) + "1" + new string(')', 10000) + "\nend\n", null);
        Assert.True(tooWide.InterpCode == 1 || tooWide.InterpCode == 0);
        Assert.True(tooWide.CompCode == 1 || tooWide.CompCode == 0);
        Assert.NotEqual(3, tooWide.InterpCode);
        Assert.NotEqual(3, tooWide.CompCode);
        Assert.True(
            tooWide.InterpErr.Contains("expression is too deep") || tooWide.CompErr.Contains("expression is too deep") || tooWide.Matched,
            tooWide.InterpErr + tooWide.CompErr);

        DualMode.DualRun overflow = DualFile("overflow.vire", null, null);
        Alive(overflow, 0);
        Assert.Equal("4294967294\n", DualMode.Norm(overflow.InterpOut));

        DualMode.DualRun zero = DualFile("zero-div.vire", null, null);
        Alive(zero, 1);
        Assert.Contains("division by zero", zero.InterpErr);

        DualMode.DualRun badJson = DualFile("bad-json.vire", null, null);
        Alive(badJson, 1);
        Assert.Contains("json", badJson.InterpErr);

        DualMode.DualRun huge = DualMode.RunSource(
            "define main\n  say " + new string('9', 400) + "\nend\n", null);
        Assert.NotEqual(3, huge.InterpCode);
        Assert.NotEqual(3, huge.CompCode);
        Assert.Equal(1, huge.InterpCode);
        Assert.Equal(1, huge.CompCode);
        Assert.True(
            huge.InterpErr.Contains("too large") || huge.InterpErr.Contains("json"),
            huge.InterpErr);
        Assert.True(
            huge.CompErr.Contains("too large") || huge.CompErr.Contains("json") || huge.CompErr.Contains("number"),
            huge.CompErr);
    }

    [Fact]
    public void WhilePassLimitFollowsStepBudget()
    {
        DualMode.DualRun result = DualMode.RunSource(
            "define main\n  let n be 0\n  while n < 120000\n    let n be n + 1\n  end\n  say \"ok\"\nend\n",
            null,
            "5000000");
        Alive(result, 0);
        Assert.Contains("ok", result.InterpOut);
        Assert.DoesNotContain("while ran too long", result.InterpErr);
    }

    [Fact]
    public void RunawayWhileIsStillStopped()
    {
        DualMode.DualRun result = DualMode.RunSource(
            "define main\n  while 1\n  end\n  say \"escaped\"\nend\n",
            null,
            "200");
        Alive(result, 1);
        Assert.True(
            result.InterpErr.Contains("while ran too long") || result.InterpErr.Contains("program ran too long"),
            result.InterpErr);
        Assert.DoesNotContain("escaped", result.InterpOut);
    }

    [Fact]
    public void CompiledWhilePassLimitFollowsStepBudget()
    {
        Dictionary<string, object> many = Func("main", new List<object>(), new List<object>
        {
            Let("n", Num(0)),
            While(Lt(Name("n"), Num(120000)), new List<object>
            {
                Let("n", Plus(Name("n"), Num(1)))
            }),
            Say(Text("ok"))
        });
        Budget raised = new Budget();
        raised.ApplyStepLimit(5000000);
        string output = Capture(() =>
        {
            CompiledMachine machine = new CompiledMachine(Funcs(many), ".", new List<object>(), raised);
            machine.Call("main", new List<object>());
        });
        Assert.Contains("ok", output);

        Dictionary<string, object> runaway = Func("main", new List<object>(), new List<object>
        {
            While(Num(1), new List<object>()),
            Say(Text("escaped"))
        });
        Budget tight = new Budget();
        tight.ApplyStepLimit(200);
        VireError error = Assert.Throws<VireError>(() =>
        {
            CompiledMachine machine = new CompiledMachine(Funcs(runaway), ".", new List<object>(), tight);
            machine.Call("main", new List<object>());
        });
        Assert.True(error.Message == "while ran too long" || error.Message == "program ran too long and was stopped", error.Message);
    }

    static Dictionary<string, object> Funcs(params Dictionary<string, object>[] funcs)
    {
        Dictionary<string, object> table = new Dictionary<string, object>();
        foreach (Dictionary<string, object> func in funcs)
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

    static List<object> Let(string name, List<object> expr)
    {
        return new List<object> { "let", name, expr };
    }

    static List<object> Say(List<object> expr)
    {
        return new List<object> { "say", expr };
    }

    static List<object> While(List<object> test, List<object> body)
    {
        return new List<object> { "while", test, body };
    }

    static List<object> Num(int value)
    {
        return new List<object> { "num", value };
    }

    static List<object> Text(string value)
    {
        return new List<object> { "text", value };
    }

    static List<object> Name(string value)
    {
        return new List<object> { "name", value };
    }

    static List<object> Plus(List<object> left, List<object> right)
    {
        return new List<object> { "+", left, right };
    }

    static List<object> Lt(List<object> left, List<object> right)
    {
        return new List<object> { "<", left, right };
    }

    static string Capture(Action action)
    {
        System.IO.TextWriter previous = Console.Out;
        System.IO.StringWriter sink = new System.IO.StringWriter();
        Console.SetOut(sink);
        try
        {
            action();
            return sink.ToString();
        }
        finally
        {
            Console.SetOut(previous);
        }
    }

    [Fact]
    public void JsonAndShowRefuseAdversarialValuesInProcess()
    {
        List<object> cycle = new List<object>();
        cycle.Add(cycle);
        Assert.Contains("[...]", Machine.Show(cycle));
        VireError loop = Assert.Throws<VireError>(() => Json.Write(cycle));
        Assert.Contains("contains itself", loop.Message);

        string escaped = Json.Write("a\b\f\n\r\t\"\\" + ((char)1).ToString() + "\uD800");
        Assert.Contains("\\b", escaped);
        Assert.Contains("\\f", escaped);
        Assert.Contains("\\n", escaped);
        Assert.Contains("\\r", escaped);
        Assert.Contains("\\t", escaped);
        Assert.Contains("\\u0001", escaped);
        Assert.Contains("\\ud800", escaped);

        VireError nan = Assert.Throws<VireError>(() => Json.Write(double.NaN));
        Assert.Contains("json can't write that number", nan.Message);
        Assert.Throws<VireError>(() => Json.Write(double.PositiveInfinity));

        VireError deep = Assert.Throws<VireError>(() => Json.Read(new string('[', 300) + new string(']', 300), 1));
        Assert.Contains("nested too deeply", deep.Message);

        VireError huge = Assert.Throws<VireError>(() => Json.Read("1e400", 1));
        Assert.Contains("bad number", huge.Message);

        VireError esc = Assert.Throws<VireError>(() => Json.Read("\"\\uZZZZ\"", 1));
        Assert.Contains("bad escape", esc.Message);

        VireError extra = Assert.Throws<VireError>(() => Json.Read("true true", 1));
        Assert.Contains("extra", extra.Message);
    }

    static DualMode.DualRun DualFile(string name, string[] extra, string budget)
    {
        string root = DualMode.FindRoot();
        string crash = Path.Combine(root, "tests", "crash");
        string work = Path.Combine(root, "data", "conformance", Guid.NewGuid().ToString("N"));
        Directory.CreateDirectory(work);
        Directory.CreateDirectory(Path.Combine(work, "data"));
        File.Copy(Path.Combine(crash, name), Path.Combine(work, name), true);
        if (extra != null)
        {
            foreach (string item in extra)
                File.Copy(Path.Combine(crash, item), Path.Combine(work, item), true);
        }
        return DualMode.CompareFile(root, Path.Combine(work, name), work, budget);
    }

    static void Alive(DualMode.DualRun both, int code)
    {
        Assert.NotEqual(3, both.InterpCode);
        Assert.NotEqual(3, both.CompCode);
        Assert.True(both.Matched, "crash fixture interpreter vs compiled differed\n i out " + both.InterpOut + "\n c out " + both.CompOut + "\n i err " + both.InterpErr + "\n c err " + both.CompErr);
        Assert.Equal(code, both.InterpCode);
        Assert.Equal(code, both.CompCode);
    }
}
