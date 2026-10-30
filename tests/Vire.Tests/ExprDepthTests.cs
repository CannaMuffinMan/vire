using System;
using System.Collections.Generic;
using Xunit;

public class ExprDepthTests
{
    [Fact]
    public void NestedExpressionDepthResetsEachEvaluation()
    {
        List<object> expr = Num(1);
        for (int i = 0; i < 62; i++)
            expr = Plus(expr, Num(0));
        Dictionary<string, object> main = Func("main", new List<object>(), new List<object>
        {
            Let("n", Num(0)),
            While(Lt(Name("n"), Num(10000)), new List<object>
            {
                Let("x", expr),
                Let("n", Plus(Name("n"), Num(1)))
            }),
            Say(Text("ok"))
        });
        string output = Capture(() =>
        {
            CompiledMachine machine = new CompiledMachine(Funcs(main), ".", new List<object>(), FreshBudget());
            machine.Call("main", new List<object>());
        });
        Assert.Contains("ok", output);
    }

    [Fact]
    public void ExpressionNested257DeepIsRefused()
    {
        List<object> expr = Num(1);
        for (int i = 0; i < 256; i++)
            expr = Plus(expr, Num(0));
        Dictionary<string, object> main = Func("main", new List<object>(), new List<object>
        {
            Say(expr)
        });
        VireError error = Assert.Throws<VireError>(() =>
        {
            CompiledMachine machine = new CompiledMachine(Funcs(main), ".", new List<object>(), FreshBudget());
            machine.Call("main", new List<object>());
        });
        Assert.Equal("expression is too deep", error.Message);
    }

    static Budget FreshBudget()
    {
        Budget budget = new Budget();
        budget.ApplyStepLimit(5000000);
        return budget;
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
}
