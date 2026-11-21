using System;
using System.IO;
using Xunit;

public class WindowsPeProofTests
{
    [Fact]
    public void NormalizeNewlinesStripsBomAndCr()
    {
        Assert.Equal("ab\ncd\n", VirePaths.NormalizeNewlines("\uFEFFab\r\ncd\r"));
        Assert.Equal("a/b", NormSlashes("a\\b"));
    }

    [Fact]
    public void HostReasonPhrasesCoverListenStatuses()
    {
        Assert.Equal("OK", VireListen.ReasonOf(200));
        Assert.Equal("Switching Protocols", VireListen.ReasonOf(101));
        Assert.Equal("Forbidden", VireListen.ReasonOf(403));
        Assert.Equal("Not Found", VireListen.ReasonOf(404));
        Assert.Equal("Bad Request", VireListen.ReasonOf(400));
        Assert.Equal("Unauthorized", VireListen.ReasonOf(401));
        Assert.Equal("Request Timeout", VireListen.ReasonOf(408));
        Assert.Equal("Length Required", VireListen.ReasonOf(411));
        Assert.Equal("Payload Too Large", VireListen.ReasonOf(413));
        Assert.Equal("Range Not Satisfiable", VireListen.ReasonOf(416));
        Assert.Equal("Request Header Fields Too Large", VireListen.ReasonOf(431));
        Assert.Equal("Internal Server Error", VireListen.ReasonOf(500));
        Assert.Equal("Not Implemented", VireListen.ReasonOf(501));
        Assert.Equal("Bad Gateway", VireListen.ReasonOf(502));
        Assert.Equal("Service Unavailable", VireListen.ReasonOf(503));
        Assert.Equal("Insufficient Storage", VireListen.ReasonOf(507));
        Assert.Equal("Partial Content", VireListen.ReasonOf(206));
        Assert.Equal("OK", VireListen.ReasonOf(418));
    }

    [Fact]
    public void NativeNetParksHostReasonPhrases()
    {
        string root = DualMode.FindRoot();
        string blob = File.ReadAllText(Path.Combine(root, "src", "rt-net-blob.txt"));
        // ASCII " Forbidden" in the packed sendhttp reason table.
        Assert.Contains("20466f7262696464656e", blob);
        Assert.Contains("20537769746368696e672050726f746f636f6c73", blob);
        string net = File.ReadAllText(Path.Combine(root, "src", "rt-net.vire"));
        Assert.DoesNotContain("HTTP/1.1 403 Error", net);
    }

    [Fact]
    public void NativeListenImageParksForbiddenPhrase()
    {
        string root = DualMode.FindRoot();
        CompilerStage.CopyToData(root);
        string work = Path.Combine(root, "data", "reason-phrase", Guid.NewGuid().ToString("N"));
        Directory.CreateDirectory(work);
        File.Copy(Path.Combine(root, "tests", "rebuild", "guests", "listen-ws.vire"), Path.Combine(work, "listen-ws.vire"));
        string dir = Path.GetRelativePath(root, work).Replace('\\', '/');
        DualMode.Proc compiled = DualMode.RunVire(root, new string[] { "compile-native.vire", dir + "/listen-ws.vire", dir + "/listen-ws.hex" }, root);
        Assert.True(compiled.Code == 0, DualMode.Norm(compiled.Out + " " + compiled.Err));
        string hex = File.ReadAllText(Path.Combine(work, "listen-ws.hex")).Trim();
        byte[] image = new byte[hex.Length / 2];
        for (int i = 0; i < image.Length; i++)
            image[i] = Convert.ToByte(hex.Substring(i * 2, 2), 16);
        string ascii = System.Text.Encoding.ASCII.GetString(image);
        Assert.Contains(" Forbidden", ascii);
        Assert.Contains(" Switching Protocols", ascii);
        Assert.Contains(" Bad Request", ascii);
    }

    [Fact]
    public void CapsUnchanged()
    {
        string cs = File.ReadAllText(Path.Combine(DualMode.FindRoot(), "Vire.cs"));
        Assert.Contains("int itemCap = 100000;", cs);
        Assert.Contains("itemCap = 1000000;", cs);
        Assert.Contains("public const int ProgramStepCap = 5000000;", cs);
        Assert.Contains("33554432", File.ReadAllText(Path.Combine(DualMode.FindRoot(), "src", "rt.vire")));
    }

    static string NormSlashes(string path)
    {
        return path.Replace('\\', '/');
    }
}
