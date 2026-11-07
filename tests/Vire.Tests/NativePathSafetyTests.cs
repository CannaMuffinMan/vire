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
        Assert.Contains("iat_ga", pe);
        Assert.Contains("iat_fi", pe);
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
        Assert.Contains("72, 199, 68, 36, 32, 2, 0, 0, 0", more);
        Assert.Contains("iat_fi", rt);
        Assert.Contains("iat_fi", more);
    }

    [Fact]
    public void NativeFrameSaveStopsAtInterpreterCallDepth()
    {
        string rt = File.ReadAllText(Path.Combine(Root(), "src", "rt.vire"));
        Assert.Contains("frame_base", rt);
        Assert.Contains("emitU32 with image, 512", rt);
        Assert.Contains("msg_deep", rt);
        Assert.Contains("frame_deep", rt);
        Assert.Contains("heap_cell", rt);
        Assert.Contains("intern_tab", rt);
    }

    [Fact]
    public void NativeReadBuiltinIsDataOrSiteOnly()
    {
        string rt = File.ReadAllText(Path.Combine(Root(), "src", "rt.vire"));
        Assert.Contains("128, 122, 8, 100, 15, 133", rt);
        Assert.Contains("128, 122, 8, 115, 15, 133", rt);
        Assert.Contains("msg_folder", rt);
        Assert.Contains("102, 105, 108, 101, 115, 32, 115, 116, 97, 121, 32, 105, 110, 32, 100, 97, 116, 97, 32, 111, 114, 32, 115, 105, 116, 101", rt);
        Assert.DoesNotContain("\"src/\"", rt);
    }
}
