using System;
using System.IO;
using Xunit;

public class ThreadTests
{
    [Fact]
    public void WorkerResultIsPrintedAfterWait()
    {
        string src = string.Join("\n", new string[]
        {
            "define worker with n",
            "  return n + 1",
            "end",
            "define other",
            "  return 3",
            "end",
            "define main",
            "  let left be start with \"worker\", 6",
            "  let right be start with \"other\"",
            "  wait with left",
            "  wait with right",
            "  say result with left",
            "  say result with right",
            "end",
            ""
        });
        string dir = Path.Combine(Path.GetTempPath(), "vire-thread-" + Guid.NewGuid().ToString("N"));
        Directory.CreateDirectory(dir);
        try
        {
            File.WriteAllText(Path.Combine(dir, "work.vire"), src);
            string text = Run(dir, "work.vire", out int code);
            Assert.Equal(0, code);
            Assert.Equal("7\n3", text.Trim().Replace("\r", ""));
        }
        finally
        {
            try { Directory.Delete(dir, true); } catch (IOException) { }
        }
    }

    [Fact]
    public void ResultBeforeWaitFails()
    {
        string src = string.Join("\n", new string[]
        {
            "define worker",
            "  return 1",
            "end",
            "define main",
            "  let t be start with \"worker\"",
            "  say result with t",
            "end",
            ""
        });
        string dir = Path.Combine(Path.GetTempPath(), "vire-thread-" + Guid.NewGuid().ToString("N"));
        Directory.CreateDirectory(dir);
        try
        {
            File.WriteAllText(Path.Combine(dir, "early.vire"), src);
            string err = Run(dir, "early.vire", out int code);
            Assert.NotEqual(0, code);
            Assert.Contains("join before reading the thread", err);
        }
        finally
        {
            try { Directory.Delete(dir, true); } catch (IOException) { }
        }
    }

    [Fact]
    public void EndlessWorkerStopsAtItsOwnStepBudget()
    {
        string src = string.Join("\n", new string[]
        {
            "define worker",
            "  while true",
            "  end",
            "  return 1",
            "end",
            "define main",
            "  let t be start with \"worker\"",
            "  wait with t",
            "  say result with t",
            "end",
            ""
        });
        string dir = Path.Combine(Path.GetTempPath(), "vire-thread-" + Guid.NewGuid().ToString("N"));
        Directory.CreateDirectory(dir);
        string previous = Environment.GetEnvironmentVariable("VIRE_BUDGET");
        try
        {
            File.WriteAllText(Path.Combine(dir, "spin.vire"), src);
            Environment.SetEnvironmentVariable("VIRE_BUDGET", "1000");
            string err = Run(dir, "spin.vire", out int code);
            Assert.NotEqual(0, code);
            Assert.Contains("too long", err);
        }
        finally
        {
            Environment.SetEnvironmentVariable("VIRE_BUDGET", previous);
            try { Directory.Delete(dir, true); } catch (IOException) { }
        }
    }

    static string Run(string dir, string file, out int code)
    {
        TextWriter previousOut = Console.Out;
        TextWriter previousErr = Console.Error;
        StringWriter sink = new StringWriter();
        StringWriter err = new StringWriter();
        string cwd = Directory.GetCurrentDirectory();
        try
        {
            Console.SetOut(sink);
            Console.SetError(err);
            Directory.SetCurrentDirectory(dir);
            code = Program.Execute(new string[] { file });
        }
        finally
        {
            Directory.SetCurrentDirectory(cwd);
            Console.SetOut(previousOut);
            Console.SetError(previousErr);
        }
        string text = sink.ToString();
        if (text.Trim().Length == 0) text = err.ToString();
        return text;
    }
}
