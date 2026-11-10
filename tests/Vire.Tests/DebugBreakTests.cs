using System;
using System.IO;
using System.Text;
using Xunit;

public class DebugBreakTests
{
    [Fact]
    public void BreakStopsOnlyNamedFunctionsInsideDataWhenDebuggerOn()
    {
        string dir = Path.Combine(Path.GetTempPath(), "vire-break-" + Guid.NewGuid().ToString("N"));
        Directory.CreateDirectory(dir);
        string data = Path.Combine(dir, "data");
        Directory.CreateDirectory(data);
        string outside = Path.Combine(dir, "inspect.txt");
        string prior = Environment.GetEnvironmentVariable("VIRE_DEBUGGER");
        try
        {
            Environment.SetEnvironmentVariable("VIRE_DEBUGGER", "1");
            Assert.False(VireDebug.Break(dir, "main", 4, "absent"));
            Assert.False(File.Exists(Path.Combine(data, "inspect.txt")));
            Assert.False(File.Exists(outside));

            File.WriteAllText(Path.Combine(data, "break.txt"), "other\nmain\n");
            Assert.False(VireDebug.Break(dir, "nope", 2, "miss"));
            Assert.False(File.Exists(Path.Combine(data, "inspect.txt")));

            Assert.True(VireDebug.Break(dir, "main", 9, "here"));
            string inspect = Path.Combine(data, "inspect.txt");
            Assert.Equal("stop main line 9 here\n", File.ReadAllText(inspect));
            Assert.StartsWith(Path.GetFullPath(data) + Path.DirectorySeparatorChar, Path.GetFullPath(inspect));
            Assert.False(File.Exists(outside));

            StringBuilder many = new StringBuilder();
            for (int i = 0; i < 100; i++) many.Append("old ").Append(i).Append('\n');
            File.WriteAllText(inspect, many.ToString());
            Assert.True(VireDebug.Break(dir, "main", 10, "capped"));
            Assert.Equal(100, File.ReadAllLines(inspect).Length);
            Assert.DoesNotContain("capped", File.ReadAllText(inspect));
        }
        finally
        {
            Environment.SetEnvironmentVariable("VIRE_DEBUGGER", prior);
            try { Directory.Delete(dir, true); } catch (IOException) { }
        }
    }

    [Fact]
    public void BreakDoesNotProbeBreakFileWhenDebuggerUnset()
    {
        string dir = Path.Combine(Path.GetTempPath(), "vire-break-off-" + Guid.NewGuid().ToString("N"));
        Directory.CreateDirectory(dir);
        string data = Path.Combine(dir, "data");
        Directory.CreateDirectory(data);
        File.WriteAllText(Path.Combine(data, "break.txt"), "main\n");
        string prior = Environment.GetEnvironmentVariable("VIRE_DEBUGGER");
        long before = System.Threading.Interlocked.Read(ref VireDebug.ProbeCalls);
        try
        {
            Environment.SetEnvironmentVariable("VIRE_DEBUGGER", null);
            Assert.False(VireDebug.Break(dir, "main", 9, "here"));
            Assert.False(File.Exists(Path.Combine(data, "inspect.txt")));
            Assert.Equal("main\n", File.ReadAllText(Path.Combine(data, "break.txt")));
            Assert.Equal(before, System.Threading.Interlocked.Read(ref VireDebug.ProbeCalls));
        }
        finally
        {
            Environment.SetEnvironmentVariable("VIRE_DEBUGGER", prior);
            try { Directory.Delete(dir, true); } catch (IOException) { }
        }
    }
}
