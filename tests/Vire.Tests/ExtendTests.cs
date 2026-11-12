using System.Collections.Generic;
using Xunit;

public class ExtendTests
{
    [Fact]
    public void ExtendWrapsLikeEmitU8AndHitsTheListCap()
    {
        List<object> got = (List<object>)Program.ExtendList(
            new List<object>(),
            new List<object> { 72, 300, -1, 0, 255, 256 },
            100000,
            1,
            1);
        Assert.Equal(new object[] { 72, 44, 255, 0, 255, 0 }, got.ToArray());
        VireError cap = Assert.Throws<VireError>(() =>
            Program.ExtendList(new List<object>(), new List<object> { 1 }, 0, 1, 1));
        Assert.Contains("list is too large", cap.Message);
    }

    [Fact]
    public void DualModeExtendMatchesInterpreter()
    {
        DualMode.DualRun run = DualMode.RunSource(
            "define main\n  say (extend with [], [72, 300, -1])\nend\n",
            null);
        Assert.True(run.Matched, run.InterpOut + run.CompOut + run.InterpErr + run.CompErr);
        Assert.Equal(0, run.InterpCode);
        Assert.Equal("[72, 44, 255]\n", DualMode.Norm(run.InterpOut));
    }

    [Fact]
    public void SelfExtendCopiesOriginalElementsOnce()
    {
        DualMode.DualRun run = DualMode.RunSource(
            "define main\n  let a be [1, 2]\n  say (extend with a, a)\nend\n",
            null);
        Assert.True(run.Matched, run.InterpOut + run.CompOut + run.InterpErr + run.CompErr);
        Assert.Equal("[1, 2, 1, 2]\n", DualMode.Norm(run.InterpOut));
    }
}
