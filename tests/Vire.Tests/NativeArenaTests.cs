using System;
using System.IO;
using Xunit;

public class NativeArenaTests
{
    const int ArenaBytes = 33554432;
    const int InternOff = 4096;
    const int InternCount = 128;
    const int StackOff = 65536;

    [Fact]
    public void MappingAllocAndPeHeapShareThe32MbCap()
    {
        string root = DualMode.FindRoot();
        string rt = File.ReadAllText(Path.Combine(root, "src", "rt.vire"));
        string more = File.ReadAllText(Path.Combine(root, "src", "rt-more.vire"));
        string pe = File.ReadAllText(Path.Combine(root, "src", "pe.vire"));
        Assert.Contains("let image be emitU32 with image, " + ArenaBytes, rt);
        Assert.Contains("emitU32 with image, " + ArenaBytes, more);
        Assert.Contains("poke32 with head, 224, " + ArenaBytes, pe);
        Assert.Contains("poke32 with head, 240, " + ArenaBytes, pe);
        Assert.DoesNotContain("268435456", rt);
        Assert.DoesNotContain("268435456", more);
        Assert.DoesNotContain("268435456", pe);
        Assert.Equal(5000000, Program.ProgramStepCap);
        Assert.Contains("2000000", more);
    }

    [Fact]
    public void InternTableIsInitializedBeforeArgsAndFitsUnderTheStack()
    {
        string rt = File.ReadAllText(Path.Combine(DualMode.FindRoot(), "src", "rt.vire"));
        Assert.Contains("pin with labels, \"intern_fill\", image", rt);
        Assert.Contains("let image be emitU32 with image, " + InternOff, rt);
        Assert.Contains("let image be emitU32 with image, " + InternCount, rt);
        int intern = rt.IndexOf("intern_fill", StringComparison.Ordinal);
        int args = rt.IndexOf("rt_args_init", intern, StringComparison.Ordinal);
        Assert.True(intern >= 0 && args > intern, "intern_fill must run before rt_args_init");
        Assert.True(InternOff + InternCount * 16 <= StackOff);
    }

    [Fact]
    public void TextIndexReusesInternedAsciiBytes()
    {
        string more = File.ReadAllText(Path.Combine(DualMode.FindRoot(), "src", "rt-more.vire"));
        Assert.Contains("pin with labels, \"at_text_alloc\", image", more);
        Assert.Contains("pin with labels, \"at_text_push\", image", more);
        Assert.Contains("emitJcc with image, fixes, 131, \"at_text_alloc\"", more);
        Assert.Contains("emitU32 with image, " + InternCount, more);
        Assert.Contains("emitU32 with image, " + InternOff, more);
        Assert.Contains("emitRel with image, fixes, \"at_text_push\"", more);
    }

    [Fact]
    public void CompileNativeAndSrcStayTheOnlyNativeSources()
    {
        string root = DualMode.FindRoot();
        string native = File.ReadAllText(Path.Combine(root, "compile-native.vire"));
        Assert.Contains("use \"src/pe.vire\"", native);
        Assert.DoesNotContain("use \"data/src/", native);
        string dataSrc = Path.Combine(root, "data", "src");
        if (!Directory.Exists(dataSrc)) return;
        foreach (string path in Directory.GetFiles(dataSrc, "*.vire"))
        {
            string name = Path.GetFileName(path);
            string peer = Path.Combine(root, "src", name);
            Assert.True(File.Exists(peer), "data/src/" + name + " has no src/ peer");
            Assert.Equal(File.ReadAllText(peer), File.ReadAllText(path));
        }
    }

    [Fact]
    public void NativeSmokeCoversInternedIndexing()
    {
        string smoke = File.ReadAllText(Path.Combine(DualMode.FindRoot(), "tools", "native-smoke.ps1"));
        Assert.Contains("intern-chars", smoke);
        Assert.Contains("tests/native/intern-chars.vire", smoke);
    }

    [Fact]
    public void NativeSelfHostProofKeepsThe32MbCap()
    {
        string root = DualMode.FindRoot();
        string proof = File.ReadAllText(Path.Combine(root, "tools", "native-selfhost-proof.ps1"));
        Assert.Contains("compile-native.vire", proof);
        Assert.Contains("Copy-Item -Recurse", proof);
        Assert.Contains("SHA256", proof);
        Assert.Contains("hello from stage", proof);
        Assert.DoesNotContain("268435456", proof);
        Assert.DoesNotContain("96MB", proof);
        string yml = File.ReadAllText(Path.Combine(root, ".github", "workflows", "check.yml"));
        Assert.Contains("native-selfhost-proof.ps1", yml);
    }
}
