using System;
using System.Collections.Generic;
using System.IO;
using Xunit;

public class ForeignTests
{
    [Fact]
    public void ForeignCallsNoArgExportInsideProgramFolder()
    {
        string dir = Path.Combine(Path.GetTempPath(), "vire-foreign-" + Guid.NewGuid().ToString("N"));
        Directory.CreateDirectory(dir);
        try
        {
            if (!OperatingSystem.IsWindows())
            {
                File.WriteAllBytes(Path.Combine(dir, "kernel32.dll"), new byte[] { 0x4D, 0x5A });
                string linuxSrc = "define main\n  return (foreign with \"kernel32.dll\", \"GetTickCount\")\nend\n";
                File.WriteAllText(Path.Combine(dir, "prog.vire"), linuxSrc);
                Dictionary<string, Func> linuxFuncs = Program.Load(Path.Combine(dir, "prog.vire"), dir, new HashSet<string>());
                Machine linuxMachine = new Machine(linuxFuncs, dir);
                VireError opened = Assert.Throws<VireError>(() => linuxMachine.Call("main", new List<object>(), 1, 1));
                Assert.Contains("could not open that dll", opened.Message);
                VireError linuxRooted = Assert.Throws<VireError>(() => linuxMachine.Call("foreign", new List<object> { "C:/Windows/System32/kernel32.dll", "GetTickCount" }, 1, 1));
                Assert.Contains("program folder", linuxRooted.Message);
                return;
            }
            File.Copy(Path.Combine(Environment.SystemDirectory, "kernel32.dll"), Path.Combine(dir, "kernel32.dll"));
            string src = string.Join("\n", new string[]
            {
                "define main",
                "  return (foreign with \"kernel32.dll\", \"GetTickCount\")",
                "end",
                ""
            });
            string path = Path.Combine(dir, "prog.vire");
            File.WriteAllText(path, src);
            Dictionary<string, Func> funcs = Program.Load(path, dir, new HashSet<string>());
            Machine machine = new Machine(funcs, dir);
            int before = Environment.TickCount;
            object got = machine.Call("main", new List<object>(), 1, 1);
            int after = Environment.TickCount;
            Assert.IsType<int>(got);
            int tick = (int)got;
            Assert.InRange(tick, before, after + 1000);

            VireError rooted = Assert.Throws<VireError>(() => machine.Call("foreign", new List<object> { "C:/Windows/System32/kernel32.dll", "GetTickCount" }, 1, 1));
            Assert.Contains("program folder", rooted.Message);
            VireError parent = Assert.Throws<VireError>(() => machine.Call("foreign", new List<object> { "../kernel32.dll", "GetTickCount" }, 1, 1));
            Assert.Contains("program folder", parent.Message);
            VireError site = Assert.Throws<VireError>(() => machine.Call("foreign", new List<object> { "data/kernel32.dll", "GetTickCount" }, 1, 1));
            Assert.Contains("data and site", site.Message);
            VireError missing = Assert.Throws<VireError>(() => machine.Call("foreign", new List<object> { "missing.dll", "GetTickCount" }, 1, 1));
            Assert.Contains("no file", missing.Message);
            VireError export = Assert.Throws<VireError>(() => machine.Call("foreign", new List<object> { "kernel32.dll", "NoSuchExport" }, 1, 1));
            Assert.Contains("no export", export.Message);
            VireError address = Assert.Throws<VireError>(() => machine.Call("foreign", new List<object> { "kernel32.dll", "0x401000" }, 1, 1));
            Assert.Contains("export name", address.Message);

            Budget budget = new Budget();
            CompiledMachine compiled = new CompiledMachine(new Dictionary<string, object>(), dir, new List<object>(), budget);
            object compiledTick = compiled.Call("foreign", new List<object> { "kernel32.dll", "GetTickCount" }, 1, 1);
            Assert.IsType<int>(compiledTick);
        }
        finally
        {
            try { Directory.Delete(dir, true); } catch (IOException) { } catch (UnauthorizedAccessException) { }
        }
    }
}
