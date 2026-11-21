using System;
using System.Diagnostics;
using System.Globalization;
using System.IO;
using Xunit;

public class AesGcmKatTests
{
    [Fact]
    public void GuestAes256GcmMatchesNistAndRejectsTamper()
    {
        string root = DualMode.FindRoot();
        string dll = typeof(Program).Assembly.Location;
        string dotnet = Environment.GetEnvironmentVariable("DOTNET_HOST_PATH");
        if (string.IsNullOrEmpty(dotnet)) dotnet = "dotnet";
        ProcessStartInfo info = new ProcessStartInfo();
        info.FileName = dotnet;
        info.Arguments = "exec \"" + dll + "\" \"aes-gcm-prove.vire\"";
        info.WorkingDirectory = root;
        info.RedirectStandardOutput = true;
        info.RedirectStandardError = true;
        info.UseShellExecute = false;
        info.Environment["VIRE_BUDGET"] = "5000000";
        Process process = Process.Start(info);
        string stdout = process.StandardOutput.ReadToEnd();
        string stderr = process.StandardError.ReadToEnd();
        Assert.True(process.WaitForExit(180000), "aes-gcm-prove timed out");
        Assert.True(process.ExitCode == 0, stderr + stdout);
        string norm = DualMode.Norm(stdout);
        Assert.Contains("NIST SP800-38D empty TAG PASS 530f8afbc74536b9a963b4f1c4cb738b", norm);
        Assert.Contains("NIST SP800-38D 1block CT PASS cea7403d4d606b6e074ec5d3baf39d18", norm);
        Assert.Contains("NIST SP800-38D 1block TAG PASS d0d1c8a799996bf0265b98b5d48ab919", norm);
        Assert.Contains("NIST AAD TAG PASS ae9b1771dba9cf62b39be017940330b4", norm);
        Assert.Contains("WYCHEPROOF tag-tamper REJECT", norm);
        Assert.Contains("WYCHEPROOF tag-tamper no-plaintext PASS", norm);
        Assert.Contains("WYCHEPROOF aad-tamper REJECT", norm);
        Assert.Contains("WYCHEPROOF aad-tamper no-plaintext PASS", norm);
        Assert.Contains("WYCHEPROOF truncated-tag REJECT", norm);
        Assert.Contains("NONCE 11 REJECT", norm);
        Assert.Contains("NONCE 13 REJECT", norm);
        Assert.Contains("SBOX 0 PASS 99", norm);
        Assert.Contains("SBOX 1 PASS 124", norm);
        Assert.Contains("SBOX 255 PASS 22", norm);
        Assert.Contains("not a CPU timing barrier", norm);
        Assert.Contains("AES-GCM PROVE pass", norm);
    }

    [Fact]
    public void GuestAes256GcmSourceHasNoSecretDependentSboxOrGhashSkip()
    {
        string root = DualMode.FindRoot();
        string src = File.ReadAllText(Path.Combine(root, "src", "rt-aes.vire"));
        Assert.DoesNotContain("sbox at", src, StringComparison.Ordinal);
        Assert.DoesNotContain("if d >= 256", src, StringComparison.Ordinal);
        Assert.DoesNotContain("if flag == 1", src, StringComparison.Ordinal);
        Assert.DoesNotContain("if lsb == 1", src, StringComparison.Ordinal);
        Assert.DoesNotContain("if a != b", src, StringComparison.Ordinal);
        Assert.Contains("aesSboxByte", src, StringComparison.Ordinal);
        Assert.Contains("gcmXorMasked", src, StringComparison.Ordinal);
        Assert.Contains("aesBitXor", src, StringComparison.Ordinal);
        Assert.Contains("not a timing barrier", src, StringComparison.OrdinalIgnoreCase);
    }

    [Fact]
    public void GuestAes256GcmHostMatchesNativeElfOnLinux()
    {
        if (!OperatingSystem.IsLinux()) return;
        string root = DualMode.FindRoot();
        DualMode.Proc host = DualMode.RunVire(root, new string[] { "aes-gcm-prove.vire" }, root);
        Assert.True(host.Code == 0, host.Err + host.Out);
        string dll = typeof(Program).Assembly.Location;
        string dotnet = Environment.GetEnvironmentVariable("DOTNET_HOST_PATH");
        if (string.IsNullOrEmpty(dotnet)) dotnet = "dotnet";
        Directory.CreateDirectory(Path.Combine(root, "data"));
        string lib = File.ReadAllText(Path.Combine(root, "src", "rt-aes.vire"));
        string prove = File.ReadAllText(Path.Combine(root, "aes-gcm-prove.vire"));
        prove = prove.Replace("use \"src/rt-aes.vire\"", "", StringComparison.Ordinal);
        File.WriteAllText(Path.Combine(root, "data", "aes-gcm-prove.vire"), lib + "\n" + prove);
        ProcessStartInfo compileInfo = new ProcessStartInfo();
        compileInfo.FileName = dotnet;
        compileInfo.Arguments = "exec \"" + dll + "\" \"--compiler\" \"compile-native.vire\" \"data/aes-gcm-prove.vire\" \"data/aes-gcm-prove.hex\"";
        compileInfo.WorkingDirectory = root;
        compileInfo.RedirectStandardOutput = true;
        compileInfo.RedirectStandardError = true;
        compileInfo.UseShellExecute = false;
        compileInfo.Environment.Remove("VIRE_BUDGET");
        Process compile = Process.Start(compileInfo);
        string compileOut = compile.StandardOutput.ReadToEnd();
        string compileErr = compile.StandardError.ReadToEnd();
        Assert.True(compile.WaitForExit(400000), "compile-native aes-gcm-prove timed out");
        Assert.True(compile.ExitCode == 0, compileErr + compileOut);
        Assert.Contains("compiled", DualMode.Norm(compileOut));
        string hexPath = Path.Combine(root, "data", "aes-gcm-prove.hex");
        string hex = File.ReadAllText(hexPath).Trim();
        byte[] elf = new byte[hex.Length / 2];
        for (int i = 0; i < elf.Length; i++)
            elf[i] = byte.Parse(hex.Substring(i * 2, 2), NumberStyles.HexNumber, CultureInfo.InvariantCulture);
        Assert.Equal(0x7f, elf[0]);
        Assert.Equal((byte)'E', elf[1]);
        string elfPath = Path.Combine(root, "data", "aes-gcm-prove.elf");
        File.WriteAllBytes(elfPath, elf);
        File.SetUnixFileMode(elfPath, UnixFileMode.UserRead | UnixFileMode.UserWrite | UnixFileMode.UserExecute);
        ProcessStartInfo run = new ProcessStartInfo();
        run.FileName = elfPath;
        run.WorkingDirectory = root;
        run.RedirectStandardOutput = true;
        run.RedirectStandardError = true;
        run.UseShellExecute = false;
        Process process = Process.Start(run);
        string stdout = process.StandardOutput.ReadToEnd();
        string stderr = process.StandardError.ReadToEnd();
        Assert.True(process.WaitForExit(180000), "aes-gcm ELF timed out");
        Assert.True(process.ExitCode == 0, stderr + stdout);
        Assert.Equal(DualMode.Norm(host.Out).Trim(), DualMode.Norm(stdout).Trim());
        Assert.Contains("AES-GCM PROVE pass", DualMode.Norm(stdout));
    }
}
