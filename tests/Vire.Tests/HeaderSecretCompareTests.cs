using System.IO;
using Xunit;

public class HeaderSecretCompareTests
{
    [Fact]
    public void LongSecretsDifferingAfter256MustNotMatch()
    {
        string a = new string('A', 256) + new string('B', 24);
        string b = new string('A', 256) + new string('C', 24);
        Assert.Equal(280, a.Length);
        Assert.Equal(280, b.Length);
        Assert.False(Program.HeaderTokenMatches(
            "GET /x HTTP/1.1\r\nX-FCG-Token: " + a + "\r\n\r\n", b));
        Assert.False(Program.HeaderBearerMatches(
            "POST /block HTTP/1.1\r\nAuthorization: Bearer " + a + "\r\n\r\n", b));
        Assert.True(Program.HeaderBearerMatches(
            "POST /block HTTP/1.1\r\nAuthorization: Bearer " + a + "\r\n\r\n", a));
    }

    [Fact]
    public void LongSecretsDifferingAfter4096MustNotMatch()
    {
        string a = new string('A', 4096) + new string('B', 904);
        string b = new string('A', 4096) + new string('C', 904);
        Assert.Equal(5000, a.Length);
        Assert.Equal(5000, b.Length);
        Assert.False(Program.HeaderTokenMatches(
            "GET /x HTTP/1.1\r\nX-FCG-Token: " + a + "\r\n\r\n", b));
        Assert.False(Program.HeaderBearerMatches(
            "POST /block HTTP/1.1\r\nAuthorization: Bearer " + a + "\r\n\r\n", b));
        Assert.True(Program.HeaderBearerMatches(
            "POST /block HTTP/1.1\r\nAuthorization: Bearer " + a + "\r\n\r\n", a));
    }

    [Fact]
    public void LengthMismatchDoesNotMatch()
    {
        string want = new string('A', 32);
        Assert.False(Program.HeaderTokenMatches(
            "GET /x HTTP/1.1\r\nX-FCG-Token: " + want + "x\r\n\r\n", want));
    }

    [Fact]
    public void CtEqWalksWithoutByteInequalityBranch()
    {
        string root = DualMode.FindRoot();
        string crypto = File.ReadAllText(Path.Combine(root, "src", "rt-crypto.vire"));
        int start = crypto.IndexOf("define ct_eq with left, right");
        int end = crypto.IndexOf("\ndefine ", start + 1);
        string body = crypto.Substring(start, end - start);
        Assert.DoesNotContain("if a != b", body);
        Assert.Contains("xor8_bit", body);
        Assert.Contains("(n - m) * (n - m)", body);
    }
}
