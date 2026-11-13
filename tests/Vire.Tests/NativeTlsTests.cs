using System;
using System.Collections.Generic;
using System.Globalization;
using System.IO;
using System.Text;
using Xunit;

public class NativeTlsTests
{
    [Fact]
    public void FetchIsExplicitTlsCapabilityAndConnectStaysLoopback()
    {
        string root = DualMode.FindRoot();
        string native = File.ReadAllText(Path.Combine(root, "compile-native.vire"));
        Assert.Contains("use \"src/rt-tls.vire\"", native);
        Assert.Contains("nm == \"fetch\"", native);
        Assert.Contains("needTls", native);
        Assert.Contains("openTlsImage", native);
        string pe = File.ReadAllText(Path.Combine(root, "src", "pe.vire"));
        Assert.Contains("openTlsImage", pe);
        Assert.Contains("secur32.dll", pe);
        Assert.Contains("WSAGetLastError", pe);
        Assert.DoesNotContain("getaddrinfo", pe);
        Assert.DoesNotContain("\"LoadLibraryA\"", pe);
        string tls = File.ReadAllText(Path.Combine(root, "src", "rt-tls.vire"));
        Assert.Contains("InitializeSecurityContextA", File.ReadAllText(Path.Combine(root, "src", "pe.vire")));
        Assert.Contains("DecryptMessage", pe);
        Assert.Contains("connect stays 127.0.0.1", tls);
        string net = File.ReadAllText(Path.Combine(root, "src", "rt-net.vire"));
        Assert.Contains("Loopback 127.0.0.1 only", net);
    }

    [Fact]
    public void FetchGuestImportsSecur32AndConnectGuestDoesNot()
    {
        string root = DualMode.FindRoot();
        string work = Path.Combine(root, "data", "native-tls", Guid.NewGuid().ToString("N"));
        Directory.CreateDirectory(work);
        try
        {
            File.WriteAllText(Path.Combine(work, "get.vire"), "define main\n  say (fetch with \"https://127.0.0.1:9443/\")\nend\n");
            File.WriteAllText(Path.Combine(work, "cn.vire"), "define main\n  close with (connect with \"127.0.0.1\", 9)\nend\n");
            File.WriteAllText(Path.Combine(work, "hello.vire"), "define main\n  say \"hello from vire\"\nend\n");
            DualMode.Proc get = DualMode.RunVire(root, new string[] { "compile-native.vire", Rel(work, "get.vire"), Rel(work, "get.hex") }, root);
            DualMode.Proc cn = DualMode.RunVire(root, new string[] { "compile-native.vire", Rel(work, "cn.vire"), Rel(work, "cn.hex") }, root);
            DualMode.Proc hello = DualMode.RunVire(root, new string[] { "compile-native.vire", Rel(work, "hello.vire"), Rel(work, "hello.hex") }, root);
            Assert.True(get.Code == 0, DualMode.Norm(get.Out + " " + get.Err));
            Assert.True(cn.Code == 0, DualMode.Norm(cn.Out + " " + cn.Err));
            Assert.Equal(0, hello.Code);
            HashSet<string> getImp = PeImports.Names(HexToPe(root, Rel(work, "get.hex")));
            HashSet<string> cnImp = PeImports.Names(HexToPe(root, Rel(work, "cn.hex")));
            HashSet<string> helloImp = PeImports.Names(HexToPe(root, Rel(work, "hello.hex")));
            Assert.Contains("AcquireCredentialsHandleA", getImp);
            Assert.Contains("InitializeSecurityContextA", getImp);
            Assert.Contains("DecryptMessage", getImp);
            Assert.Contains("WSAGetLastError", getImp);
            Assert.DoesNotContain("getaddrinfo", getImp);
            Assert.Contains("connect", getImp);
            Assert.DoesNotContain("LoadLibraryA", getImp);
            Assert.DoesNotContain("GetProcAddress", getImp);
            Assert.DoesNotContain("AcquireCredentialsHandleA", cnImp);
            Assert.DoesNotContain("getaddrinfo", cnImp);
            Assert.Contains("connect", cnImp);
            Assert.DoesNotContain("WSAStartup", helloImp);
            Assert.DoesNotContain("AcquireCredentialsHandleA", helloImp);
        }
        finally
        {
            try { Directory.Delete(work, true); } catch (IOException) { }
        }
    }

    static string Rel(string work, string name)
    {
        string root = DualMode.FindRoot();
        return Path.GetRelativePath(root, Path.Combine(work, name)).Replace('\\', '/');
    }

    static byte[] HexToPe(string root, string hexRel)
    {
        string hex = File.ReadAllText(Path.Combine(root, hexRel.Replace('/', Path.DirectorySeparatorChar))).Trim();
        byte[] pe = new byte[hex.Length / 2];
        for (int i = 0; i < pe.Length; i++)
            pe[i] = byte.Parse(hex.Substring(i * 2, 2), NumberStyles.HexNumber, CultureInfo.InvariantCulture);
        return pe;
    }
}
