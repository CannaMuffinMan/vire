using System;
using System.IO;
using System.Text.RegularExpressions;
using Xunit;

public class HarnessTests
{
    [Fact]
    public void ProjectsTargetNet10AndWarningsAreErrors()
    {
        string root = FindRoot();
        string main = File.ReadAllText(Path.Combine(root, "vire.csproj"));
        string tests = File.ReadAllText(Path.Combine(root, "tests", "Vire.Tests", "Vire.Tests.csproj"));
        string windows = File.ReadAllText(Path.Combine(root, "windows", "vire.windows.csproj"));
        Assert.Contains("<TargetFramework>net10.0</TargetFramework>", main);
        Assert.Contains("<TreatWarningsAsErrors>true</TreatWarningsAsErrors>", main);
        Assert.Contains("<TargetFramework>net10.0</TargetFramework>", tests);
        Assert.Contains("<TargetFramework>net10.0-windows</TargetFramework>", windows);
        Assert.Contains("WINDOWS", windows);
        Assert.Contains("UseWindowsForms", windows);
    }

    [Fact]
    public void WorkflowPinsActionsToFullShas()
    {
        string yml = File.ReadAllText(Path.Combine(FindRoot(), ".github", "workflows", "check.yml"));
        MatchCollection uses = Regex.Matches(yml, @"uses:\s+\S+@([0-9a-f]+)");
        Assert.True(uses.Count >= 3, "expected pinned uses: lines");
        foreach (Match match in uses)
            Assert.Equal(40, match.Groups[1].Value.Length);
    }

    [Fact]
    public void GitTracksNoBinaries()
    {
        string root = FindRoot();
        foreach (string path in Directory.GetFiles(root, "*", SearchOption.AllDirectories))
        {
            if (path.Contains(Path.DirectorySeparatorChar + ".git" + Path.DirectorySeparatorChar)) continue;
            if (path.Contains(Path.DirectorySeparatorChar + "bin" + Path.DirectorySeparatorChar)) continue;
            if (path.Contains(Path.DirectorySeparatorChar + "obj" + Path.DirectorySeparatorChar)) continue;
            string ext = Path.GetExtension(path);
            Assert.False(ext.Equals(".exe", StringComparison.OrdinalIgnoreCase) || ext.Equals(".dll", StringComparison.OrdinalIgnoreCase), path);
        }
    }

    static string FindRoot()
    {
        string dir = AppContext.BaseDirectory;
        for (int i = 0; i < 8; i++)
        {
            if (File.Exists(Path.Combine(dir, "vire.csproj"))) return dir;
            DirectoryInfo parent = Directory.GetParent(dir);
            if (parent == null) break;
            dir = parent.FullName;
        }
        throw new InvalidOperationException("could not find the vire repo root");
    }
}
