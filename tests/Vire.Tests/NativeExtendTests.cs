using System.IO;
using Xunit;

public class NativeExtendTests
{
    [Fact]
    public void CompileNativeEmitsExtendInsteadOfMissingName()
    {
        string root = DualMode.FindRoot();
        string data = Path.Combine(root, "data");
        Directory.CreateDirectory(data);
        File.WriteAllText(Path.Combine(data, "extend-guest.vire"),
            "define main\n  say (extend with [1], [2, 300, -1])\nend\n");
        DualMode.Proc proc = DualMode.RunVire(
            root,
            new string[] { "compile-native.vire", "data/extend-guest.vire", "data/extend-guest.hex" },
            root);
        Assert.Equal(0, proc.Code);
        Assert.Contains("compiled", DualMode.Norm(proc.Out));
        Assert.DoesNotContain("no definition named extend", DualMode.Norm(proc.Out + proc.Err));
        Assert.True(File.Exists(Path.Combine(data, "extend-guest.hex")));
    }
}
