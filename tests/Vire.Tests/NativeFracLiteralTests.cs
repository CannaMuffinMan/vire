using System;
using System.Diagnostics;
using System.IO;
using Xunit;

public class NativeFracLiteralTests
{
    [Fact]
    public void HostAndNativeAgreeOnFractionalLiteralsAndHostErrorCases()
    {
        string root = DualMode.FindRoot();
        AssertHostNativeSay(root, "1.5", "1.5\n");
        AssertHostNativeSay(root, "0.25", "0.25\n");
        AssertHostNativeSay(root, "10.0", "10\n");
        AssertHostNativeSay(root, "-1.5", "-1.5\n");
        AssertHostNativeSay(root, "-10.0", "-10\n");

        DualMode.Proc hostDot = DualMode.RunVire(root, new string[] { Write(root, "say 1.") }, root);
        DualMode.Proc nativeDot = CompileNative(root, Write(root, "say 1."));
        Assert.NotEqual(0, hostDot.Code);
        Assert.NotEqual(0, nativeDot.Code);
        Assert.DoesNotContain("that number is not ready", DualMode.Norm(nativeDot.Out + nativeDot.Err));

        DualMode.Proc hostLead = DualMode.RunVire(root, new string[] { Write(root, "say .5") }, root);
        DualMode.Proc nativeLead = CompileNative(root, Write(root, "say .5"));
        Assert.NotEqual(0, hostLead.Code);
        Assert.NotEqual(0, nativeLead.Code);
        Assert.DoesNotContain("that number is not ready", DualMode.Norm(nativeLead.Out + nativeLead.Err));
    }

    static void AssertHostNativeSay(string root, string literal, string want)
    {
        string src = Write(root, "say " + literal);
        DualMode.Proc host = DualMode.RunVire(root, new string[] { src }, root);
        Assert.True(host.Code == 0, host.Err + host.Out);
        Assert.Equal(want, DualMode.Norm(host.Out));
        if (!OperatingSystem.IsLinux()) return;
        DualMode.Proc compiled = CompileNative(root, src);
        Assert.True(compiled.Code == 0, compiled.Out + compiled.Err);
        string hexRel = Path.ChangeExtension(src, ".hex");
        byte[] image = HexToBin(root, hexRel);
        Assert.Equal(0x7f, image[0]);
        string elf = Path.Combine(root, hexRel.Replace('/', Path.DirectorySeparatorChar) + ".elf");
        File.WriteAllBytes(elf, image);
        try { File.SetUnixFileMode(elf, UnixFileMode.UserRead | UnixFileMode.UserWrite | UnixFileMode.UserExecute); } catch (PlatformNotSupportedException) { }
        ProcessStartInfo info = new ProcessStartInfo();
        info.FileName = elf;
        info.WorkingDirectory = root;
        info.RedirectStandardOutput = true;
        info.RedirectStandardError = true;
        info.UseShellExecute = false;
        Process process = Process.Start(info);
        string stdout = process.StandardOutput.ReadToEnd();
        string stderr = process.StandardError.ReadToEnd();
        Assert.True(process.WaitForExit(30000), "native frac timed out");
        Assert.True(process.ExitCode == 0, stderr + stdout);
        Assert.Equal(want, DualMode.Norm(stdout));
    }

    static string Write(string root, string body)
    {
        string dir = Path.Combine(root, "data", "frac-lit", Guid.NewGuid().ToString("N"));
        Directory.CreateDirectory(dir);
        string rel = Path.GetRelativePath(root, Path.Combine(dir, "prog.vire")).Replace('\\', '/');
        File.WriteAllText(Path.Combine(root, rel.Replace('/', Path.DirectorySeparatorChar)), "define main\n  " + body + "\nend\n");
        return rel;
    }

    static DualMode.Proc CompileNative(string root, string srcRel)
    {
        string hexRel = Path.ChangeExtension(srcRel, ".hex");
        return DualMode.RunVire(root, new string[] { "compile-native.vire", srcRel, hexRel }, root);
    }

    static byte[] HexToBin(string root, string hexRel)
    {
        string hex = File.ReadAllText(Path.Combine(root, hexRel.Replace('/', Path.DirectorySeparatorChar))).Trim();
        byte[] raw = new byte[hex.Length / 2];
        for (int i = 0; i < raw.Length; i++)
            raw[i] = Convert.ToByte(hex.Substring(i * 2, 2), 16);
        return raw;
    }
}
