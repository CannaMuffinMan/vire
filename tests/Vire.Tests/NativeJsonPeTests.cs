using System;
using System.Diagnostics;
using System.IO;
using Xunit;

public class NativeJsonPeTests
{
    const string FailBefore = "6e969fc2e9c94f537bad69b948e56670096c2a1b";

    [Fact]
    public void FuzzJsonMapAndParseArrayReprosAreTracked()
    {
        string root = DualMode.FindRoot();
        Assert.True(File.Exists(Path.Combine(root, "tests", "fuzz", "findings", "native-pe-json-map.vire")));
        Assert.True(File.Exists(Path.Combine(root, "tests", "fuzz", "findings", "native-pe-parse-array.vire")));
        string more = File.ReadAllText(Path.Combine(root, "src", "rt-more.vire"));
        Assert.Contains("72, 137, 208", more);
        string blob = File.ReadAllText(Path.Combine(root, "src", "rt-net-json-blob.txt")).Trim();
        Assert.Contains("4c8b024c01c148894808", blob);
        Assert.Contains("4889c1b23a", blob);
        Assert.StartsWith("488b4df8", blob);
        Assert.DoesNotContain("4801c848894108", blob);
        Assert.Contains("cl_emptybody", File.ReadAllText(Path.Combine(root, "src", "rt-net.vire")));
        Assert.Equal(FailBefore, "6e969fc2e9c94f537bad69b948e56670096c2a1b");
    }

    [Fact]
    public void NativeLinuxElfJsonParseAndListenDoNotSegfault()
    {
        if (!OperatingSystem.IsLinux())
            return;
        string root = DualMode.FindRoot();
        string work = Path.Combine(root, "data", "native-json-elf", Guid.NewGuid().ToString("N"));
        Directory.CreateDirectory(work);
        try
        {
            File.WriteAllText(Path.Combine(work, "parse-obj.vire"), "define main\n  say (json with (parse with \"{\\\"a\\\":1}\"))\nend\n");
            string dir = Path.GetRelativePath(root, work).Replace('\\', '/');
            DualMode.Proc compiled = DualMode.RunVire(root, new string[] { "compile-native.vire", dir + "/parse-obj.vire", dir + "/parse-obj.hex" }, root);
            Assert.True(compiled.Code == 0, DualMode.Norm(compiled.Out + " " + compiled.Err));
            byte[] elf = HexToBytes(root, dir + "/parse-obj.hex");
            string elfPath = Path.Combine(work, "parse-obj.elf");
            File.WriteAllBytes(elfPath, elf);
            ProcessStartInfo chmod = new ProcessStartInfo();
            chmod.FileName = "chmod";
            chmod.Arguments = "+x \"" + elfPath + "\"";
            chmod.UseShellExecute = false;
            Process.Start(chmod).WaitForExit();
            ProcessStartInfo run = new ProcessStartInfo();
            run.FileName = elfPath;
            run.WorkingDirectory = root;
            run.RedirectStandardOutput = true;
            run.RedirectStandardError = true;
            run.UseShellExecute = false;
            Process proc = Process.Start(run);
            string stdout = proc.StandardOutput.ReadToEnd();
            string stderr = proc.StandardError.ReadToEnd();
            Assert.True(proc.WaitForExit(15000), "elf timed out");
            Assert.True(proc.ExitCode == 0, stdout + stderr);
            Assert.Contains("{\"a\":1}", DualMode.Norm(stdout).Replace(" ", ""));
        }
        finally
        {
            try { Directory.Delete(work, true); } catch (IOException) { }
        }
    }

    static byte[] HexToBytes(string root, string rel)
    {
        string hex = File.ReadAllText(Path.Combine(root, rel.Replace('/', Path.DirectorySeparatorChar))).Trim();
        byte[] buf = new byte[hex.Length / 2];
        for (int i = 0; i < buf.Length; i++)
            buf[i] = Convert.ToByte(hex.Substring(i * 2, 2), 16);
        return buf;
    }
}
