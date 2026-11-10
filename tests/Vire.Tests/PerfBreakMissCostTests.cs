using System;
using System.Diagnostics;
using System.IO;
using Xunit;

public class PerfBreakMissCostTests
{
    [Fact]
    public void BreakMissPathReportsNanosecondsPerCall()
    {
        string dir = Path.Combine(Path.GetTempPath(), "vire-perf-break-" + Guid.NewGuid().ToString("N"));
        Directory.CreateDirectory(Path.Combine(dir, "data"));
        int n = 20000;
        string prior = Environment.GetEnvironmentVariable("VIRE_DEBUGGER");
        try
        {
            Environment.SetEnvironmentVariable("VIRE_DEBUGGER", null);
            Assert.False(VireDebug.Break(dir, "main", 1, "warmup"));
            long beforeOff = System.Threading.Interlocked.Read(ref VireDebug.ProbeCalls);
            Stopwatch off = Stopwatch.StartNew();
            int hitsOff = 0;
            for (int i = 0; i < n; i++)
            {
                if (VireDebug.Break(dir, "emitU8", 1, "miss")) hitsOff++;
            }
            off.Stop();
            Assert.Equal(0, hitsOff);
            Assert.Equal(beforeOff, System.Threading.Interlocked.Read(ref VireDebug.ProbeCalls));

            Environment.SetEnvironmentVariable("VIRE_DEBUGGER", "1");
            Assert.False(VireDebug.Break(dir, "main", 1, "warmup"));
            long beforeOn = System.Threading.Interlocked.Read(ref VireDebug.ProbeCalls);
            Stopwatch on = Stopwatch.StartNew();
            int hitsOn = 0;
            for (int i = 0; i < n; i++)
            {
                if (VireDebug.Break(dir, "emitU8", 1, "miss")) hitsOn++;
            }
            on.Stop();
            Assert.Equal(0, hitsOn);
            Assert.Equal(beforeOn + n, System.Threading.Interlocked.Read(ref VireDebug.ProbeCalls));
            Assert.False(File.Exists(Path.Combine(dir, "data", "break.txt")));

            double nsOff = off.Elapsed.TotalNanoseconds / n;
            double nsOn = on.Elapsed.TotalNanoseconds / n;
            Console.WriteLine("break_skip_calls " + n);
            Console.WriteLine("break_skip_ns_each " + nsOff.ToString("0.0"));
            Console.WriteLine("break_miss_calls " + n);
            Console.WriteLine("break_miss_wall_s " + on.Elapsed.TotalSeconds.ToString("0.000000"));
            Console.WriteLine("break_miss_ns_each " + nsOn.ToString("0.0"));
            string dataDir = Path.Combine(DualMode.FindRoot(), "data");
            Directory.CreateDirectory(dataDir);
            File.WriteAllText(
                Path.Combine(dataDir, "perf-break-miss.txt"),
                "break_skip_calls " + n + "\nbreak_skip_ns_each " + nsOff.ToString("0.0") + "\nbreak_miss_calls " + n + "\nbreak_miss_wall_s " + on.Elapsed.TotalSeconds.ToString("0.000000") + "\nbreak_miss_ns_each " + nsOn.ToString("0.0") + "\n");
        }
        finally
        {
            Environment.SetEnvironmentVariable("VIRE_DEBUGGER", prior);
            try { Directory.Delete(dir, true); } catch (IOException) { }
        }
    }
}
