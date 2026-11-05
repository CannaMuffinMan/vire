using System;
using System.IO;
using System.Security.Cryptography;
using System.Text;
using System.Threading;
using Xunit;

public class DebugStepTests
{
    [Fact]
    public void PauseStepSetThenContinue()
    {
        string dir = Path.Combine(Path.GetTempPath(), "vire-debug-" + Guid.NewGuid().ToString("N"));
        Directory.CreateDirectory(dir);
        string data = Path.Combine(dir, "data");
        Directory.CreateDirectory(data);
        string secret = "00112233445566778899aabbccddeeff00112233445566778899aabbccddeeff";
        string program = Path.Combine(dir, "main.vire");
        File.WriteAllText(program,
            "define main\n" +
            "  let token be \"" + secret + "\"\n" +
            "  let n be 1\n" +
            "  let n be n + 10\n" +
            "  say n\n" +
            "end\n");
        File.WriteAllText(Path.Combine(data, "break.txt"), "main.vire:4\n");
        string previousDebug = Environment.GetEnvironmentVariable("VIRE_DEBUGGER");
        string previousTrace = Environment.GetEnvironmentVariable("VIRE_TRACE");
        TextWriter previousOut = Console.Out;
        TextWriter previousErr = Console.Error;
        StringWriter sink = new StringWriter();
        int code = -1;
        try
        {
            Console.SetOut(sink);
            Console.SetError(new StringWriter());
            Environment.SetEnvironmentVariable("VIRE_DEBUGGER", "1");
            Environment.SetEnvironmentVariable("VIRE_TRACE", "1");
            Thread worker = new Thread(delegate ()
            {
                code = Program.Execute(new string[] { program });
            });
            worker.IsBackground = true;
            worker.Start();
            string status = Path.Combine(data, "debug.txt");
            string trace = Path.Combine(data, "trace.txt");
            string paused = WaitFileContains(status, "paused main.vire:4", 15000);
            Assert.Contains("n=1", paused);
            Assert.DoesNotContain(secret, paused);
            Assert.Contains("token=len=64 sha256=" + Sha8(secret), paused);
            Post(data, "set n 7");
            paused = WaitFileContains(status, "n=7", 15000);
            Assert.Contains("paused main.vire:4", paused);
            Assert.DoesNotContain(secret, paused);
            Post(data, "step");
            paused = WaitFileContains(status, "paused main.vire:5", 15000);
            Assert.Contains("n=17", paused);
            Assert.DoesNotContain(secret, File.ReadAllText(trace));
            Assert.Contains("main.vire:4", File.ReadAllText(trace));
            Post(data, "cont");
            Assert.True(worker.Join(20000), "debugger thread did not finish");
            Assert.Equal(0, code);
            Assert.Equal("17" + Environment.NewLine, sink.ToString());
        }
        finally
        {
            Console.SetOut(previousOut);
            Console.SetError(previousErr);
            Environment.SetEnvironmentVariable("VIRE_DEBUGGER", previousDebug);
            Environment.SetEnvironmentVariable("VIRE_TRACE", previousTrace);
            try { Directory.Delete(dir, true); } catch (IOException) { }
        }
    }

    static void Post(string data, string command)
    {
        string cmd = Path.Combine(data, "debug.cmd");
        string tmp = cmd + ".tmp";
        File.WriteAllText(tmp, command + "\n");
        File.Move(tmp, cmd, true);
    }

    static string WaitFileContains(string path, string needle, int timeoutMs)
    {
        DateTime end = DateTime.UtcNow.AddMilliseconds(timeoutMs);
        string text = "";
        while (DateTime.UtcNow < end)
        {
            if (File.Exists(path))
            {
                try { text = File.ReadAllText(path); }
                catch (IOException) { text = ""; }
                if (text.IndexOf(needle, StringComparison.Ordinal) >= 0) return text;
            }
            Thread.Sleep(20);
        }
        throw new Xunit.Sdk.XunitException("timed out waiting for " + needle + " in " + text);
    }

    static string Sha8(string text)
    {
        byte[] hash = SHA256.HashData(Encoding.UTF8.GetBytes(text));
        return hash[0].ToString("x2") + hash[1].ToString("x2") + hash[2].ToString("x2") + hash[3].ToString("x2");
    }
}
