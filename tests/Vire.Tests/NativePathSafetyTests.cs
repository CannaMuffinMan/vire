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
        Assert.Contains("rt_check_path", rt);
        Assert.Contains("2097280", rt);
        Assert.Contains("2097280", more);
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
    }
}
