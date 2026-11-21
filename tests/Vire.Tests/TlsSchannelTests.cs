using System;
using System.Globalization;
using System.IO;
using System.Text;
using Xunit;

public class TlsSchannelTests
{
    [Fact]
    public void NativePeTlsGuestImportsSchannelAllowlist()
    {
        string root = DualMode.FindRoot();
        string work = Path.Combine(root, "data", "tls-schannel", Guid.NewGuid().ToString("N"));
        Directory.CreateDirectory(work);
        try
        {
            File.WriteAllText(Path.Combine(work, "guest.vire"),
                "define main\n  tls_connect with \"127.0.0.1\", 443, \"localhost\", \"\"\nend\n");
            string srcRel = Rel(work, "guest.vire");
            string hexRel = Rel(work, "guest.hex");
            DualMode.Proc compiled = DualMode.RunVire(
                root,
                new string[] { "compile-native.vire", srcRel, hexRel, "pe" },
                root);
            Assert.True(compiled.Code == 0, DualMode.Norm(compiled.Out + " " + compiled.Err));
            Assert.Contains("compiled", DualMode.Norm(compiled.Out));
            byte[] pe = HexToBytes(root, hexRel);
            Assert.Equal((byte)'M', pe[0]);
            Assert.Equal((byte)'Z', pe[1]);
            string ascii = Encoding.ASCII.GetString(pe);
            Assert.Contains("secur32.dll", ascii.ToLowerInvariant());
            Assert.Contains("crypt32.dll", ascii.ToLowerInvariant());
            Assert.Contains("ws2_32.dll", ascii.ToLowerInvariant());
            Assert.Contains("Microsoft Unified Security Protocol Provider", ascii);
            Assert.DoesNotContain("libssl.so.3", ascii);
            var names = PeImports.Names(pe);
            Assert.Contains("AcquireCredentialsHandleA", names);
            Assert.Contains("InitializeSecurityContextA", names);
            Assert.Contains("AcceptSecurityContext", names);
            Assert.Contains("EncryptMessage", names);
            Assert.Contains("DecryptMessage", names);
            Assert.Contains("PFXImportCertStore", names);
            Assert.DoesNotContain("LoadLibraryA", names);
            Assert.DoesNotContain("GetProcAddress", names);
            Assert.DoesNotContain("CreateProcessA", names);
            Assert.True(pe.Length > 64);
            int e = BitConverter.ToInt32(pe, 0x3c);
            int oh = e + 24;
            Assert.Equal(0x20b, BitConverter.ToUInt16(pe, oh));
            uint textChars = BitConverter.ToUInt32(pe, 432 + 36);
            Assert.Equal(0x60000020u, textChars);
            Assert.Equal(0, (int)(textChars & 0x80000000));
        }
        finally
        {
            try { Directory.Delete(work, true); } catch (IOException) { }
        }
    }

    [Fact]
    public void NativePeTlsWrapGuestImportsSchannelAllowlist()
    {
        string root = DualMode.FindRoot();
        string work = Path.Combine(root, "data", "tls-schannel", Guid.NewGuid().ToString("N"));
        Directory.CreateDirectory(work);
        try
        {
            File.WriteAllText(Path.Combine(work, "guest.vire"),
                "define main\n  tls_wrap with 1, \"localhost\", \"\", 1\nend\n");
            string srcRel = Rel(work, "guest.vire");
            string hexRel = Rel(work, "guest.hex");
            DualMode.Proc compiled = DualMode.RunVire(
                root,
                new string[] { "compile-native.vire", srcRel, hexRel, "pe" },
                root);
            Assert.True(compiled.Code == 0, DualMode.Norm(compiled.Out + " " + compiled.Err));
            Assert.Contains("compiled", DualMode.Norm(compiled.Out));
            byte[] pe = HexToBytes(root, hexRel);
            Assert.Equal((byte)'M', pe[0]);
            Assert.Equal((byte)'Z', pe[1]);
            string ascii = Encoding.ASCII.GetString(pe);
            Assert.Contains("secur32.dll", ascii.ToLowerInvariant());
            Assert.Contains("crypt32.dll", ascii.ToLowerInvariant());
            Assert.DoesNotContain("libssl.so.3", ascii);
            var names = PeImports.Names(pe);
            Assert.Contains("InitializeSecurityContextA", names);
            Assert.Contains("EncryptMessage", names);
            Assert.DoesNotContain("LoadLibraryA", names);
            Assert.DoesNotContain("GetProcAddress", names);
            Assert.Contains("rt_tls_wrap", File.ReadAllText(Path.Combine(root, "src", "rt-tls-pe.vire")));
        }
        finally
        {
            try { Directory.Delete(work, true); } catch (IOException) { }
        }
    }

    [Fact]
    public void NativeElfTlsGuestDoesNotImportSchannel()
    {
        string root = DualMode.FindRoot();
        string work = Path.Combine(root, "data", "tls-schannel", Guid.NewGuid().ToString("N"));
        Directory.CreateDirectory(work);
        try
        {
            File.WriteAllText(Path.Combine(work, "guest.vire"),
                "define main\n  tls_connect with \"127.0.0.1\", 443, \"localhost\", \"\"\nend\n");
            string srcRel = Rel(work, "guest.vire");
            string hexRel = Rel(work, "guest.hex");
            DualMode.Proc compiled = DualMode.RunVire(
                root,
                new string[] { "compile-native.vire", srcRel, hexRel, "elf" },
                root);
            Assert.True(compiled.Code == 0, DualMode.Norm(compiled.Out + " " + compiled.Err));
            byte[] elf = HexToBytes(root, hexRel);
            Assert.Equal(0x7f, elf[0]);
            string ascii = Encoding.ASCII.GetString(elf);
            Assert.Contains("libssl.so.3", ascii);
            Assert.DoesNotContain("secur32.dll", ascii);
            Assert.DoesNotContain("AcquireCredentialsHandleA", ascii);
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

    static byte[] HexToBytes(string root, string hexRel)
    {
        string hex = File.ReadAllText(Path.Combine(root, hexRel.Replace('/', Path.DirectorySeparatorChar))).Trim();
        byte[] pe = new byte[hex.Length / 2];
        for (int i = 0; i < pe.Length; i++)
            pe[i] = byte.Parse(hex.Substring(i * 2, 2), NumberStyles.HexNumber, CultureInfo.InvariantCulture);
        return pe;
    }
}
