using System;
using System.Collections.Generic;
using System.IO;
using System.Text;
using System.Text.RegularExpressions;
using Xunit;

public class ConformanceTests
{
    [Fact]
    public void GrammarProgramsMatchInBothModes()
    {
        string root = DualMode.FindRoot();
        string[] names = { "else-if.vire", "for-skip.vire", "try-miss.vire", "map-decimal.vire", "use_main.vire", "span-sort-drop.vire", "files-folders.vire" };
        foreach (string name in names)
        {
            string source = Path.Combine(root, "tests", "conformance", name);
            DualMode.DualRun both = DualMode.CompareFile(root, source, CopyWork(root, source, ExtraFor(root, name)));
            Assert.True(both.Matched, name + " interpreter vs compiled differed\n--- stdout i ---\n" + both.InterpOut + "\n--- stdout c ---\n" + both.CompOut + "\n--- stderr i ---\n" + both.InterpErr + "\n--- stderr c ---\n" + both.CompErr);
            Assert.Equal(0, both.InterpCode);
            Assert.Equal(0, both.CompCode);
        }
    }

    [Fact]
    public void CompiledDivisionErrorUsesRealLineAndColumn()
    {
        string root = DualMode.FindRoot();
        string source = Path.Combine(root, "tests", "conformance", "boom.vire");
        string work = CopyWork(root, source, null);
        DualMode.DualRun both = DualMode.CompareFile(root, Path.Combine(work, "boom.vire"), work);
        Assert.True(both.Matched, "boom outputs should match\n i " + both.InterpErr + "\n c " + both.CompErr);
        Assert.Equal(1, both.InterpCode);
        Assert.Contains("division by zero", both.CompErr);
        Assert.Contains("line 4", both.CompErr);
        Assert.Contains("line 4", both.InterpErr);
        Assert.DoesNotContain("line 1:", both.CompErr);
        Assert.DoesNotContain("line 1:", both.InterpErr);
        Match col = Regex.Match(both.CompErr, @"line 4 col (\d+)");
        Assert.True(col.Success, "compiled error should include a column on line 4: " + both.CompErr);
        Assert.True(int.Parse(col.Groups[1].Value) > 1, "compiled column should not be the dummy 1: " + both.CompErr);
        Match icol = Regex.Match(both.InterpErr, @"line 4 col (\d+)");
        Assert.True(icol.Success, "interpreter error should include a column on line 4: " + both.InterpErr);
        Assert.Equal(col.Groups[1].Value, icol.Groups[1].Value);
    }

    [Fact]
    public void ErrorProgramsAssertLineAndColumnInBothModes()
    {
        string root = DualMode.FindRoot();
        string dir = Path.Combine(root, "tests", "conformance", "errors");
        Assert.True(Directory.Exists(dir));
        foreach (string source in Directory.GetFiles(dir, "*.vire"))
        {
            string text = File.ReadAllText(source);
            Match want = Regex.Match(text, @"~ expect line (\d+) col (\d+)");
            Assert.True(want.Success, source + " needs an expect comment");
            string work = CopyWork(root, source, null);
            DualMode.DualRun both = DualMode.CompareFile(root, Path.Combine(work, Path.GetFileName(source)), work);
            Assert.True(both.Matched, Path.GetFileName(source) + " stderr differed\n i " + both.InterpErr + "\n c " + both.CompErr);
            Assert.Equal(1, both.InterpCode);
            string needle = "line " + want.Groups[1].Value + " col " + want.Groups[2].Value;
            Assert.Contains(needle, both.InterpErr);
            Assert.Contains(needle, both.CompErr);
        }
    }

    [Fact]
    public void SuiteProgramsMatchInBothModes()
    {
        string root = DualMode.FindRoot();
        List<string> programs = new List<string>();
        programs.Add(Path.Combine(root, "tests.vire"));
        AddMains(programs, Path.Combine(root, "checks"));
        AddMains(programs, Path.Combine(root, "systems"));
        StringBuilder report = new StringBuilder();
        int matched = 0;
        foreach (string program in programs)
        {
            string[] extra = null;
            if (Path.GetFileName(program).Equals("tests.vire", StringComparison.OrdinalIgnoreCase))
            {
                extra = new string[] { Path.Combine(root, "checks"), Path.Combine(root, "systems") };
            }
            string work = CopyWork(root, program, extra);
            DualMode.DualRun both = DualMode.CompareFile(root, Path.Combine(work, Path.GetFileName(program)), work);
            if (both.Matched && both.InterpCode == 0 && DualMode.Norm(both.InterpOut).Length > 0) matched++;
            else
            {
                report.AppendLine(program);
                report.AppendLine(" interp code " + both.InterpCode + " compiled code " + both.CompCode);
                report.AppendLine(" stdout i: " + both.InterpOut);
                report.AppendLine(" stdout c: " + both.CompOut);
                report.AppendLine(" stderr i: " + both.InterpErr);
                report.AppendLine(" stderr c: " + both.CompErr);
            }
        }
        Assert.True(programs.Count >= 8, "expected tests.vire plus checks/ and systems/ mains, got " + programs.Count);
        Assert.True(matched == programs.Count, "conformance mismatches (" + matched + "/" + programs.Count + "):\n" + report);
    }

    static string[] ExtraFor(string root, string name)
    {
        if (name == "use_main.vire")
            return new string[] { Path.Combine(root, "tests", "conformance", "use_lib.vire") };
        return null;
    }

    static void AddMains(List<string> programs, string dir)
    {
        foreach (string path in Directory.GetFiles(dir, "*.vire"))
        {
            string text = File.ReadAllText(path);
            if (text.Contains("define main")) programs.Add(path);
        }
    }

    static string CopyWork(string root, string source, string[] extra)
    {
        string work = Path.Combine(root, "data", "conformance", Guid.NewGuid().ToString("N"));
        Directory.CreateDirectory(work);
        Directory.CreateDirectory(Path.Combine(work, "data"));
        File.Copy(source, Path.Combine(work, Path.GetFileName(source)), true);
        if (extra != null)
        {
            foreach (string item in extra)
            {
                if (Directory.Exists(item))
                {
                    string name = Path.GetFileName(item);
                    CopyTree(item, Path.Combine(work, name));
                }
                else if (File.Exists(item))
                    File.Copy(item, Path.Combine(work, Path.GetFileName(item)), true);
            }
        }
        return work;
    }

    static void CopyTree(string from, string to)
    {
        Directory.CreateDirectory(to);
        foreach (string file in Directory.GetFiles(from))
            File.Copy(file, Path.Combine(to, Path.GetFileName(file)), true);
        foreach (string dir in Directory.GetDirectories(from))
            CopyTree(dir, Path.Combine(to, Path.GetFileName(dir)));
    }
}
