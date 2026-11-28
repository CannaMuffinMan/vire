using System;
using System.Collections.Generic;
using System.IO;
using System.Text.RegularExpressions;
using Xunit;

public class WindowsHostCompileTests
{
    [Fact]
    public void WindowsCsprojCompilesEveryLinuxHostCsFile()
    {
        string root = DualMode.FindRoot();
        string windowsProj = Path.Combine(root, "windows", "vire.windows.csproj");
        string text = File.ReadAllText(windowsProj);

        HashSet<string> linux = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
        foreach (string path in Directory.GetFiles(root, "*.cs"))
            linux.Add(Path.GetFullPath(path));

        HashSet<string> windows = ExpandCompileIncludes(windowsProj, text);
        List<string> missing = new List<string>();
        foreach (string path in linux)
        {
            if (!windows.Contains(path))
                missing.Add(Path.GetFileName(path));
        }
        missing.Sort(StringComparer.OrdinalIgnoreCase);
        Assert.True(
            missing.Count == 0,
            "windows/vire.windows.csproj Compile items miss Linux host .cs files: " +
            string.Join(", ", missing));

        List<string> extra = new List<string>();
        foreach (string path in windows)
        {
            if (!linux.Contains(path))
                extra.Add(path);
        }
        extra.Sort(StringComparer.OrdinalIgnoreCase);
        Assert.True(
            extra.Count == 0,
            "windows/vire.windows.csproj Compile items not in Linux host set: " +
            string.Join(", ", extra));
        Assert.DoesNotContain("TODO(VIRE-FINISH-NOW)", text);
    }

    static HashSet<string> ExpandCompileIncludes(string windowsProj, string text)
    {
        string windowsDir = Path.GetDirectoryName(windowsProj);
        HashSet<string> files = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
        foreach (Match match in Regex.Matches(text, @"<Compile\s+Include=""([^""]+)"""))
        {
            string include = match.Groups[1].Value.Replace('\\', Path.DirectorySeparatorChar)
                .Replace('/', Path.DirectorySeparatorChar);
            string combined = Path.GetFullPath(Path.Combine(windowsDir, include));
            if (combined.IndexOf('*') < 0)
            {
                files.Add(combined);
                continue;
            }
            string dir = Path.GetDirectoryName(combined);
            string pattern = Path.GetFileName(combined);
            if (!Directory.Exists(dir)) continue;
            foreach (string path in Directory.GetFiles(dir, pattern))
                files.Add(Path.GetFullPath(path));
        }
        return files;
    }
}
