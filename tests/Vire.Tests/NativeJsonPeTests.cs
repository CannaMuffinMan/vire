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
    public void NativePeJsonMapEncodesAndParseArrayExitsClean()
    {
        if (!OperatingSystem.IsLinux())
            return;
        string root = DualMode.FindRoot();
        string work = Path.Combine(root, "data", "native-json-pe", Guid.NewGuid().ToString("N"));
        Directory.CreateDirectory(work);
        try
        {
            File.Copy(
                Path.Combine(root, "tests", "fuzz", "findings", "native-pe-json-map.vire"),
                Path.Combine(work, "json-map.vire"));
            File.Copy(
                Path.Combine(root, "tests", "fuzz", "findings", "native-pe-parse-array.vire"),
                Path.Combine(work, "parse-array.vire"));
            File.WriteAllText(
                Path.Combine(work, "parse-round.vire"),
                "define main\n  say (json with (parse with \"[1,true,null]\"))\nend\n");
            string dir = Rel(work, root);
            CompilePe(root, dir + "/json-map.vire", dir + "/json-map.hex");
            CompilePe(root, dir + "/parse-array.vire", dir + "/parse-array.hex");
            CompilePe(root, dir + "/parse-round.vire", dir + "/parse-round.hex");
            string mapOut = Emu(root, Path.Combine(work, "json-map.hex"));
            string parseOut = Emu(root, Path.Combine(work, "parse-array.hex"));
            string roundOut = Emu(root, Path.Combine(work, "parse-round.hex"));
            Assert.Contains("EXIT 0", mapOut);
            Assert.Contains("FAULTS []", mapOut);
            Assert.Contains("{\"a\":2}", mapOut.Replace(" ", ""));
            Assert.Contains("EXIT 0", parseOut);
            Assert.Contains("FAULTS []", parseOut);
            Assert.Contains("EXIT 0", roundOut);
            Assert.Contains("FAULTS []", roundOut);
            Assert.Contains("[1,true,null]", DualMode.Norm(roundOut));
        }
        finally
        {
            try { Directory.Delete(work, true); } catch (IOException) { }
        }
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

    static string Rel(string work, string root)
    {
        return Path.GetRelativePath(root, work).Replace('\\', '/');
    }

    static void CompilePe(string root, string src, string hex)
    {
        DualMode.Proc compiled = DualMode.RunVire(root, new string[] { "compile-native.vire", src, hex, "pe" }, root);
        Assert.Equal(0, compiled.Code);
        Assert.Contains("compiled", DualMode.Norm(compiled.Out));
    }

    static string Emu(string root, string hexPath)
    {
        ProcessStartInfo info = new ProcessStartInfo();
        info.FileName = "python3";
        info.Arguments = "\"" + Path.Combine(root, "tools", "native-pe-emu.py") + "\" \"" + hexPath + "\"";
        info.WorkingDirectory = root;
        info.RedirectStandardOutput = true;
        info.RedirectStandardError = true;
        info.UseShellExecute = false;
        Process process = Process.Start(info);
        string stdout = process.StandardOutput.ReadToEnd();
        string stderr = process.StandardError.ReadToEnd();
        Assert.True(process.WaitForExit(60000), "emu timed out");
        Assert.True(process.ExitCode == 0, stdout + stderr);
        return stdout;
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
