using System;
using System.IO;
using Xunit;

public class NativePathSafetyTests
{
    static string Root()
    {
        string dir = AppContext.BaseDirectory;
        while (!string.IsNullOrEmpty(dir))
        {
            if (File.Exists(Path.Combine(dir, "src", "pe.vire"))) return dir;
            dir = Path.GetDirectoryName(dir);
        }
        return Directory.GetCurrentDirectory();
    }

    [Fact]
    public void NativeImportsIncludeAttributesAndHandleInfo()
    {
        string pe = File.ReadAllText(Path.Combine(Root(), "src", "pe.vire"));
        Assert.Contains("GetFileAttributesA", pe);
        Assert.Contains("GetFileInformationByHandle", pe);
        Assert.Contains("SetUnhandledExceptionFilter", pe);
        Assert.Contains("AddVectoredExceptionHandler", pe);
        Assert.Contains("SetFilePointerEx", pe);
        Assert.Contains("SetEndOfFile", pe);
        Assert.Contains("GetFinalPathNameByHandleA", pe);
        Assert.Contains("iat_ga", pe);
        Assert.Contains("iat_fi", pe);
        Assert.Contains("iat_ue", pe);
        Assert.Contains("iat_sp", pe);
        Assert.Contains("iat_se", pe);
        Assert.Contains("iat_fp", pe);
        Assert.DoesNotContain("\"Sleep\"", pe);
        Assert.DoesNotContain("iat_sl", pe);
    }

    [Fact]
    public void NativePathWalkRefusesReparseAndCallsCheckFromRead()
    {
        string more = File.ReadAllText(Path.Combine(Root(), "src", "rt-more.vire"));
        string rt = File.ReadAllText(Path.Combine(Root(), "src", "rt.vire"));
        Assert.Contains("path_walk", more);
        Assert.Contains("iat_ga", more);
        Assert.Contains("emitU32 with image, 1024", more);
        Assert.Contains("15, 182, 20, 1", more);
        Assert.Contains("68, 15, 182, 68, 1, 8", more);
        Assert.DoesNotContain("138, 4, 1, 60, 47", more);
        Assert.DoesNotContain("138, 68, 1, 8, 60, 58", more);
        Assert.Contains("rt_check_path", rt);
        Assert.Contains("path_copy_oom", more);
        Assert.Contains("72, 139, 85, 248, 72, 141, 82, 8", more);
        Assert.DoesNotContain("72, 141, 81, 8, 72, 137, 85, 216", more);
        Assert.DoesNotContain("72, 141, 73, 8, 72, 137, 77, 232, 72, 199, 69, 224, 0, 0, 0, 0", more);
        string native = File.ReadAllText(Path.Combine(Root(), "compile-native.vire"));
        int runtime = native.LastIndexOf("parkRuntime with (gen at \"image\")", StringComparison.Ordinal);
        int pool = native.LastIndexOf("parkPool with (gen at \"image\")", StringComparison.Ordinal);
        Assert.True(runtime >= 0 && pool > runtime, "string pool must park in RW .data after frame_base");
        Assert.Contains("2097280", rt);
        Assert.Contains("2097280", more);
        Assert.Contains("72, 199, 68, 36, 32, 3, 0, 0, 0", more);
        Assert.Contains("72, 199, 68, 36, 32, 1, 0, 0, 0", more);
        Assert.DoesNotContain("72, 199, 68, 36, 32, 2, 0, 0, 0", more);
        Assert.Contains("iat_sp", more);
        Assert.Contains("iat_se", more);
        Assert.Contains("rt_memcpy", more);
        Assert.Contains("iat_fi", rt);
        Assert.Contains("iat_fi", more);
        Assert.Contains("rt_bind_path", more);
        Assert.Contains("iat_fp", more);
        Assert.Contains("rt_bind_path", rt);
        Assert.Contains("path_space", more);
        Assert.Contains("read_space", rt);
    }

    [Fact]
    public void NativeFrameSaveStopsAtInterpreterCallDepth()
    {
        string rt = File.ReadAllText(Path.Combine(Root(), "src", "rt.vire"));
        Assert.Contains("frame_base", rt);
        Assert.Contains("emitU32 with image, 1024", rt);
        Assert.Contains("msg_deep", rt);
        Assert.Contains("frame_deep", rt);
        Assert.Contains("heap_cell", rt);
        Assert.Contains("intern_tab", rt);
    }

    [Fact]
    public void CrashFilterOmitsUncheckedCreateFile()
    {
        string rt = File.ReadAllText(Path.Combine(Root(), "src", "rt.vire"));
        int crash = rt.IndexOf("pin with labels, \"crash_filter\"", StringComparison.Ordinal);
        int after = rt.IndexOf("pin with labels, \"rt_push_int\"", crash);
        string slice = rt.Substring(crash, after - crash);
        Assert.DoesNotContain("iat_cf", slice);
        Assert.Contains("crash_rip_msg", slice);
    }

    [Fact]
    public void LoopCountersParkInDataAfterFrameBase()
    {
        string src = File.ReadAllText(Path.Combine(Root(), "compile-native.vire"));
        int runtime = src.LastIndexOf("parkRuntime with (gen at \"image\")", StringComparison.Ordinal);
        int counters = src.LastIndexOf("parkCounters with (gen at \"image\")", StringComparison.Ordinal);
        Assert.True(runtime >= 0 && counters > runtime);
    }

    [Fact]
    public void ProductPeOmitsSleepWidenerAndIatSl()
    {
        string root = Root();
        string pe = File.ReadAllText(Path.Combine(root, "src", "pe.vire"));
        string more = File.ReadAllText(Path.Combine(root, "src", "rt-more.vire"));
        string native = File.ReadAllText(Path.Combine(root, "compile-native.vire"));
        Assert.DoesNotContain("\"Sleep\"", pe);
        Assert.DoesNotContain("iat_sl", pe);
        Assert.DoesNotContain("iat_sl", more);
        Assert.DoesNotContain("Sleep", native);
        string dataPe = Path.Combine(root, "data", "src", "pe.vire");
        if (File.Exists(dataPe))
        {
            string dpe = File.ReadAllText(dataPe);
            Assert.DoesNotContain("\"Sleep\"", dpe);
            Assert.DoesNotContain("iat_sl", dpe);
        }
        string ps1 = File.ReadAllText(Path.Combine(root, "tools", "native-sec-windows.ps1"));
        Assert.Contains("Test-only", ps1);
        Assert.Contains("Never apply to the product checkout", ps1);
        Assert.Contains("Apply-SecWiden", ps1);
        string paths = File.ReadAllText(Path.Combine(root, "VirePaths.cs"));
        Assert.DoesNotContain("VIRE_TEST_TOCTOU_MS", paths);
        Assert.Contains("TestToctouDelayMs", paths);
        Assert.Contains("TryLinuxFdId", paths);
        Assert.Contains("TryLinuxPathId", paths);
        var info = new System.Diagnostics.ProcessStartInfo
        {
            FileName = "git",
            WorkingDirectory = root,
            RedirectStandardOutput = true,
            UseShellExecute = false
        };
        info.ArgumentList.Add("show");
        info.ArgumentList.Add("d818f1691ed8659538a10255c58211ebc1316e00:VirePaths.cs");
        System.Diagnostics.Process p = System.Diagnostics.Process.Start(info);
        string old = p.StandardOutput.ReadToEnd();
        p.WaitForExit(15000);
        if (p.ExitCode == 0 && old.Length > 0)
        {
            Assert.DoesNotContain("TryLinuxFdId", old);
            Console.WriteLine("host_fileid_fail_before d818f169 TryLinuxFdId=false");
        }
        Console.WriteLine("host_fileid_pass_after TryLinuxFdId=true");
        var dbg = new System.Diagnostics.ProcessStartInfo
        {
            FileName = "git",
            WorkingDirectory = root,
            RedirectStandardOutput = true,
            UseShellExecute = false
        };
        dbg.ArgumentList.Add("show");
        dbg.ArgumentList.Add("d818f1691ed8659538a10255c58211ebc1316e00:VireDebug.cs");
        System.Diagnostics.Process d = System.Diagnostics.Process.Start(dbg);
        string oldDbg = d.StandardOutput.ReadToEnd();
        d.WaitForExit(15000);
        if (d.ExitCode == 0 && oldDbg.Length > 0)
        {
            Assert.DoesNotContain("if (Environment.GetEnvironmentVariable(\"VIRE_DEBUGGER\") != \"1\") return false;", oldDbg);
            Console.WriteLine("break_probe_fail_before d818f169 always_opens_break_txt=true");
        }
        string nowDbg = File.ReadAllText(Path.Combine(root, "VireDebug.cs"));
        Assert.Contains("if (Environment.GetEnvironmentVariable(\"VIRE_DEBUGGER\") != \"1\") return false;", nowDbg);
        Console.WriteLine("break_probe_pass_after VIRE_DEBUGGER_gate=true");
    }
}
