using System.IO;
using Xunit;

public class CryptoKatTests
{
    [Fact]
    public void GuestSha256AbcMatchesFips1804()
    {
        string root = DualMode.FindRoot();
        DualMode.Proc run = DualMode.RunVire(root, new string[] { "crypto-abc.vire" }, root);
        Assert.True(run.Code == 0, run.Err);
        Assert.Contains("ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad", DualMode.Norm(run.Out));
    }

    [Fact]
    public void BuiltinHashEmptyAndMillionAMatchFips1804()
    {
        string root = DualMode.FindRoot();
        DualMode.Proc run = DualMode.RunVire(root, new string[] { "crypto-mb.vire" }, root);
        Assert.True(run.Code == 0, run.Err);
        Assert.Contains("cdc76e5c9914fb9281a1c7e284d73e67f1809a48a497200e046d39ccc7112cd0", DualMode.Norm(run.Out));
    }
}
