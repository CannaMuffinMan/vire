using System;
using System.IO;
using Xunit;

public class InspectTests
{
    [Fact]
    public void RecordWritesArgsOnlyWhenEnabled()
    {
        string dir = Path.Combine(Path.GetTempPath(), "vire-inspect-" + Guid.NewGuid().ToString("N"));
        Directory.CreateDirectory(dir);
        string inspect = Path.Combine(dir, "data", "inspect.txt");
        string previous = Environment.GetEnvironmentVariable("VIRE_INSPECT");
        try
        {
            Environment.SetEnvironmentVariable("VIRE_INSPECT", null);
            VireInspect.Record(dir, "add", 3, "1, 2");
            Assert.False(File.Exists(inspect));

            Environment.SetEnvironmentVariable("VIRE_INSPECT", "1");
            VireInspect.Record(dir, "add", 3, "1, 2");
            Assert.True(File.Exists(inspect));
            string full = Path.GetFullPath(inspect);
            Assert.StartsWith(Path.GetFullPath(Path.Combine(dir, "data")) + Path.DirectorySeparatorChar, full);
            Assert.Equal("add line 3 1, 2\n", File.ReadAllText(inspect));

            VireInspect.Record(dir, "add", 4, "a\nb");
            Assert.Equal("add line 3 1, 2\n", File.ReadAllText(inspect));

            string longArgs = new string('x', 300);
            VireInspect.Record(dir, "wide", 9, longArgs);
            string[] lines = File.ReadAllLines(inspect);
            Assert.Equal(2, lines.Length);
            Assert.Equal(200, lines[1].Length);
            Assert.StartsWith("wide line 9 ", lines[1]);

            for (int i = 0; i < 198; i++)
                VireInspect.Record(dir, "more", i, "ok");
            lines = File.ReadAllLines(inspect);
            Assert.Equal(200, lines.Length);
            VireInspect.Record(dir, "past", 999, "no");
            lines = File.ReadAllLines(inspect);
            Assert.Equal(200, lines.Length);
            Assert.DoesNotContain("past line 999 no", File.ReadAllText(inspect));

            Environment.SetEnvironmentVariable("VIRE_INSPECT", null);
            VireInspect.Record(dir, "off", 1, "silent");
            Assert.Equal(200, File.ReadAllLines(inspect).Length);
        }
        finally
        {
            Environment.SetEnvironmentVariable("VIRE_INSPECT", previous);
            try { Directory.Delete(dir, true); } catch (IOException) { }
        }
    }
}
