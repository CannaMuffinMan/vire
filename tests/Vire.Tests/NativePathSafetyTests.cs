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
    }
}
