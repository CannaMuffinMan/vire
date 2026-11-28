using System;
using System.Diagnostics;
using System.IO;
using Xunit;

public class NativeFormsTests
{
    [Fact]
    public void TrackedTryMissAndForListFixturesExist()
    {
        string root = DualMode.FindRoot();
        Assert.True(File.Exists(Path.Combine(root, "data", "native-forms", "try-miss.vire")));
        Assert.True(File.Exists(Path.Combine(root, "data", "native-forms", "for-list.vire")));
        string ps = File.ReadAllText(Path.Combine(root, "tools", "native-forms.ps1"));
        Assert.Contains("try-miss", ps);
        Assert.Contains("for-list", ps);
        Assert.DoesNotContain("TODO(VIRE-FINISH-NOW)", ps);
        Assert.Contains("native-forms.ps1", File.ReadAllText(Path.Combine(root, "tools", "couchstation-windows-all.ps1")));
    }

    [Fact]
    public void LinuxElfTryMissAndForListMatchHost()
    {
        if (!OperatingSystem.IsLinux())
            return;
        string root = DualMode.FindRoot();
        string[] names = { "try-miss", "for-list" };
        foreach (string name in names)
        {
            string srcRel = "data/native-forms/" + name + ".vire";
            string hexRel = "data/native-forms/" + name + ".hex";
            string hexPath = Path.Combine(root, "data", "native-forms", name + ".hex");
            if (File.Exists(hexPath)) File.Delete(hexPath);
            DualMode.Proc compiled = DualMode.RunVire(root, new string[] { "compile-native.vire", srcRel, hexRel }, root);
            Assert.True(compiled.Code == 0, DualMode.Norm(compiled.Out + " " + compiled.Err));
            string hex = File.ReadAllText(hexPath).Trim();
            byte[] elf = new byte[hex.Length / 2];
            for (int i = 0; i < elf.Length; i++)
                elf[i] = Convert.ToByte(hex.Substring(i * 2, 2), 16);
            string elfPath = Path.Combine(root, "data", "native-forms", name + ".elf");
            File.WriteAllBytes(elfPath, elf);
            Process chmod = Process.Start(new ProcessStartInfo("chmod", "+x \"" + elfPath + "\"") { UseShellExecute = false });
            chmod.WaitForExit();
            DualMode.Proc host = DualMode.RunVire(root, new string[] { srcRel }, root);
            ProcessStartInfo ninfo = new ProcessStartInfo(elfPath)
            {
                RedirectStandardOutput = true,
                RedirectStandardError = true,
                UseShellExecute = false,
                WorkingDirectory = root
            };
            Process nat = Process.Start(ninfo);
            string nout = nat.StandardOutput.ReadToEnd();
            string nerr = nat.StandardError.ReadToEnd();
            nat.WaitForExit();
            Assert.Equal(0, host.Code);
            Assert.Equal(0, nat.ExitCode);
            Assert.Equal(DualMode.Norm(host.Out), DualMode.Norm(nout));
            Assert.Equal("", DualMode.Norm(nerr));
        }
    }
}
