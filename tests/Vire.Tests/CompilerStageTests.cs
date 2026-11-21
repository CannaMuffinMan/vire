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
        AssertSame(root, Path.Combine("src", "rt-ws.vire"), Path.Combine("data", "src", "rt-ws.vire"));
        AssertSame(root, Path.Combine("src", "elf.vire"), Path.Combine("data", "src", "elf.vire"));
        AssertSame(root, Path.Combine("src", "rt-linux.vire"), Path.Combine("data", "src", "rt-linux.vire"));
        AssertSame(root, Path.Combine("src", "rt-tls.vire"), Path.Combine("data", "src", "rt-tls.vire"));
        AssertSame(root, Path.Combine("src", "rt-tls-pe.vire"), Path.Combine("data", "src", "rt-tls-pe.vire"));
        AssertSame(root, Path.Combine("src", "rt-tls-pe-blob.txt"), Path.Combine("data", "src", "rt-tls-pe-blob.txt"));
        AssertSame(root, Path.Combine("src", "rt-tls-pe-pins.txt"), Path.Combine("data", "src", "rt-tls-pe-pins.txt"));
        AssertSame(root, Path.Combine("src", "rt-tls-pe-fixes.txt"), Path.Combine("data", "src", "rt-tls-pe-fixes.txt"));
        AssertSame(root, Path.Combine("src", "rt-net-blob.txt"), Path.Combine("data", "src", "rt-net-blob.txt"));
        AssertSame(root, Path.Combine("src", "rt-net-pins.txt"), Path.Combine("data", "src", "rt-net-pins.txt"));
        AssertSame(root, Path.Combine("src", "rt-net-fixes.txt"), Path.Combine("data", "src", "rt-net-fixes.txt"));
        AssertSame(root, Path.Combine("src", "rt-net-json-blob.txt"), Path.Combine("data", "src", "rt-net-json-blob.txt"));
        AssertSame(root, Path.Combine("src", "rt-net-json-pins.txt"), Path.Combine("data", "src", "rt-net-json-pins.txt"));
        AssertSame(root, Path.Combine("src", "rt-net-json-fixes.txt"), Path.Combine("data", "src", "rt-net-json-fixes.txt"));
        AssertSame(root, Path.Combine("src", "rt-net-r3-blob.txt"), Path.Combine("data", "src", "rt-net-r3-blob.txt"));
        AssertSame(root, Path.Combine("src", "rt-net-r3-pins.txt"), Path.Combine("data", "src", "rt-net-r3-pins.txt"));
        AssertSame(root, Path.Combine("src", "rt-net-r3-fixes.txt"), Path.Combine("data", "src", "rt-net-r3-fixes.txt"));
        AssertSame(root, Path.Combine("src", "rt-net-r4-blob.txt"), Path.Combine("data", "src", "rt-net-r4-blob.txt"));
        AssertSame(root, Path.Combine("src", "rt-net-r4-pins.txt"), Path.Combine("data", "src", "rt-net-r4-pins.txt"));
        AssertSame(root, Path.Combine("src", "rt-net-r4-fixes.txt"), Path.Combine("data", "src", "rt-net-r4-fixes.txt"));
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
        CompilerStage.CopyToData(root);
    }
}
