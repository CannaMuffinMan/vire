using System;
using System.Collections.Generic;
using System.Diagnostics;
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
        string proof = File.ReadAllText(Path.Combine(root, "tools", "VireProof", "VireProof.csproj"));
        Assert.Contains("<TargetFramework>net10.0</TargetFramework>", proof);
        Assert.Contains("<TargetFramework>net10.0-windows</TargetFramework>", windows);
        Assert.Contains("WINDOWS", windows);
        Assert.Contains("UseWindowsForms", windows);
    }

    [Fact]
    public void WorkflowPinsActionsToFullShas()
    {
        string root = FindRoot();
        string yml = File.ReadAllText(Path.Combine(root, ".github", "workflows", "check.yml"));
        string workflows = Path.Combine(root, ".github", "workflows");
        foreach (string path in Directory.GetFiles(workflows, "*.yml"))
        {
            string text = File.ReadAllText(path);
            MatchCollection uses = Regex.Matches(text, @"^\s+- uses:\s+(\S+)", RegexOptions.Multiline);
            foreach (Match match in uses)
            {
                string spec = match.Groups[1].Value;
                Match pin = Regex.Match(spec, @"^[A-Za-z0-9_./-]+@([0-9a-f]{40})$");
                Assert.True(pin.Success, "unpinned or short SHA action: " + spec + " in " + Path.GetFileName(path));
            }
        }
        MatchCollection checkUses = Regex.Matches(yml, @"^\s+- uses:\s+(\S+)", RegexOptions.Multiline);
        Assert.True(checkUses.Count >= 3, "expected pinned uses: lines");
        Assert.Contains("dotnet-version: 10.0.x", yml);
        Assert.Contains("bash tools/check-tracked-binaries.sh", yml);
        Assert.Contains("bash tools/selfhost-check.sh", yml);
    }

    [Fact]
    public void DockerfileBasesArePinnedByDigest()
    {
        string docker = File.ReadAllText(Path.Combine(FindRoot(), "Dockerfile"));
        MatchCollection froms = Regex.Matches(docker, @"^FROM\s+(\S+)", RegexOptions.Multiline);
        Assert.True(froms.Count >= 2, "expected FROM lines");
        foreach (Match match in froms)
        {
            string image = match.Groups[1].Value;
            if (image.StartsWith("--from=", StringComparison.Ordinal)) continue;
            Assert.True(
                Regex.IsMatch(image, @"^[^@\s]+@sha256:[0-9a-f]{64}$"),
                "unpinned Docker base: " + image);
        }
    }

    [Fact]
    public void SdkAndProjectsAreNet10()
    {
        string root = FindRoot();
        string global = File.ReadAllText(Path.Combine(root, "global.json"));
        Assert.Contains("\"version\": \"10.0.", global);
        foreach (string path in Directory.GetFiles(root, "*.csproj", SearchOption.AllDirectories))
        {
            string text = File.ReadAllText(path);
            Match tfm = Regex.Match(text, @"<TargetFramework>([^<]+)</TargetFramework>");
            Assert.True(tfm.Success, path);
            Assert.StartsWith("net10.0", tfm.Groups[1].Value);
        }
    }

    [Fact]
    public void SelfhostChecksCompareUnsealedPayloadBytes()
    {
        string root = FindRoot();
        string sh = File.ReadAllText(Path.Combine(root, "tools", "selfhost-check.sh"));
        string ps = File.ReadAllText(Path.Combine(root, "tools", "selfhost-check.ps1"));
        Assert.Contains("payload-write", sh);
        Assert.Contains("cmp -s", sh);
        Assert.Contains("--compiler compiler.vire", sh);
        Assert.Contains("run data/stage1.vc data/compiler.vire data/stage2.vc", sh);
        Assert.Contains("payload-write", ps);
        Assert.Contains("Compare-Object", ps);
        Assert.Contains("--compiler", ps);
        Assert.Contains("run data/stage1.vc data/compiler.vire data/stage2.vc", ps);
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
    public void NativeSecAndHelloHandoffBoundTheCompileWait()
    {
        string root = FindRoot();
        string sec = File.ReadAllText(Path.Combine(root, "tools", "native-sec-windows.ps1"));
        string hello = File.ReadAllText(Path.Combine(root, "tools", "native-hello-handoff.ps1"));
        string yml = File.ReadAllText(Path.Combine(root, ".github", "workflows", "check.yml"));
        Assert.Contains("WaitForExit", sec);
        Assert.Contains("timed out after", sec);
        Assert.Contains("PositionalBinding = $false", sec);
        Assert.Contains("[string[]]$VireArgs", sec);
        Assert.Contains("WaitForExit", hello);
        Assert.Contains("120000", hello);
        Assert.Contains("native-hello-handoff.ps1", yml);
        Assert.Contains("native-sec-windows.ps1", yml);
        Assert.Contains("native-oom.ps1", yml);
        Assert.Contains("native-gc-loop-proof.ps1", yml);
        Assert.Contains("schema-prove-windows.ps1", yml);
        Assert.Contains("native-tcp-windows.ps1", yml);
        Assert.Contains("pg-prove-windows.ps1", yml);
        Assert.Contains("native-pg-windows", yml);
        Assert.Contains("pg-tls-prove-windows.ps1", yml);
        Assert.Contains("native-pg-tls-windows", yml);
        Assert.Contains("native-redis-tls-windows", yml);
        Assert.Contains("redis-tls-prove-windows.ps1", yml);
        Assert.Contains("pg-redis-tls-windows.ps1", yml);
        Assert.Contains("native-pg-redis-tls-windows", yml);
        Assert.Contains("native-selfhost-handoff.ps1", yml);
        Assert.Contains("native-selfhost-windows", yml);
        Assert.DoesNotContain("continue-on-error: true", yml);
        string self = File.ReadAllText(Path.Combine(root, "tools", "native-selfhost-handoff.ps1"));
        Assert.Contains("WaitForExit", self);
        Assert.Contains("gen1_sha256", self);
        Assert.Contains("compile-native.vire", self);
        Assert.Contains("--compiler", self);
        Assert.DoesNotContain("Apply-SecWiden", self);
        Assert.DoesNotContain("iat_sl", self);
        Assert.DoesNotContain("python -c", self);
        Assert.DoesNotContain("bash ", self);
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
    public void CouchStationAllReferencedFilesExist()
    {
        string root = FindRoot();
        string all = File.ReadAllText(Path.Combine(root, "tools", "couchstation-windows-all.ps1"));
        HashSet<string> scripts = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
        foreach (Match m in Regex.Matches(all, @"Run-Script\s+""(tools/[^""]+\.ps1)"""))
            scripts.Add(m.Groups[1].Value.Replace('/', Path.DirectorySeparatorChar));
        Assert.Contains("tools" + Path.DirectorySeparatorChar + "rebuild-fcgbds-heartbeat-windows.ps1", scripts);
        Assert.Contains("tools" + Path.DirectorySeparatorChar + "rebuild-chain-limits-windows.ps1", scripts);
        foreach (string rel in scripts)
        {
            string path = Path.Combine(root, rel);
            Assert.True(File.Exists(path), "missing " + rel);
            string text = File.ReadAllText(path);
            foreach (Match m in Regex.Matches(text, @"Join-Path \$Root ""([^""]+)"""))
            {
                string inner = m.Groups[1].Value;
                if (inner.Contains("$") || inner.Contains("{")) continue;
                bool tracked = inner.StartsWith("tests/", StringComparison.Ordinal)
                    || inner.StartsWith("guest-", StringComparison.Ordinal)
                    || inner.StartsWith("src/", StringComparison.Ordinal)
                    || inner.StartsWith("tools/", StringComparison.Ordinal)
                    || inner == "session-prove.vire"
                    || inner == "guest-health.vire"
                    || inner == "guest-chain.vire"
                    || inner == "guest-health-tls.vire";
                if (!tracked) continue;
                string target = Path.Combine(root, inner.Replace('/', Path.DirectorySeparatorChar));
                Assert.True(File.Exists(target) || Directory.Exists(target), rel + " references missing " + inner);
            }
        }
        Assert.True(File.Exists(Path.Combine(root, "tests", "rebuild", "guests", "fcgbds-heartbeat.vire")));
        Assert.True(File.Exists(Path.Combine(root, "tests", "rebuild", "guests", "fcgbds-heartbeat-fail.vire")));
        string hostInfo = File.ReadAllText(Path.Combine(root, "tools", "native-host-info.ps1"));
        Assert.Contains("ConvertTo-ProcessArguments", hostInfo);
        Assert.Contains("Get-ListenPort", hostInfo);
        Assert.Contains("WaitForExit", all);
        Assert.Contains("wall timeout", all);
        Assert.Contains("g1.exe", all);
        Assert.DoesNotContain("python3", File.ReadAllText(Path.Combine(root, "tools", "rebuild-chain-limits-windows.ps1")));
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
            string norm = path.Replace('\\', '/');
            if (norm.Contains("/data/")) continue;
            string ext = Path.GetExtension(path);
            Assert.False(ext.Equals(".exe", StringComparison.OrdinalIgnoreCase) || ext.Equals(".dll", StringComparison.OrdinalIgnoreCase), path);
        }
    }

    [Fact]
    public void GitIndexHasNoBuildBinaries()
    {
        string root = FindRoot();
        ProcessStartInfo info = new ProcessStartInfo();
        info.FileName = "git";
        info.Arguments = "ls-files";
        info.WorkingDirectory = root;
        info.RedirectStandardOutput = true;
        info.RedirectStandardError = true;
        info.UseShellExecute = false;
        Process process = Process.Start(info);
        string output = process.StandardOutput.ReadToEnd();
        process.WaitForExit(30000);
        Assert.Equal(0, process.ExitCode);
        string[] lines = output.Replace("\r\n", "\n").Split('\n');
        foreach (string raw in lines)
        {
            string path = raw.Trim();
            if (path.Length == 0) continue;
            string norm = path.Replace('\\', '/');
            string ext = Path.GetExtension(norm);
            bool fixtureVc = norm.StartsWith("tests/fixtures/", StringComparison.OrdinalIgnoreCase) &&
                ext.Equals(".vc", StringComparison.OrdinalIgnoreCase);
            if (fixtureVc) continue;
            Assert.False(
                ext.Equals(".exe", StringComparison.OrdinalIgnoreCase) ||
                ext.Equals(".dll", StringComparison.OrdinalIgnoreCase) ||
                ext.Equals(".pdb", StringComparison.OrdinalIgnoreCase) ||
                ext.Equals(".hex", StringComparison.OrdinalIgnoreCase) ||
                ext.Equals(".vc", StringComparison.OrdinalIgnoreCase),
                "tracked build binary: " + path);
            Assert.False(
                norm.StartsWith("bin/", StringComparison.OrdinalIgnoreCase) ||
                norm.StartsWith("obj/", StringComparison.OrdinalIgnoreCase) ||
                norm.StartsWith("dist/", StringComparison.OrdinalIgnoreCase) ||
                norm.StartsWith("publish/", StringComparison.OrdinalIgnoreCase),
                "tracked build output: " + path);
        }
        string script = File.ReadAllText(Path.Combine(root, "tools", "check-tracked-binaries.sh"));
        Assert.Contains(".exe", script);
        Assert.Contains(".vc", script);
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
