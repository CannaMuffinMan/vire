using System;
using System.IO;
using Xunit;

public class NativeArenaTests
{
    const int ArenaBytes = 33554432;

    [Fact]
    public void MappingAllocAndPeHeapShareThe32MbCap()
    {
        string root = DualMode.FindRoot();
        string rt = File.ReadAllText(Path.Combine(root, "src", "rt.vire"));
        string more = File.ReadAllText(Path.Combine(root, "src", "rt-more.vire"));
        string pe = File.ReadAllText(Path.Combine(root, "src", "pe.vire"));
        Assert.Contains("let image be emitU32 with image, " + ArenaBytes, rt);
        Assert.Contains("emitU32 with image, " + ArenaBytes, more);
        Assert.Contains("poke32 with head, 224, 1048576", pe);
        Assert.Contains("poke32 with head, 240, 1048576", pe);
        Assert.DoesNotContain("poke32 with head, 224, " + ArenaBytes, pe);
        Assert.DoesNotContain("poke32 with head, 240, " + ArenaBytes, pe);
        Assert.DoesNotContain("268435456", rt);
        Assert.DoesNotContain("268435456", more);
        Assert.DoesNotContain("268435456", pe);
        Assert.Equal(5000000, Program.ProgramStepCap);
        Assert.Contains("2000000", more);
        Assert.Contains("pin with labels, \"rt_gc\", image", more);
        Assert.Contains("pin with labels, \"rt_note_wait\", image", more);
        Assert.Contains("33554432", more);
    }

    [Fact]
    public void NativeGcAndWaitCellsStayInTheImageData()
    {
        string rt = File.ReadAllText(Path.Combine(DualMode.FindRoot(), "src", "rt.vire"));
        Assert.Contains("pin with labels, \"gc_busy\", image", rt);
        Assert.Contains("pin with labels, \"wait_cell\", image", rt);
        string native = File.ReadAllText(Path.Combine(DualMode.FindRoot(), "compile-native.vire"));
        Assert.Contains("nm == \"args\" or nm == \"ticks\"", native);
        Assert.DoesNotContain("MaxCalls", File.ReadAllText(Path.Combine(DualMode.FindRoot(), "src", "rt-more.vire")));
    }

    [Fact]
    public void AllocLimitLoadsTheSavedHeapBase()
    {
        string more = File.ReadAllText(Path.Combine(DualMode.FindRoot(), "src", "rt-more.vire"));
        Assert.Contains("emitRel with image, fixes, \"heap_cell\"", more);
        Assert.DoesNotContain("[77, 137, 250, 73, 129, 194]", more);
    }

    [Fact]
    public void InternTableLivesInTheImageNotOnTheFrameCursor()
    {
        string root = DualMode.FindRoot();
        string rt = File.ReadAllText(Path.Combine(root, "src", "rt.vire"));
        string more = File.ReadAllText(Path.Combine(root, "src", "rt-more.vire"));
        Assert.Contains("pin with labels, \"heap_cell\", image", rt);
        Assert.Contains("pin with labels, \"intern_tab\", image", rt);
        Assert.Contains("let image be emitRel with image, fixes, \"heap_cell\"", rt);
        Assert.Contains("emitRel with image, fixes, \"intern_tab\"", more);
        Assert.DoesNotContain("intern_fill", rt);
        Assert.DoesNotContain("73, 141, 135", more);
        Assert.DoesNotContain("73, 141, 151", rt);
    }

    [Fact]
    public void TextIndexReusesInternedAsciiBytes()
    {
        string more = File.ReadAllText(Path.Combine(DualMode.FindRoot(), "src", "rt-more.vire"));
        Assert.Contains("pin with labels, \"at_text_alloc\", image", more);
        Assert.Contains("pin with labels, \"at_text_push\", image", more);
        Assert.Contains("emitJcc with image, fixes, 131, \"at_text_alloc\"", more);
        Assert.Contains("emitU32 with image, 128", more);
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
    public void NativeEmuCheckCoversInternedIndexing()
    {
        string root = DualMode.FindRoot();
        string emu = File.ReadAllText(Path.Combine(root, "tools", "native-pe-emu-check.sh"));
        Assert.Contains("intern-chars", emu);
        Assert.Contains("hello-stage", emu);
        Assert.Contains("gc-kind-stress", emu);
        Assert.True(File.Exists(Path.Combine(root, "tests", "native", "intern-chars.vire")));
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
        Assert.DoesNotContain("native-selfhost-proof.ps1", yml);
        Assert.Contains("native-oom.ps1", yml);
        Assert.Contains("native-list-cap-proof.ps1", yml);
        Assert.DoesNotContain("continue-on-error: true", yml);
    }

    [Fact]
    public void PeRtPushListGateMatchesHostCap()
    {
        string more = File.ReadAllText(Path.Combine(DualMode.FindRoot(), "src", "rt-more.vire"));
        int push = more.IndexOf("pin with labels, \"rt_push\", image", StringComparison.Ordinal);
        int bytes = more.IndexOf("pin with labels, \"push_byte\", image", StringComparison.Ordinal);
        Assert.True(push >= 0 && bytes > push);
        string listGate = more.Substring(push, bytes - push);
        Assert.Contains("emitU32 with image, 100000", listGate);
        Assert.DoesNotContain("emitU32 with image, 2000000", listGate);
        string byteGate = more.Substring(bytes, more.IndexOf("pin with labels, \"rt_bytes\", image", StringComparison.Ordinal) - bytes);
        Assert.Contains("emitU32 with image, 2000000", byteGate);
        string host = File.ReadAllText(Path.Combine(DualMode.FindRoot(), "Vire.cs"));
        Assert.Contains("const int MaxItems = 100000;", host);
        Assert.Contains("int itemCap = 100000;", host);
    }
}
