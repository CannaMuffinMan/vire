using System;
using System.Collections.Generic;
using System.IO;
using Xunit;

public class CopilotFindingsTests
{
    [Fact]
    public void F1_SelfExtendSnapshotsOriginalCount()
    {
        List<object> a = new List<object> { 1, 2 };
        Program.ExtendList(a, a, 100000, 1, 1);
        Assert.Equal(new object[] { 1, 2, 1, 2 }, a.ToArray());
    }

    [Fact]
    public void F2_LinuxOrdinaryFileLinkCountIsOne()
    {
        if (!OperatingSystem.IsLinux()) return;
        string dir = Path.Combine(Path.GetTempPath(), "vire-nlink-" + Guid.NewGuid().ToString("n"));
        Directory.CreateDirectory(dir);
        try
        {
            File.WriteAllText(Path.Combine(dir, "hello.vire"), "define main\n  say \"ok\"\nend\n");
            Assert.Equal(0, Program.Execute(new string[] { Path.Combine(dir, "hello.vire") }));
        }
        finally
        {
            try { Directory.Delete(dir, true); } catch (IOException) { }
        }
    }

    [Fact]
    public void F3_CompileNativeKeepsListExpressions()
    {
        string native = File.ReadAllText(Path.Combine(DualMode.FindRoot(), "compile-native.vire"));
        int list = native.IndexOf("if k == \"[\"", StringComparison.Ordinal);
        Assert.True(list >= 0);
        string slice = native.Substring(list, 800);
        Assert.Contains("parseExpr with state, func", slice);
        Assert.DoesNotContain("form with state) != \"num\" and (form with state) != \"-\"", slice);
    }

    [Fact]
    public void F4_PathWalkCopiesBeforeNul()
    {
        string more = File.ReadAllText(Path.Combine(DualMode.FindRoot(), "src", "rt-more.vire"));
        int ok = more.IndexOf("pin with labels, \"path_ok\"", StringComparison.Ordinal);
        string slice = more.Substring(ok, 700);
        Assert.Contains("rt_alloc", slice);
        Assert.Contains("rt_memcpy", slice);
    }

    [Fact]
    public void F5_WriteTruncatesTheValidatedHandle()
    {
        string more = File.ReadAllText(Path.Combine(DualMode.FindRoot(), "src", "rt-more.vire"));
        Assert.Contains("iat_se", more);
        Assert.Contains("iat_sp", more);
        int have = more.IndexOf("pin with labels, \"write_have\"", StringComparison.Ordinal);
        int ready = more.IndexOf("pin with labels, \"write_ready\"", StringComparison.Ordinal);
        string slice = more.Substring(have, ready - have);
        Assert.DoesNotContain("72, 199, 68, 36, 32, 2, 0, 0, 0", slice);
    }

    [Fact]
    public void F6_CrashFilterDoesNotCreateCrashRipFile()
    {
        string rt = File.ReadAllText(Path.Combine(DualMode.FindRoot(), "src", "rt.vire"));
        int crash = rt.IndexOf("pin with labels, \"crash_filter\"", StringComparison.Ordinal);
        int next = rt.IndexOf("pin with labels, \"rt_push_int\"", crash);
        string slice = rt.Substring(crash, next - crash);
        Assert.DoesNotContain("crash_path", slice);
        Assert.DoesNotContain("iat_cf", slice);
        Assert.Contains("iat_gs", slice);
        Assert.DoesNotContain("crash-rip.txt", rt);
    }

    [Fact]
    public void F4_F5_F6_WindowsOsRecipesArePresent()
    {
        string ps1 = File.ReadAllText(Path.Combine(DualMode.FindRoot(), "tools", "native-sec-windows.ps1"));
        Assert.Contains("f4_double_read", ps1);
        Assert.Contains("f5_two_process_race", ps1);
        Assert.Contains("f6_crash_pe", ps1);
        Assert.Contains("7c7c8ea3dcc4030ba8714fc2330d30b67f8d6867", ps1);
        Assert.Contains("do not let that become the function output", ps1);
    }

    [Fact]
    public void F7_WindowsJunctionRecipeRequiresSandboxText()
    {
        string ps1 = File.ReadAllText(Path.Combine(DualMode.FindRoot(), "tools", "native-sec-windows.ps1"));
        Assert.Contains("files stay inside the program folder", ps1);
        Assert.Contains("parent junction did not report sandbox error", ps1);
    }

    [Fact]
    public void F8_EmitU8WrapsAboveInt32Max()
    {
        List<object> got = (List<object>)Program.ExtendList(
            new List<object>(),
            new List<object> { 2147483648.0 },
            100000,
            1,
            1);
        Assert.Equal(0, Convert.ToInt32(got[0]));
    }

    [Fact]
    public void F9_ApkWithoutAndroidToolsDoesNotWritePlainManifest()
    {
        string src = File.ReadAllText(Path.Combine(DualMode.FindRoot(), "VireApk.cs"));
        Assert.DoesNotContain("PackZipSigned", src);
        Assert.Contains("aapt is not installed", src);
    }

    [Fact]
    public void F10_AndroidBuildDoesNotFallBackToHostClang()
    {
        string src = File.ReadAllText(Path.Combine(DualMode.FindRoot(), "VireBuild.cs"));
        Assert.Contains("--target=aarch64-linux-android35", src);
        Assert.DoesNotContain("FindOnPath(OperatingSystem.IsWindows() ? \"clang.exe\" : \"clang\")", src);
    }

    [Fact]
    public void F11_NativeExtendSnapshotsSourceLength()
    {
        string more = File.ReadAllText(Path.Combine(DualMode.FindRoot(), "src", "rt-more.vire"));
        Assert.Contains("72, 139, 85, 240, 72, 139, 2, 72, 137, 69, 192", more);
        Assert.Contains("72, 139, 69, 232, 72, 59, 69, 192, 15, 141", more);
        int bloop = more.IndexOf("pin with labels, \"extend_bloop\"", StringComparison.Ordinal);
        Assert.True(bloop >= 0);
        string bslice = more.Substring(bloop, 420);
        Assert.Contains("72, 139, 85, 240, 72, 139, 82, 16, 68, 15, 182, 12, 2", bslice);
    }

    [Fact]
    public void F12_NativeExtendRejectsNonnumericExtra()
    {
        string more = File.ReadAllText(Path.Combine(DualMode.FindRoot(), "src", "rt-more.vire"));
        int loop = more.IndexOf("pin with labels, \"extend_loop\"", StringComparison.Ordinal);
        string slice = more.Substring(loop, 500);
        Assert.Contains("extend_notnum", slice);
    }

    [Fact]
    public void F13_ArenaCheckUsesOneMegHeaderReserves()
    {
        string sh = File.ReadAllText(Path.Combine(DualMode.FindRoot(), "tools", "native-arena-check.sh"));
        Assert.Contains("poke32 with head, 224, 1048576", sh);
        Assert.Contains("! grep -q 'poke32 with head, 224, 33554432'", sh);
    }
}
