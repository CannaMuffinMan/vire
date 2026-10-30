using System;
using System.Collections.Generic;
using System.IO;
using Xunit;

public class SuiteTests
{
    [Fact]
    public void PortGuardRejectsReservedPortsAndBindsLoopback()
    {
        int[] banned = { 7099, 8778, 7071, 7072, 17841 };
        for (int i = 0; i < banned.Length; i++)
        {
            int port = banned[i];
            Assert.Throws<InvalidOperationException>(() => PortGuard.AssertAllowedPort(port));
        }
        int free = PortGuard.GetFreeLoopbackPort();
        PortGuard.AssertAllowedPort(free);
        Assert.InRange(free, 1, 65535);
    }

    [Fact]
    public void InterpreterSuitePasses()
    {
        string root = FindRoot();
        List<string> programs = new List<string>();
        programs.Add(Path.Combine(root, "tests.vire"));
        AddMains(programs, Path.Combine(root, "checks"));
        AddMains(programs, Path.Combine(root, "systems"));
        Assert.Contains(programs, path => path.EndsWith("tests.vire", StringComparison.OrdinalIgnoreCase));
        Assert.True(File.Exists(Path.Combine(root, "checks", "core.vire")));
        foreach (string program in programs)
        {
            string output = Run(program);
            string[] lines = output.Replace("\r\n", "\n").Split('\n');
            bool saw = false;
            foreach (string raw in lines)
            {
                string line = raw.Trim();
                if (line.Length == 0) continue;
                Assert.False(line.EndsWith(" fail", StringComparison.Ordinal), program + " printed: " + line);
                Assert.True(line == "pass" || line.EndsWith(" pass", StringComparison.Ordinal), program + " printed: " + line);
                saw = true;
            }
            Assert.True(saw, program + " printed nothing");
        }
    }

    static void AddMains(List<string> programs, string dir)
    {
        foreach (string path in Directory.GetFiles(dir, "*.vire"))
        {
            string text = File.ReadAllText(path);
            if (text.Contains("define main")) programs.Add(path);
        }
    }

    static string Run(string program)
    {
        TextWriter previous = Console.Out;
        StringWriter sink = new StringWriter();
        Console.SetOut(sink);
        try
        {
            int code = Program.Execute(new string[] { program });
            Assert.Equal(0, code);
            return sink.ToString();
        }
        finally
        {
            Console.SetOut(previous);
        }
    }

    static string FindRoot()
    {
        string dir = AppContext.BaseDirectory;
        for (int i = 0; i < 8; i++)
        {
            if (File.Exists(Path.Combine(dir, "tests.vire")) && File.Exists(Path.Combine(dir, "vire.csproj")))
                return dir;
            DirectoryInfo parent = Directory.GetParent(dir);
            if (parent == null) break;
            dir = parent.FullName;
        }
        throw new InvalidOperationException("could not find the vire repo root from " + AppContext.BaseDirectory);
    }
}
