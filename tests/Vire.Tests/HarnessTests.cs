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
        Assert.True(
            windows.Contains("..\\*.cs") || windows.Contains("../*.cs") || windows.Contains("Include=\"..\\*.cs\"") || windows.Contains("VireListen.cs"),
            "windows project must compile every runtime .cs file");
    }

    [Fact]
    public void WorkflowPinsActionsToFullShas()
    {
        string yml = File.ReadAllText(Path.Combine(FindRoot(), ".github", "workflows", "check.yml"));
        MatchCollection uses = Regex.Matches(yml, @"uses:\s+\S+@([0-9a-f]+)");
        Assert.True(uses.Count >= 3, "expected pinned uses: lines");
        foreach (Match match in uses)
            Assert.Equal(40, match.Groups[1].Value.Length);
        Assert.Contains("windows-gui", yml);
        Assert.Contains("vire.windows.csproj", yml);
        Assert.Contains("Vire.Windows.Tests", yml);
    }

    [Fact]
    public void DockerfileCopiesEveryRootCsharpFile()
    {
        string root = FindRoot();
        string docker = File.ReadAllText(Path.Combine(root, "Dockerfile"));
        Match copy = Regex.Match(docker, @"^COPY (.+) \./\s*$", RegexOptions.Multiline);
        Assert.True(copy.Success, "expected a COPY ... ./ line");
        string spec = copy.Groups[1].Value;
        foreach (string path in Directory.GetFiles(root, "*.cs"))
        {
            string name = Path.GetFileName(path);
            Assert.True(
                spec.Contains("*.cs") || (" " + spec + " ").Contains(" " + name + " "),
                "Dockerfile must copy " + name);
        }
        Assert.Contains("vire.csproj", spec);
    }

    [Fact]
    public void NativeSmokeKeepsVireStdoutOffTheExitCode()
    {
        string text = File.ReadAllText(Path.Combine(FindRoot(), "tools", "native-smoke.ps1"));
        Assert.Contains("$code = Invoke-Vire", text);
        Assert.Contains("$out = &", text);
        Assert.Contains("Write-Host", text);
        Assert.Contains("$LASTEXITCODE", text);
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
