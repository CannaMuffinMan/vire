using System.Diagnostics;
using System.IO;
using Xunit;

public class CompilerStageTests
{
    [Fact]
    public void StagedCompilerSourcesMatchSrcAndCompileUsesThem()
    {
        string root = DualMode.FindRoot();
        RunStage(root);
        AssertSame(root, "compile-native.vire", Path.Combine("data", "compile-native.vire"));
        AssertSame(root, Path.Combine("src", "asm.vire"), Path.Combine("data", "src", "asm.vire"));
        AssertSame(root, Path.Combine("src", "pe.vire"), Path.Combine("data", "src", "pe.vire"));
        AssertSame(root, Path.Combine("src", "rt.vire"), Path.Combine("data", "src", "rt.vire"));
        AssertSame(root, Path.Combine("src", "rt-more.vire"), Path.Combine("data", "src", "rt-more.vire"));
        AssertSame(root, Path.Combine("src", "rt-net.vire"), Path.Combine("data", "src", "rt-net.vire"));
        AssertSame(root, Path.Combine("src", "rt-server.vire"), Path.Combine("data", "src", "rt-server.vire"));
        AssertSame(root, Path.Combine("src", "rt-net-blob.txt"), Path.Combine("data", "src", "rt-net-blob.txt"));
        AssertSame(root, Path.Combine("src", "rt-net-pins.txt"), Path.Combine("data", "src", "rt-net-pins.txt"));
        AssertSame(root, Path.Combine("src", "rt-net-fixes.txt"), Path.Combine("data", "src", "rt-net-fixes.txt"));
        AssertSame(root, Path.Combine("src", "rt-net-json-blob.txt"), Path.Combine("data", "src", "rt-net-json-blob.txt"));
        AssertSame(root, Path.Combine("src", "rt-net-json-pins.txt"), Path.Combine("data", "src", "rt-net-json-pins.txt"));
        AssertSame(root, Path.Combine("src", "rt-net-json-fixes.txt"), Path.Combine("data", "src", "rt-net-json-fixes.txt"));
        string guest = Path.Combine(root, "data", "staged-use.vire");
        File.WriteAllText(guest, "use \"src/asm.vire\"\ndefine main\n  say (hexOf with [72, 300, -1])\nend\n");
        DualMode.Proc proc = DualMode.RunVire(
            root,
            new string[] { "compile-native.vire", "data/staged-use.vire", "data/staged-use.hex" },
            root);
        Assert.Equal(0, proc.Code);
        Assert.Contains("compiled", DualMode.Norm(proc.Out));
    }

    static void AssertSame(string root, string a, string b)
    {
        byte[] left = File.ReadAllBytes(Path.Combine(root, a));
        byte[] right = File.ReadAllBytes(Path.Combine(root, b));
        Assert.Equal(left, right);
    }

    static void RunStage(string root)
    {
        ProcessStartInfo info = new ProcessStartInfo();
        info.FileName = "bash";
        info.Arguments = "tools/stage-compiler-src.sh";
        info.WorkingDirectory = root;
        info.RedirectStandardOutput = true;
        info.RedirectStandardError = true;
        info.UseShellExecute = false;
        Process process = Process.Start(info);
        string stdout = process.StandardOutput.ReadToEnd();
        string stderr = process.StandardError.ReadToEnd();
        Assert.True(process.WaitForExit(30000), "stage-compiler-src timed out");
        Assert.Equal(0, process.ExitCode);
        Assert.Contains("stage-compiler-src ok", stdout + stderr);
    }
}
