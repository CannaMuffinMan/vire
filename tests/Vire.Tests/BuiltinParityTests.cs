using System;
using System.Collections.Generic;
using System.IO;
using System.Net.Http;
using System.Threading;
using Xunit;

public class BuiltinParityTests
{
    [Fact]
    public void AskReadsStdinInBothMachines()
    {
        string src = "define main\n  say (ask with \"n?\")\nend\n";
        TextReader previousIn = Console.In;
        TextWriter previousOut = Console.Out;
        try
        {
            Console.SetIn(new StringReader("ok\n"));
            Console.SetOut(new StringWriter());
            Machine interp = Load(src);
            object got = interp.Call("main", new List<object>(), 1);
            Assert.Null(got);
        }
        finally
        {
            Console.SetIn(previousIn);
            Console.SetOut(previousOut);
        }

        DualMode.DualRun both = DualMode.RunSource(
            "define main\n  say (span with 2, 4)\n  say (sort with [9, 1])\nend\n", null);
        Assert.True(both.Matched, both.InterpOut + both.CompOut + both.InterpErr + both.CompErr);
        Assert.Equal(0, both.InterpCode);
        Assert.Contains("[2, 3, 4]", DualMode.Norm(both.InterpOut));
        Assert.Contains("[1, 9]", DualMode.Norm(both.InterpOut));
    }

    [Fact]
    public void TermWindowShowClosesOnZeroInBothModes()
    {
        string src = string.Join("\n", new string[]
        {
            "define tapped",
            "  say \"hit\"",
            "end",
            "define main",
            "  open with \"box\"",
            "  line with \"hello\"",
            "  field with \"name\"",
            "  button with \"go\", \"tapped\"",
            "  place with 2, 3",
            "  show",
            "  say (screen)",
            "end",
            ""
        });
        TextReader previousIn = Console.In;
        TextWriter previousOut = Console.Out;
        StringWriter sink = new StringWriter();
        try
        {
            Console.SetIn(new StringReader("Ada\n0\n"));
            Console.SetOut(sink);
            Machine machine = Load(src);
            machine.Call("main", new List<object>(), 1);
        }
        finally
        {
            Console.SetIn(previousIn);
            Console.SetOut(previousOut);
        }
        string text = sink.ToString();
        Assert.Contains("box", text);
        Assert.Contains("hello", text);

        CompiledMachine compiled = FromSource(src);
        sink = new StringWriter();
        try
        {
            Console.SetIn(new StringReader("Ada\n0\n"));
            Console.SetOut(sink);
            compiled.Call("main", new List<object>(), 1, 1);
        }
        finally
        {
            Console.SetIn(previousIn);
            Console.SetOut(previousOut);
        }
        Assert.Contains("box", sink.ToString());
        Assert.Contains("hello", sink.ToString());
    }

    [Fact]
    public void CompiledListenServesRoute()
    {
        string src = string.Join("\n", new string[]
        {
            "define route with method, path, body",
            "  return \"{\\\"ok\\\":true}\"",
            "end",
            "define main",
            "  listen with 0",
            "end",
            ""
        });
        string dir = Path.Combine(Path.GetTempPath(), "vire-clisten-" + Guid.NewGuid().ToString("N"));
        Directory.CreateDirectory(dir);
        string path = Path.Combine(dir, "listen.vire");
        File.WriteAllText(path, src);
        Dictionary<string, Func> interpFuncs = Program.Load(path, dir, new HashSet<string>());
        Machine interp = new Machine(interpFuncs, dir);
        interp.UseBudget(500000);
        CancellationTokenSource cts = new CancellationTokenSource();
        Thread thread = new Thread(() => interp.ListenCore(0, 1, cts.Token));
        thread.IsBackground = true;
        thread.Start();
        DateTime until = DateTime.UtcNow.AddSeconds(5);
        while (interp.ListenPort == 0 && DateTime.UtcNow < until) Thread.Sleep(10);
        Assert.InRange(interp.ListenPort, 1024, 65535);
        cts.Cancel();
        thread.Join(4000);

        CompiledMachine compiled = FromSource(src);
        CancellationTokenSource cts2 = new CancellationTokenSource();
        Thread thread2 = new Thread(() => compiled.ListenCore(0, 1, cts2.Token));
        thread2.IsBackground = true;
        thread2.Start();
        until = DateTime.UtcNow.AddSeconds(5);
        while (compiled.ListenPort == 0 && DateTime.UtcNow < until) Thread.Sleep(10);
        int port = compiled.ListenPort;
        PortGuard.AssertAllowedPort(port);
        try
        {
            using (HttpClient client = new HttpClient())
            {
                client.Timeout = TimeSpan.FromSeconds(5);
                HttpResponseMessage res = client.GetAsync("http://127.0.0.1:" + port + "/").Result;
                Assert.Equal(200, (int)res.StatusCode);
                Assert.Contains("ok", res.Content.ReadAsStringAsync().Result);
            }
        }
        finally
        {
            cts2.Cancel();
            thread2.Join(4000);
            try { Directory.Delete(dir, true); } catch (IOException) { }
        }
    }

    static Machine Load(string source)
    {
        string dir = Path.Combine(Path.GetTempPath(), "vire-bp-" + Guid.NewGuid().ToString("N"));
        Directory.CreateDirectory(dir);
        string path = Path.Combine(dir, "prog.vire");
        File.WriteAllText(path, source);
        Dictionary<string, Func> funcs = Program.Load(path, dir, new HashSet<string>());
        Machine machine = new Machine(funcs, dir);
        machine.UseBudget(500000);
        return machine;
    }

    static CompiledMachine FromSource(string source)
    {
        string root = DualMode.FindRoot();
        string work = Path.Combine(root, "data", "conformance", Guid.NewGuid().ToString("N"));
        Directory.CreateDirectory(work);
        File.WriteAllText(Path.Combine(work, "prog.vire"), source);
        Environment.SetEnvironmentVariable("VIRE_SEAL_KEY", DualMode.TestKeyB64());
        VireSeal.LoadFromEnvironment();
        DualMode.Proc compile = DualMode.RunVire(root, new string[]
        {
            "compiler.vire",
            Path.Combine("data", "conformance", Path.GetFileName(work), "prog.vire").Replace('\\', '/'),
            Path.Combine("data", "conformance", Path.GetFileName(work), "prog.vc").Replace('\\', '/')
        }, root);
        Assert.Equal(0, compile.Code);
        string vc = Path.Combine(work, "prog.vc");
        byte[] packed = File.ReadAllBytes(vc);
        // Open via CompiledProgram would run main. Load funcs by executing Run in isolation:
        Dictionary<string, object> funcs = ReadFuncs(vc);
        Budget budget = new Budget();
        budget.ApplyStepLimit(500000);
        return new CompiledMachine(funcs, work, new List<object>(), budget);
    }

    static Dictionary<string, object> ReadFuncs(string file)
    {
        byte[] packed = File.ReadAllBytes(file);
        string text = System.Text.Encoding.UTF8.GetString(VireSeal.OpenBytes(packed));
        object tree = Json.Read(text, 1);
        Dictionary<string, object> root = (Dictionary<string, object>)tree;
        Dictionary<string, object> funcs = new Dictionary<string, object>();
        foreach (object item in (List<object>)root["funcs"])
        {
            Dictionary<string, object> func = (Dictionary<string, object>)item;
            funcs[(string)func["name"]] = func;
        }
        return funcs;
    }
}
