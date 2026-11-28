using System;
using System.Globalization;
using System.IO;
using System.Net;
using System.Security.Cryptography;
using System.Security.Cryptography.X509Certificates;
using System.Text;
using Xunit;

public class TlsEndPointTests
{
    [Fact]
    public void HostPicksSha384AndSha512PerRfc5929()
    {
        using X509Certificate2 sha256 = MakeCert(HashAlgorithmName.SHA256);
        using X509Certificate2 sha384 = MakeCert(HashAlgorithmName.SHA384);
        using X509Certificate2 sha512 = MakeCert(HashAlgorithmName.SHA512);
        Assert.Equal(32, VireTls.Rfc5929EndPoint(sha256.RawData).Length);
        Assert.Equal(48, VireTls.Rfc5929EndPoint(sha384.RawData).Length);
        Assert.Equal(64, VireTls.Rfc5929EndPoint(sha512.RawData).Length);
        Assert.Equal(SHA384.HashData(sha384.RawData), VireTls.Rfc5929EndPoint(sha384.RawData));
        Assert.Equal(SHA512.HashData(sha512.RawData), VireTls.Rfc5929EndPoint(sha512.RawData));
    }

    [Fact]
    public void ElfTlsEndPointMatchesHostOnSha384AndSha512Leaves()
    {
        string root = DualMode.FindRoot();
        RunLeaf(root, HashAlgorithmName.SHA384, 48);
        RunLeaf(root, HashAlgorithmName.SHA512, 64);
    }

    [Fact]
    public void PackedPeBlobExportsRemoteCertContext()
    {
        string root = DualMode.FindRoot();
        string pe = File.ReadAllText(Path.Combine(root, "src", "rt-tls-pe.vire"));
        Assert.Contains("rt_tls_peer_cert", pe);
        Assert.Contains("rt_tls_end_point", pe);
        Assert.Contains("iat_fct", pe);
        Assert.Contains("iat_chc", pe);
        Assert.Contains("tls_ep_kind", pe);
        Assert.Contains("tls_peerctx", pe);
        Assert.Contains("emitU32 with image, 83", pe);
        Assert.Contains("32781", pe);
        Assert.Contains("32782", pe);
        string names = File.ReadAllText(Path.Combine(root, "src", "rt-tls.vire"));
        Assert.Contains("rt_tls_peer_cert", names);
        Assert.Contains("SHA384", names);
        Assert.Contains("SHA512", names);
        Assert.DoesNotContain("pin with labels, \"rt_tls_peer_cert\", image\n  emitPro with image\n  emitFail", names.Replace("\r\n", "\n"));
        string blob = File.ReadAllText(Path.Combine(root, "src", "rt-tls-pe-blob.txt"));
        Assert.Contains("rt_tls_peer_cert", File.ReadAllText(Path.Combine(root, "src", "rt-tls-pe-names.txt")));
        Assert.Contains("rt_tls_end_point", File.ReadAllText(Path.Combine(root, "src", "rt-tls-elf-names.txt")));
        Assert.Contains("iat_sha384", File.ReadAllText(Path.Combine(root, "src", "rt-tls-elf-names.txt")));
        Assert.Contains("iat_sha512", File.ReadAllText(Path.Combine(root, "src", "rt-tls-elf-names.txt")));
        Assert.True(blob.Length > 8000, blob.Length.ToString());
        string work = Path.Combine(root, "data", "tls-endpoint", Guid.NewGuid().ToString("N"));
        Directory.CreateDirectory(work);
        File.WriteAllText(Path.Combine(work, "ep.vire"),
            "define main\n  say (length with (tls_end_point with \"abc\"))\nend\n");
        DualMode.Proc compiled = DualMode.RunVire(
            root,
            new string[] { "compile-native.vire", Rel(root, work, "ep.vire"), Rel(root, work, "ep.hex"), "pe" },
            root);
        Assert.True(compiled.Code == 0, compiled.Err + compiled.Out);
        byte[] peBin = HexToBytes(root, Rel(root, work, "ep.hex"));
        string ascii = Encoding.ASCII.GetString(peBin);
        Assert.Contains("CryptHashCertificate", ascii);
        Assert.DoesNotContain("bcrypt.dll", ascii.ToLowerInvariant());
    }

    static void RunLeaf(string root, HashAlgorithmName hash, int want)
    {
        using X509Certificate2 cert = MakeCert(hash);
        byte[] der = cert.RawData;
        byte[] expect = VireTls.Rfc5929EndPoint(der);
        Assert.Equal(want, expect.Length);
        string work = Path.Combine(root, "data", "tls-endpoint", Guid.NewGuid().ToString("N"));
        Directory.CreateDirectory(work);
        StringBuilder xs = new StringBuilder();
        xs.Append("define main\n  let xs be [");
        for (int i = 0; i < der.Length; i++)
        {
            if (i > 0) xs.Append(", ");
            xs.Append(der[i].ToString(CultureInfo.InvariantCulture));
        }
        xs.Append("]\n  let der be \"\"\n  let i be 0\n  while i < (length with xs)\n    let der be der + (chr with (xs at i))\n    let i be i + 1\n  end\n  let ep be tls_end_point with der\n  say (length with ep)\nend\n");
        File.WriteAllText(Path.Combine(work, "ep.vire"), xs.ToString());
        string srcRel = Rel(root, work, "ep.vire");
        DualMode.Proc host = DualMode.RunVire(root, new string[] { srcRel }, root);
        Assert.True(host.Code == 0, host.Err + host.Out);
        Assert.Contains(want.ToString(CultureInfo.InvariantCulture), DualMode.Norm(host.Out));
        string hexRel = Rel(root, work, "ep.hex");
        DualMode.Proc compiled = DualMode.RunVire(root, new string[] { "compile-native.vire", srcRel, hexRel, "elf" }, root);
        Assert.True(compiled.Code == 0, compiled.Err + compiled.Out);
        byte[] elf = HexToBytes(root, hexRel);
        Assert.Equal(0x7f, elf[0]);
        string ascii = Encoding.ASCII.GetString(elf);
        Assert.Contains("SHA384", ascii);
        Assert.Contains("SHA512", ascii);
        if (!OperatingSystem.IsLinux()) return;
        string elfPath = Path.Combine(work, "ep.elf");
        File.WriteAllBytes(elfPath, elf);
        try { File.SetUnixFileMode(elfPath, UnixFileMode.UserRead | UnixFileMode.UserWrite | UnixFileMode.UserExecute); }
        catch (Exception) { }
        DualMode.Proc native = RunElf(elfPath, work);
        Assert.True(native.Code == 0, native.Err + native.Out);
        Assert.Equal(DualMode.Norm(host.Out).Trim(), DualMode.Norm(native.Out).Trim());
    }

    static DualMode.Proc RunElf(string path, string cwd)
    {
        System.Diagnostics.ProcessStartInfo info = new System.Diagnostics.ProcessStartInfo();
        info.FileName = path;
        info.WorkingDirectory = cwd;
        info.RedirectStandardOutput = true;
        info.RedirectStandardError = true;
        info.UseShellExecute = false;
        System.Diagnostics.Process process = System.Diagnostics.Process.Start(info);
        string stdout = process.StandardOutput.ReadToEnd();
        string stderr = process.StandardError.ReadToEnd();
        Assert.True(process.WaitForExit(30000), "elf tls_end_point timed out");
        return new DualMode.Proc(process.ExitCode, stdout, stderr);
    }

    static X509Certificate2 MakeCert(HashAlgorithmName hash)
    {
        using RSA rsa = RSA.Create(2048);
        CertificateRequest req = new CertificateRequest("CN=localhost", rsa, hash, RSASignaturePadding.Pkcs1);
        SubjectAlternativeNameBuilder san = new SubjectAlternativeNameBuilder();
        san.AddDnsName("localhost");
        san.AddIpAddress(IPAddress.Loopback);
        req.CertificateExtensions.Add(san.Build());
        using X509Certificate2 cert = req.CreateSelfSigned(DateTimeOffset.UtcNow.AddHours(-1), DateTimeOffset.UtcNow.AddDays(1));
        return X509CertificateLoader.LoadCertificate(cert.RawData);
    }

    static string Rel(string root, string work, string name)
    {
        return Path.GetRelativePath(root, Path.Combine(work, name)).Replace('\\', '/');
    }

    static byte[] HexToBytes(string root, string hexRel)
    {
        string hex = File.ReadAllText(Path.Combine(root, hexRel.Replace('/', Path.DirectorySeparatorChar))).Trim();
        byte[] raw = new byte[hex.Length / 2];
        for (int i = 0; i < raw.Length; i++)
            raw[i] = byte.Parse(hex.Substring(i * 2, 2), NumberStyles.HexNumber, CultureInfo.InvariantCulture);
        return raw;
    }
}
