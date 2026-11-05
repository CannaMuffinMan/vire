using Xunit;

public class AtChainParityTests
{
    [Fact]
    public void ChainedAtReadsNestedValuesInBothModes()
    {
        string src = string.Join("\n", new string[]
        {
            "define main",
            "  let rows be [{\"name\": \"ada\"}]",
            "  say rows at 0 at \"name\"",
            "  let word be \"vire\"",
            "  say word at 1",
            "end",
            ""
        });
        DualMode.DualRun both = DualMode.RunSource(src, null);
        Assert.True(both.Matched, both.InterpOut + "\n" + both.CompOut + "\n" + both.InterpErr + "\n" + both.CompErr);
        Assert.Equal(0, both.InterpCode);
        Assert.Equal(0, both.CompCode);
        Assert.Contains("ada", DualMode.Norm(both.InterpOut));
        Assert.Contains("i", DualMode.Norm(both.InterpOut));
    }
}
