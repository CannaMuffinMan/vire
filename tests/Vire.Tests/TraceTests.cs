using System;
using System.IO;
using Xunit;

public class TraceTests
{
    [Fact]
    public void TraceWritesCallLinesOnlyWhenEnabled()
    {
        string dir = Path.Combine(Path.GetTempPath(), "vire-trace-" + Guid.NewGuid().ToString("N"));
        Directory.CreateDirectory(dir);
        string program = Path.Combine(dir, "main.vire");
        File.WriteAllText(program, "define main\nend\n");
        string trace = Path.Combine(dir, "data", "trace.txt");
        string previous = Environment.GetEnvironmentVariable("VIRE_TRACE");
        TextWriter previousOut = Console.Out;
        TextWriter previousErr = Console.Error;
        try
        {
            Console.SetOut(new StringWriter());
            Console.SetError(new StringWriter());
            Environment.SetEnvironmentVariable("VIRE_TRACE", null);
            Assert.Equal(0, Program.Execute(new string[] { program }));
            Assert.False(File.Exists(trace));

            Environment.SetEnvironmentVariable("VIRE_TRACE", "1");
            Assert.Equal(0, Program.Execute(new string[] { program }));
            Assert.True(File.Exists(trace));
            string text = File.ReadAllText(trace);
            Assert.Contains("call main line 1", text);
            Assert.StartsWith(Path.GetFullPath(Path.Combine(dir, "data")) + Path.DirectorySeparatorChar, Path.GetFullPath(trace));
        }
        finally
        {
            Console.SetOut(previousOut);
            Console.SetError(previousErr);
            Environment.SetEnvironmentVariable("VIRE_TRACE", previous);
            try { Directory.Delete(dir, true); } catch (IOException) { }
        }
    }
}
