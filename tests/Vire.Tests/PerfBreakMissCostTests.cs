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
        try
        {
            Assert.False(VireDebug.Break(dir, "main", 1, "warmup"));
            long before = System.Threading.Interlocked.Read(ref VireDebug.ProbeCalls);
            Stopwatch sw = Stopwatch.StartNew();
            int hits = 0;
            for (int i = 0; i < n; i++)
            {
                if (VireDebug.Break(dir, "emitU8", 1, "miss")) hits++;
            }
            sw.Stop();
            Assert.Equal(0, hits);
            Assert.Equal(before + n, System.Threading.Interlocked.Read(ref VireDebug.ProbeCalls));
            Assert.False(File.Exists(Path.Combine(dir, "data", "break.txt")));
            double nsEach = sw.Elapsed.TotalNanoseconds / n;
            Console.WriteLine("break_miss_calls " + n);
            Console.WriteLine("break_miss_wall_s " + sw.Elapsed.TotalSeconds.ToString("0.000000"));
            Console.WriteLine("break_miss_ns_each " + nsEach.ToString("0.0"));
            Console.WriteLine("break_miss_root " + dir);
            string dataDir = Path.Combine(DualMode.FindRoot(), "data");
            Directory.CreateDirectory(dataDir);
            string report = Path.Combine(dataDir, "perf-break-miss.txt");
            File.WriteAllText(report, "break_miss_calls " + n + "\nbreak_miss_wall_s " + sw.Elapsed.TotalSeconds.ToString("0.000000") + "\nbreak_miss_ns_each " + nsEach.ToString("0.0") + "\n");
        }
        finally
        {
            try { Directory.Delete(dir, true); } catch (IOException) { }
        }
    }
}
