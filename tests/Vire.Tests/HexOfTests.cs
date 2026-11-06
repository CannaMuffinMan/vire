using System.IO;
using Xunit;

public class HexOfTests
{
    [Fact]
    public void HexOfMatchesLockedWrapForWholeNumbers()
    {
        string root = DualMode.FindRoot();
        DualMode.Proc proc = DualMode.RunVire(root, new string[] { "hex-range.vire" }, root);
        Assert.Equal(0, proc.Code);
        Assert.Equal("00\n48\nff\n00\n00\n2c\n482c0000ff\n48\n", DualMode.Norm(proc.Out));
    }

    [Fact]
    public void DualModeHexOfMatchesInterpreterOnWrapList()
    {
        string root = DualMode.FindRoot();
        string asm = File.ReadAllText(Path.Combine(root, "src", "asm.vire"));
        DualMode.DualRun run = DualMode.RunSource(
            "use \"src/asm.vire\"\ndefine main\n  say (hexOf with [72, 300, -1, 0, 255])\nend\n",
            new string[] { "src/asm.vire", asm });
        Assert.True(run.Matched, run.InterpOut + run.CompOut + run.InterpErr + run.CompErr);
        Assert.Equal(0, run.InterpCode);
        Assert.Equal("482c0000ff\n", DualMode.Norm(run.InterpOut));
    }
}
