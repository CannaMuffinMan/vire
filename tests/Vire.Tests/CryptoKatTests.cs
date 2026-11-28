using System;
using System.Diagnostics;
using System.Globalization;
using System.IO;
using Xunit;

public class CryptoKatTests
{
    [Fact]
    public void GuestSha256DoesNotCallDigestBuiltin()
    {
        string src = File.ReadAllText(Path.Combine(DualMode.FindRoot(), "src", "rt-crypto.vire"));
        int wrap = src.IndexOf("define sha256_bytes with buf", StringComparison.Ordinal);
        Assert.True(wrap >= 0);
        string body = src.Substring(wrap, src.IndexOf("define sha256_hex", wrap) - wrap);
        Assert.Contains("sha_compress", body);
        Assert.Contains("sha_iv", body);
        Assert.DoesNotContain("digest with buf", body);
    }

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

    [Fact]
    public void HmacJwtCookieKatAndHostCompiledMatch()
    {
        string root = DualMode.FindRoot();
        DualMode.Proc run = DualMode.RunVire(root, new string[] { "crypto-prove.vire" }, root);
        Assert.True(run.Code == 0, run.Err + run.Out);
        string norm = DualMode.Norm(run.Out);
        Assert.Contains("FIPS 896 guest PASS", norm);
        Assert.Contains("FIPS 896 hash PASS", norm);
        Assert.Contains("boundary 55 PASS", norm);
        Assert.Contains("boundary 56 PASS", norm);
        Assert.Contains("boundary 63 PASS", norm);
        Assert.Contains("boundary 64 PASS", norm);
        Assert.Contains("boundary 65 PASS", norm);
        Assert.Contains("largest-fit 448 a PASS", norm);
        Assert.Contains("FIPS 1M guest skipped", norm);
        Assert.Contains("RFC4231 1 PASS", norm);
        Assert.Contains("RFC4231 2 PASS", norm);
        Assert.Contains("RFC4231 3 PASS", norm);
        Assert.Contains("RFC4231 4 PASS", norm);
        Assert.Contains("RFC4231 5 PASS", norm);
        Assert.Contains("RFC4231 6 PASS", norm);
        Assert.Contains("RFC4231 7 PASS", norm);
        Assert.Contains("RFC7515 A.1 PASS", norm);
        Assert.Contains("JWT hs256 jwt.io PASS", norm);
        Assert.Contains("ADV alg none REJECT", norm);
        Assert.Contains("cookie SID PASS", norm);
        Assert.Contains("cookie first-wins PASS", norm);
        Assert.Contains("set-cookie PASS", norm);
        Assert.Contains("cookie CR name REJECT", norm);
        Assert.Contains("CRYPTO PROVE pass", norm);
        File.Copy(Path.Combine(root, "session-prove.vire"), Path.Combine(root, "data", "session-prove.vire"), true);
        DualMode.Proc interp = DualMode.RunVire(root, new string[] { "session-prove.vire" }, root);
        DualMode.Proc compile = DualMode.RunVire(root, new string[] { "compiler.vire", "data/session-prove.vire", "data/session-prove.vc" }, root);
        Assert.True(compile.Code == 0, compile.Err + compile.Out);
        DualMode.Proc compiled = DualMode.RunVire(root, new string[] { "run", "data/session-prove.vc" }, root);
        Assert.Equal(interp.Code, compiled.Code);
        Assert.Equal(DualMode.Norm(interp.Out), DualMode.Norm(compiled.Out));
        Assert.Equal(0, interp.Code);
        Assert.Contains("b0344c61d8db38535ca8afceaf0bf12b881dc200c9833da726e9376c2e32cff7", DualMode.Norm(interp.Out));
        Assert.Contains("60e431591ee0b67f0d8a26aacbf5b77f8e0bc6213728c5140546040f0ee37f54", DualMode.Norm(interp.Out));
        Assert.Contains("9b09ffa71b942fcb27635fbcd5b0e944bfdc63644f0713938a7f51535c3a35e2", DualMode.Norm(interp.Out));
        Assert.Contains("eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.", DualMode.Norm(interp.Out));
        Assert.Contains("SID=31d4d96e407aad42", DualMode.Norm(interp.Out));
        Assert.Contains("SID=x; Path=/", DualMode.Norm(interp.Out));
        Assert.Contains("bad", DualMode.Norm(interp.Out));
    }

    [Fact]
    public void SessionPrimitivesHostMatchesNativeElf()
    {
        string root = DualMode.FindRoot();
        DualMode.Proc host = DualMode.RunVire(root, new string[] { "session-prove.vire" }, root);
        Assert.True(host.Code == 0, host.Err + host.Out);
        string work = Path.Combine(root, "data", "session-native", Guid.NewGuid().ToString("N"));
        Directory.CreateDirectory(work);
        try
        {
            File.Copy(Path.Combine(root, "session-prove.vire"), Path.Combine(root, "data", "session-prove.vire"), true);
            File.Copy(Path.Combine(root, "src", "rt-crypto.vire"), Path.Combine(root, "data", "src", "rt-crypto.vire"), true);
            string srcRel = "data/session-prove.vire";
            string hexRel = Rel(root, Path.Combine(work, "session-prove.hex"));
            DualMode.Proc compiled = DualMode.RunVire(root, new string[] { "compile-native.vire", srcRel, hexRel }, root);
            Assert.True(compiled.Code == 0, compiled.Out + compiled.Err);
            byte[] image = HexToBin(root, hexRel);
            if (!OperatingSystem.IsLinux())
            {
                Assert.Equal((byte)'M', image[0]);
                Assert.Equal((byte)'Z', image[1]);
                return;
            }
            Assert.Equal(0x7f, image[0]);
            Assert.Equal((byte)'F', image[3]);
            string elf = Path.Combine(work, "session-prove.elf");
            File.WriteAllBytes(elf, image);
            try { File.SetUnixFileMode(elf, UnixFileMode.UserRead | UnixFileMode.UserWrite | UnixFileMode.UserExecute); } catch (PlatformNotSupportedException) { }
            ProcessStartInfo info = new ProcessStartInfo();
            info.FileName = elf;
            info.WorkingDirectory = work;
            info.RedirectStandardOutput = true;
            info.RedirectStandardError = true;
            info.UseShellExecute = false;
            Process process = Process.Start(info);
            string stdout = process.StandardOutput.ReadToEnd();
            string stderr = process.StandardError.ReadToEnd();
            Assert.True(process.WaitForExit(60000), "native session-prove timed out");
            Assert.True(process.ExitCode == 0, stderr + stdout);
            Assert.Equal(DualMode.Norm(host.Out), DualMode.Norm(stdout));
        }
        finally
        {
            try { Directory.Delete(work, true); } catch (IOException) { }
        }
    }

    static string Rel(string root, string path)
    {
        return Path.GetRelativePath(root, path).Replace('\\', '/');
    }

    static byte[] HexToBin(string root, string hexRel)
    {
        string hex = File.ReadAllText(Path.Combine(root, hexRel.Replace('/', Path.DirectorySeparatorChar))).Trim();
        byte[] bin = new byte[hex.Length / 2];
        for (int i = 0; i < bin.Length; i++)
            bin[i] = byte.Parse(hex.Substring(i * 2, 2), NumberStyles.HexNumber, CultureInfo.InvariantCulture);
        return bin;
    }
}
