using System;
using System.Diagnostics;
using System.Globalization;
using System.IO;
using Xunit;

public class KdfKatTests
{
    [Fact]
    public void GuestBcryptCost4MatchesPublishedVectors()
    {
        string root = DualMode.FindRoot();
        string dll = typeof(Program).Assembly.Location;
        string dotnet = Environment.GetEnvironmentVariable("DOTNET_HOST_PATH");
        if (string.IsNullOrEmpty(dotnet)) dotnet = "dotnet";
        ProcessStartInfo info = new ProcessStartInfo();
        info.FileName = dotnet;
        info.Arguments = "exec \"" + dll + "\" \"kdf-prove.vire\"";
        info.WorkingDirectory = root;
        info.RedirectStandardOutput = true;
        info.RedirectStandardError = true;
        info.UseShellExecute = false;
        info.Environment["VIRE_BUDGET"] = "5000000";
        Process process = Process.Start(info);
        string stdout = process.StandardOutput.ReadToEnd();
        string stderr = process.StandardError.ReadToEnd();
        Assert.True(process.WaitForExit(400000), "kdf-prove timed out");
        Assert.True(process.ExitCode == 0, stderr + stdout);
        string norm = DualMode.Norm(stdout);
        Assert.Contains("BCRYPT password cost4 PASS", norm);
        Assert.Contains("BCRYPT empty cost4 PASS", norm);
        Assert.Contains("BCRYPT utf8 cost4 PASS", norm);
        Assert.Contains("BCRYPT 72-byte truncation PASS", norm);
        Assert.Contains("BCRYPT wrong password REJECT", norm);
        Assert.Contains("not a CPU timing barrier", norm);
        Assert.Contains("KDF PROVE pass", norm);
    }

    [Fact]
    public void GuestPbkdf2Rfc7914AndRfc6070Match()
    {
        string root = DualMode.FindRoot();
        string dll = typeof(Program).Assembly.Location;
        string dotnet = Environment.GetEnvironmentVariable("DOTNET_HOST_PATH");
        if (string.IsNullOrEmpty(dotnet)) dotnet = "dotnet";
        ProcessStartInfo info = new ProcessStartInfo();
        info.FileName = dotnet;
        info.Arguments = "exec \"" + dll + "\" \"pbkdf2-prove.vire\"";
        info.WorkingDirectory = root;
        info.RedirectStandardOutput = true;
        info.RedirectStandardError = true;
        info.UseShellExecute = false;
        info.Environment["VIRE_BUDGET"] = "5000000";
        Process process = Process.Start(info);
        string stdout = process.StandardOutput.ReadToEnd();
        string stderr = process.StandardError.ReadToEnd();
        Assert.True(process.WaitForExit(400000), "pbkdf2-prove timed out");
        Assert.True(process.ExitCode == 0, stderr + stdout);
        string norm = DualMode.Norm(stdout);
        Assert.Contains("RFC7914 11 c=1 PASS", norm);
        Assert.Contains("RFC6070-SHA256 c=1 PASS", norm);
        Assert.Contains("RFC6070-SHA256 c=2 PASS", norm);
        Assert.Contains("RFC6070-SHA256 c=4096 PASS", norm);
        Assert.Contains("RFC7914 11 c=80000 PASS", norm);
        Assert.Contains("PBKDF2 ct_eq same PASS", norm);
        Assert.Contains("PBKDF2 wrong password REJECT", norm);
        Assert.Contains("FCG login dk32 PASS", norm);
        Assert.Contains("FCG login verify PASS", norm);
        Assert.Contains("PBKDF2 rounds 0 REJECT", norm);
        Assert.Contains("not a CPU timing barrier", norm);
        Assert.Contains("PBKDF2 PROVE pass", norm);
    }

    [Fact]
    public void Pbkdf2HostMatchesNativeElf()
    {
        string root = DualMode.FindRoot();
        string dll = typeof(Program).Assembly.Location;
        string dotnet = Environment.GetEnvironmentVariable("DOTNET_HOST_PATH");
        if (string.IsNullOrEmpty(dotnet)) dotnet = "dotnet";
        ProcessStartInfo hostInfo = VireInfo(dotnet, dll, root, "\"pbkdf2-prove.vire\"");
        Process host = Process.Start(hostInfo);
        string hostOut = host.StandardOutput.ReadToEnd();
        string hostErr = host.StandardError.ReadToEnd();
        Assert.True(host.WaitForExit(400000), "host pbkdf2-prove timed out");
        Assert.True(host.ExitCode == 0, hostErr + hostOut);
        string work = Path.Combine(root, "data", "pbkdf2-native", Guid.NewGuid().ToString("N"));
        Directory.CreateDirectory(work);
        try
        {
            File.Copy(Path.Combine(root, "src", "rt-crypto.vire"), Path.Combine(root, "data", "src", "rt-crypto.vire"), true);
            File.Copy(Path.Combine(root, "pbkdf2-prove.vire"), Path.Combine(root, "data", "pbkdf2-prove.vire"), true);
            ProcessStartInfo compileInfo = VireInfo(dotnet, dll, root, "--compiler \"compile-native.vire\" \"data/pbkdf2-prove.vire\" \"data/pbkdf2-native/" + Path.GetFileName(work) + "/pbkdf2-prove.hex\"");
            compileInfo.Environment.Remove("VIRE_BUDGET");
            Process compiled = Process.Start(compileInfo);
            string compileOut = compiled.StandardOutput.ReadToEnd();
            string compileErr = compiled.StandardError.ReadToEnd();
            Assert.True(compiled.WaitForExit(400000), "compile-native pbkdf2-prove timed out");
            Assert.True(compiled.ExitCode == 0, compileOut + compileErr);
            string hexRel = "data/pbkdf2-native/" + Path.GetFileName(work) + "/pbkdf2-prove.hex";
            byte[] image = HexToBin(root, hexRel);
            if (!OperatingSystem.IsLinux())
            {
                Assert.Equal((byte)'M', image[0]);
                Assert.Equal((byte)'Z', image[1]);
                return;
            }
            Assert.Equal(0x7f, image[0]);
            Assert.Equal((byte)'F', image[3]);
            string elf = Path.Combine(work, "pbkdf2-prove.elf");
            File.WriteAllBytes(elf, image);
            try { File.SetUnixFileMode(elf, UnixFileMode.UserRead | UnixFileMode.UserWrite | UnixFileMode.UserExecute); } catch (PlatformNotSupportedException) { }
            ProcessStartInfo run = new ProcessStartInfo();
            run.FileName = elf;
            run.WorkingDirectory = work;
            run.RedirectStandardOutput = true;
            run.RedirectStandardError = true;
            run.UseShellExecute = false;
            Process process = Process.Start(run);
            string stdout = process.StandardOutput.ReadToEnd();
            string stderr = process.StandardError.ReadToEnd();
            Assert.True(process.WaitForExit(400000), "native pbkdf2-prove timed out");
            Assert.True(process.ExitCode == 0, stderr + stdout);
            Assert.Equal(DualMode.Norm(hostOut), DualMode.Norm(stdout));
        }
        finally
        {
            try { Directory.Delete(work, true); } catch (IOException) { }
        }
    }

    [Fact]
    public void Pbkdf2Rfc7914EightyThousandNativeElfOnly()
    {
        string root = DualMode.FindRoot();
        string dll = typeof(Program).Assembly.Location;
        string dotnet = Environment.GetEnvironmentVariable("DOTNET_HOST_PATH");
        if (string.IsNullOrEmpty(dotnet)) dotnet = "dotnet";
        ProcessStartInfo hostInfo = VireInfo(dotnet, dll, root, "\"pbkdf2-80k.vire\"");
        Process host = Process.Start(hostInfo);
        string hostOut = host.StandardOutput.ReadToEnd();
        string hostErr = host.StandardError.ReadToEnd();
        Assert.True(host.WaitForExit(120000), "host 80k wait");
        Assert.True(host.ExitCode == 0, hostErr + hostOut);
        Assert.Contains("RFC7914 11 c=80000 PASS", DualMode.Norm(hostOut));
        if (!OperatingSystem.IsLinux())
        {
            return;
        }
        File.Copy(Path.Combine(root, "src", "rt-crypto.vire"), Path.Combine(root, "data", "src", "rt-crypto.vire"), true);
        File.Copy(Path.Combine(root, "pbkdf2-80k.vire"), Path.Combine(root, "data", "pbkdf2-80k.vire"), true);
        string work = Path.Combine(root, "data", "pbkdf2-80k-native", Guid.NewGuid().ToString("N"));
        Directory.CreateDirectory(work);
        try
        {
            string hexRel = Rel(root, Path.Combine(work, "pbkdf2-80k.hex"));
            ProcessStartInfo compileInfo = VireInfo(dotnet, dll, root, "--compiler \"compile-native.vire\" \"data/pbkdf2-80k.vire\" \"" + hexRel + "\"");
            compileInfo.Environment.Remove("VIRE_BUDGET");
            Process compiled = Process.Start(compileInfo);
            string compileOut = compiled.StandardOutput.ReadToEnd();
            string compileErr = compiled.StandardError.ReadToEnd();
            Assert.True(compiled.WaitForExit(400000), "compile-native pbkdf2-80k timed out");
            Assert.True(compiled.ExitCode == 0, compileOut + compileErr);
            byte[] image = HexToBin(root, hexRel);
            Assert.Equal(0x7f, image[0]);
            string elf = Path.Combine(work, "pbkdf2-80k.elf");
            File.WriteAllBytes(elf, image);
            try { File.SetUnixFileMode(elf, UnixFileMode.UserRead | UnixFileMode.UserWrite | UnixFileMode.UserExecute); } catch (PlatformNotSupportedException) { }
            ProcessStartInfo run = new ProcessStartInfo();
            run.FileName = elf;
            run.WorkingDirectory = work;
            run.RedirectStandardOutput = true;
            run.RedirectStandardError = true;
            run.UseShellExecute = false;
            Process process = Process.Start(run);
            string stdout = process.StandardOutput.ReadToEnd();
            string stderr = process.StandardError.ReadToEnd();
            Assert.True(process.WaitForExit(600000), "native pbkdf2-80k timed out");
            Assert.True(process.ExitCode == 0, stderr + stdout);
            Assert.Contains("RFC7914 11 c=80000 PASS", DualMode.Norm(stdout));
        }
        finally
        {
            try { Directory.Delete(work, true); } catch (IOException) { }
        }
    }

    static ProcessStartInfo VireInfo(string dotnet, string dll, string root, string extra)
    {
        ProcessStartInfo info = new ProcessStartInfo();
        info.FileName = dotnet;
        info.Arguments = "exec \"" + dll + "\" " + extra;
        info.WorkingDirectory = root;
        info.RedirectStandardOutput = true;
        info.RedirectStandardError = true;
        info.UseShellExecute = false;
        info.Environment["VIRE_BUDGET"] = "5000000";
        info.Environment["VIRE_HEADLESS"] = "1";
        return info;
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
