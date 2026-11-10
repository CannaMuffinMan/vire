using System;
using Xunit;

public class EmitU8Tests
{
    [Fact]
    public void EmitU8WrapsAndEmitListPushesInRangeBytes()
    {
        string root = DualMode.FindRoot();
        DualMode.Proc proc = DualMode.RunVire(root, new string[] { "emit-range.vire" }, root);
        Assert.Equal(0, proc.Code);
        Assert.Equal("255\n0\n1\n72\n0\n72\n44\n255\n0\n255\n5\n", DualMode.Norm(proc.Out));
    }

    [Fact]
    public void DualModeKeepsWrapSemanticsForLiteralHelpers()
    {
        string source = string.Join("\n", new string[]
        {
            "define floorDiv with n, d",
            "  return idiv with n, d",
            "end",
            "define emitU8 with buf, n",
            "  if n >= 0",
            "    if n < 256",
            "      return (push with buf, n)",
            "    end",
            "  end",
            "  let x be n",
            "  if x < 0",
            "    let x be x + 256",
            "  end",
            "  if x >= 256",
            "    let x be x - ((floorDiv with x, 256) * 256)",
            "  end",
            "  if x < 0",
            "    let x be 0",
            "  end",
            "  let buf be push with buf, x",
            "  return buf",
            "end",
            "define emitList with image, bytes",
            "  let i be 0",
            "  let n be length with bytes",
            "  while i < n",
            "    let b be bytes at i",
            "    if b >= 0 and b < 256",
            "      let image be push with image, b",
            "    else",
            "      let image be emitU8 with image, b",
            "    end",
            "    let i be i + 1",
            "  end",
            "  return image",
            "end",
            "define main",
            "  let a be emitU8 with [], -1",
            "  let f be emitList with [], [72, 300, -1]",
            "  say (a at 0)",
            "  say (f at 0)",
            "  say (f at 1)",
            "  say (f at 2)",
            "end",
            ""
        });
        DualMode.DualRun run = DualMode.RunSource(source, null);
        Assert.True(run.Matched, run.InterpOut + run.CompOut + run.InterpErr + run.CompErr);
        Assert.Equal(0, run.InterpCode);
        Assert.Equal("255\n72\n44\n255\n", DualMode.Norm(run.InterpOut));
    }

    [Fact]
    public void Shl8ScalesAWholeNumberBy256()
    {
        DualMode.DualRun run = DualMode.RunSource(
            "define main\n  say (shl8 with 2)\n  say (shl8 with 0)\nend\n",
            null);
        Assert.True(run.Matched, run.InterpOut + run.CompOut + run.InterpErr + run.CompErr);
        Assert.Equal(0, run.InterpCode);
        Assert.Equal("512\n0\n", DualMode.Norm(run.InterpOut));
    }
}
