using System;
using System.Globalization;
using System.IO;
using System.Text;
using Xunit;

public class NativeNetTests
{
    [Fact]
    public void CompilerSourcesIncludeNetRuntimeAndOptInListen()
    {
        string root = DualMode.FindRoot();
        string net = File.ReadAllText(Path.Combine(root, "src", "rt-net.vire"));
        string staged = File.ReadAllText(Path.Combine(root, "data", "src", "rt-net.vire"));
        Assert.Equal(net, staged);
        Assert.Contains("emitNetRuntime", net);
        Assert.Contains("rt_listen", net);
        Assert.Contains("rt_json", net);
        Assert.Contains("rt_parse", net);
        Assert.DoesNotContain("CreateFileA", net);
        string native = File.ReadAllText(Path.Combine(root, "compile-native.vire"));
        Assert.Contains("use \"src/rt-net.vire\"", native);
        Assert.Contains("nm == \"json\"", native);
        Assert.Contains("nm == \"listen\"", native);
        string pe = File.ReadAllText(Path.Combine(root, "src", "pe.vire"));
        Assert.Contains("LoadLibraryA", pe);
        Assert.Contains("GetProcAddress", pe);
        Assert.Contains("GetTickCount", pe);
        Assert.Contains("IAT_NET", pe);
    }

    [Fact]
    public void HostCompileOfHealthGuestImportsLoaderAndWs2Name()
    {
        string root = DualMode.FindRoot();
        string work = Path.Combine(root, "data", "native-net", Guid.NewGuid().ToString("N"));
        Directory.CreateDirectory(work);
        try
        {
            File.Copy(Path.Combine(root, "guest-health.vire"), Path.Combine(work, "guest-health.vire"));
            string srcRel = ("data/native-net/" + Path.GetFileName(work) + "/guest-health.vire").Replace('\\', '/');
            string hexRel = ("data/native-net/" + Path.GetFileName(work) + "/guest-health.hex").Replace('\\', '/');
            DualMode.Proc compiled = DualMode.RunVire(root, new string[] { "compile-native.vire", srcRel, hexRel }, root);
            Assert.Equal(0, compiled.Code);
            Assert.Contains("compiled", DualMode.Norm(compiled.Out));
            string hex = File.ReadAllText(Path.Combine(root, hexRel.Replace('/', Path.DirectorySeparatorChar))).Trim();
            byte[] pe = new byte[hex.Length / 2];
            for (int i = 0; i < pe.Length; i++)
                pe[i] = byte.Parse(hex.Substring(i * 2, 2), NumberStyles.HexNumber, CultureInfo.InvariantCulture);
            string ascii = Encoding.ASCII.GetString(pe);
            Assert.Contains("LoadLibraryA", ascii);
            Assert.Contains("GetProcAddress", ascii);
            Assert.Contains("GetTickCount", ascii);
            Assert.Contains("ws2_32.dll", ascii);
            Assert.Contains("WSAStartup", ascii);
            Assert.DoesNotContain("VirtualProtect", ascii);
        }
        finally
        {
            try { Directory.Delete(work, true); } catch (IOException) { }
        }
    }
}
