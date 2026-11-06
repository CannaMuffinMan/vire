using System;
using System.IO;
using Xunit;

public class PortabilityMatrixTests
{
    [Fact]
    public void CiRunsPortableHostChecksAndDoesNotClaimOsxOrElfNative()
    {
        string root = DualMode.FindRoot();
        string yml = File.ReadAllText(Path.Combine(root, ".github", "workflows", "check.yml"));
        Assert.Contains("portable-check.sh", yml);
        Assert.Contains("linux-x64", yml);
        Assert.Contains("win-x64", yml);
        Assert.DoesNotContain("osx-arm64", yml);
        Assert.DoesNotContain("compile-native.elf", yml);
        string readme = File.ReadAllText(Path.Combine(root, "README.md"));
        Assert.Contains("osx-arm64", readme);
        string pe = File.ReadAllText(Path.Combine(root, "src", "pe.vire"));
        Assert.Contains("kernel32.dll", pe);
        Assert.DoesNotContain("libc.so", pe);
        string foreign = File.ReadAllText(Path.Combine(root, "VireForeign.cs"));
        Assert.Contains("could not open that dll", foreign);
        Assert.Contains("OperatingSystem.IsWindows", foreign);
    }

    [Fact]
    public void NativePathCheckCallsGetFileAttributesA()
    {
        string root = DualMode.FindRoot();
        string pe = File.ReadAllText(Path.Combine(root, "src", "pe.vire"));
        string more = File.ReadAllText(Path.Combine(root, "src", "rt-more.vire"));
        Assert.Contains("GetFileAttributesA", pe);
        Assert.Contains("iat_ga", pe);
        Assert.Contains("iat_ga", more);
        Assert.Contains("path_attr_ok", more);
        Assert.Contains("emitU32 with image, 1024", more);
    }

    [Fact]
    public void GapPlanNamesOpenNativeBlockers()
    {
        string plan = File.ReadAllText(Path.Combine(DualMode.FindRoot(), "GAP-CLOSURE.md"));
        Assert.Contains("symlink", plan);
        Assert.Contains("value stack", plan);
        Assert.Contains("32MB", plan);
        Assert.Contains("PR #31", plan);
        Assert.DoesNotContain("unhackable", plan);
    }
}
