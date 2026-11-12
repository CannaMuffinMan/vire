using System;
using System.Collections.Generic;
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
        Assert.Contains("hu_fold", net);
        Assert.Contains("hu_frame", net);
        Assert.Contains("rt_net_hdrunsafe", net);
        string blob = File.ReadAllText(Path.Combine(root, "src", "rt-net-blob.txt")).Trim();
        Assert.True(blob.Length % 2 == 0);
        Assert.Equal("e9", blob.Substring(0x62d * 2, 2));
        Assert.Contains("636f6e74656e742d6c656e6774683a", blob);
        Assert.Contains("7472616e736665722d656e636f64696e673a", blob);
        Assert.DoesNotContain("CreateFileA", net);
        Assert.DoesNotContain("GetProcAddress", net);
        Assert.DoesNotContain("LoadLibraryA", net);
        string native = File.ReadAllText(Path.Combine(root, "compile-native.vire"));
        Assert.Contains("use \"src/rt-net.vire\"", native);
        Assert.Contains("nm == \"json\"", native);
        Assert.Contains("nm == \"listen\"", native);
        Assert.Contains("openNetImage", native);
        string pe = File.ReadAllText(Path.Combine(root, "src", "pe.vire"));
        Assert.Contains("openNetImage", pe);
        Assert.Contains("let buf be emitU8 with buf, (codeOf with (raw at i))", pe);
        Assert.DoesNotContain("let buf be emitU8 with buf, (ord with (raw at i))", pe);
        string guest = File.ReadAllText(Path.Combine(root, "guest-health.vire"));
        Assert.Contains("path == \"/health\"", guest);
        Assert.Contains("path == \"/api/health\"", guest);
        Assert.Contains("service", guest);
        Assert.Contains("fcgcpa", guest);
        Assert.Contains("payments", guest);
        Assert.Contains("ws2_32.dll", pe);
        Assert.Contains("GetTickCount", pe);
        Assert.DoesNotContain("\"LoadLibraryA\"", pe);
        Assert.DoesNotContain("\"GetProcAddress\"", pe);
        Assert.DoesNotContain("\"CreateProcessA\"", pe);
    }

    [Fact]
    public void HostCompileOfHealthGuestImportsWs2AllowlistOnly()
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
            byte[] pe = HexToPe(root, hexRel);
            string ascii = Encoding.ASCII.GetString(pe);
            HashSet<string> imports = PeImports.Names(pe);
            Assert.Contains("ws2_32.dll", ascii.ToLowerInvariant());
            byte[] okCrlf = new byte[] { 5, 0, 0, 0, 0, 0, 0, 0, 0x20, 0x4F, 0x4B, 0x0D, 0x0A, 0 };
            byte[] okUs = new byte[] { 5, 0, 0, 0, 0, 0, 0, 0, 0x20, 0x4F, 0x4B, 0x1F, 0x1F, 0 };
            Assert.True(IndexOf(pe, okCrlf) >= 0, "parked txt_sp_ok must be CR LF");
            Assert.True(IndexOf(pe, okUs) < 0, "parked txt_sp_ok must not use 0x1F");
            Assert.Contains("\r\nConnection: close\r\n", ascii);
            Assert.Contains("WSAStartup", imports);
            Assert.Contains("GetTickCount", imports);
            Assert.DoesNotContain("LoadLibraryA", imports);
            Assert.DoesNotContain("GetProcAddress", imports);
            Assert.DoesNotContain("CreateProcessA", imports);
            Assert.DoesNotContain("VirtualProtect", imports);
        }
        finally
        {
            try { Directory.Delete(work, true); } catch (IOException) { }
        }
    }

    [Fact]
    public void HelloAndJsonOnlyKeepKernel32Iat()
    {
        string root = DualMode.FindRoot();
        string work = Path.Combine(root, "data", "native-net", Guid.NewGuid().ToString("N"));
        Directory.CreateDirectory(work);
        try
        {
            File.WriteAllText(Path.Combine(work, "hello.vire"), "define main\n  say \"hello from vire\"\nend\n");
            File.WriteAllText(Path.Combine(work, "json.vire"), "define main\n  say (json with {\"ok\": true})\nend\n");
            string helloSrc = Rel(work, "hello.vire");
            string helloHex = Rel(work, "hello.hex");
            string jsonSrc = Rel(work, "json.vire");
            string jsonHex = Rel(work, "json.hex");
            DualMode.Proc hello = DualMode.RunVire(root, new string[] { "compile-native.vire", helloSrc, helloHex }, root);
            DualMode.Proc json = DualMode.RunVire(root, new string[] { "compile-native.vire", jsonSrc, jsonHex }, root);
            Assert.Equal(0, hello.Code);
            Assert.Equal(0, json.Code);
            HashSet<string> helloImp = PeImports.Names(HexToPe(root, helloHex));
            HashSet<string> jsonImp = PeImports.Names(HexToPe(root, jsonHex));
            AssertStockKernel32(helloImp);
            AssertStockKernel32(jsonImp);
        }
        finally
        {
            try { Directory.Delete(work, true); } catch (IOException) { }
        }
    }

    [Fact]
    public void NonAllowlistedResolveIsInexpressible()
    {
        string root = DualMode.FindRoot();
        string work = Path.Combine(root, "data", "native-net", Guid.NewGuid().ToString("N"));
        Directory.CreateDirectory(work);
        try
        {
            File.WriteAllText(Path.Combine(work, "bad.vire"), "define main\n  LoadLibraryA with \"kernel32.dll\"\n  GetProcAddress with 0, \"CreateProcessA\"\nend\n");
            string src = Rel(work, "bad.vire");
            string hex = Rel(work, "bad.hex");
            DualMode.Proc compiled = DualMode.RunVire(root, new string[] { "compile-native.vire", src, hex }, root);
            Assert.NotEqual(0, compiled.Code);
            string text = DualMode.Norm(compiled.Out + " " + compiled.Err);
            Assert.Contains("there is no definition named", text);
        }
        finally
        {
            try { Directory.Delete(work, true); } catch (IOException) { }
        }
    }

    [Fact]
    public void GuestStringCreateProcessDoesNotEnterIat()
    {
        string root = DualMode.FindRoot();
        string work = Path.Combine(root, "data", "native-net", Guid.NewGuid().ToString("N"));
        Directory.CreateDirectory(work);
        try
        {
            File.WriteAllText(Path.Combine(work, "say.vire"), "define main\n  say \"CreateProcessA\"\nend\n");
            string src = Rel(work, "say.vire");
            string hex = Rel(work, "say.hex");
            DualMode.Proc compiled = DualMode.RunVire(root, new string[] { "compile-native.vire", src, hex }, root);
            Assert.Equal(0, compiled.Code);
            byte[] pe = HexToPe(root, hex);
            HashSet<string> imports = PeImports.Names(pe);
            Assert.DoesNotContain("CreateProcessA", imports);
            Assert.DoesNotContain("LoadLibraryA", imports);
            Assert.Contains("CreateProcessA", Encoding.ASCII.GetString(pe));
        }
        finally
        {
            try { Directory.Delete(work, true); } catch (IOException) { }
        }
    }

    static void AssertStockKernel32(HashSet<string> imports)
    {
        Assert.Contains("GetStdHandle", imports);
        Assert.Contains("WriteFile", imports);
        Assert.Contains("ExitProcess", imports);
        Assert.DoesNotContain("LoadLibraryA", imports);
        Assert.DoesNotContain("GetProcAddress", imports);
        Assert.DoesNotContain("CreateProcessA", imports);
        Assert.DoesNotContain("GetTickCount", imports);
        Assert.DoesNotContain("WSAStartup", imports);
        Assert.DoesNotContain("socket", imports);
    }

    static string Rel(string work, string name)
    {
        string root = DualMode.FindRoot();
        string rel = Path.GetRelativePath(root, Path.Combine(work, name)).Replace('\\', '/');
        return rel;
    }

    static byte[] HexToPe(string root, string hexRel)
    {
        string hex = File.ReadAllText(Path.Combine(root, hexRel.Replace('/', Path.DirectorySeparatorChar))).Trim();
        byte[] pe = new byte[hex.Length / 2];
        for (int i = 0; i < pe.Length; i++)
            pe[i] = byte.Parse(hex.Substring(i * 2, 2), NumberStyles.HexNumber, CultureInfo.InvariantCulture);
        return pe;
    }

    static int IndexOf(byte[] hay, byte[] needle)
    {
        for (int i = 0; i + needle.Length <= hay.Length; i++)
        {
            int k = 0;
            while (k < needle.Length && hay[i + k] == needle[k]) k++;
            if (k == needle.Length) return i;
        }
        return -1;
    }
}

static class PeImports
{
    public static HashSet<string> Names(byte[] pe)
    {
        var names = new HashSet<string>(StringComparer.Ordinal);
        int peOff = BitConverter.ToInt32(pe, 60);
        int magic = BitConverter.ToUInt16(pe, peOff + 24);
        int dirOff = magic == 0x20b ? peOff + 24 + 112 : peOff + 24 + 96;
        int importRva = BitConverter.ToInt32(pe, dirOff + 8);
        if (importRva == 0)
            return names;
        int importOff = RvaToOff(pe, peOff, importRva);
        for (int desc = importOff; desc + 20 <= pe.Length; desc += 20)
        {
            int lookup = BitConverter.ToInt32(pe, desc);
            int nameRva = BitConverter.ToInt32(pe, desc + 12);
            int iat = BitConverter.ToInt32(pe, desc + 16);
            if (lookup == 0 && nameRva == 0 && iat == 0)
                break;
            int thunkRva = lookup != 0 ? lookup : iat;
            int thunk = RvaToOff(pe, peOff, thunkRva);
            int stride = magic == 0x20b ? 8 : 4;
            for (int t = thunk; t + stride <= pe.Length; t += stride)
            {
                long entry = stride == 8 ? BitConverter.ToInt64(pe, t) : BitConverter.ToUInt32(pe, t);
                if (entry == 0)
                    break;
                if ((entry & (stride == 8 ? unchecked((long)0x8000000000000000) : 0x80000000)) != 0)
                    continue;
                int hint = RvaToOff(pe, peOff, (int)(entry & 0x7fffffff));
                names.Add(ReadZ(pe, hint + 2));
            }
        }
        return names;
    }

    static int RvaToOff(byte[] pe, int peOff, int rva)
    {
        int nsec = BitConverter.ToUInt16(pe, peOff + 6);
        int opt = BitConverter.ToUInt16(pe, peOff + 20);
        int sec = peOff + 24 + opt;
        for (int i = 0; i < nsec; i++)
        {
            int s = sec + i * 40;
            int vs = BitConverter.ToInt32(pe, s + 8);
            int va = BitConverter.ToInt32(pe, s + 12);
            int raw = BitConverter.ToInt32(pe, s + 20);
            int size = vs > 0 ? vs : BitConverter.ToInt32(pe, s + 16);
            if (rva >= va && rva < va + size)
                return raw + (rva - va);
        }
        throw new InvalidDataException("rva " + rva);
    }

    static string ReadZ(byte[] pe, int off)
    {
        int n = 0;
        while (off + n < pe.Length && pe[off + n] != 0)
            n++;
        return Encoding.ASCII.GetString(pe, off, n);
    }
}
