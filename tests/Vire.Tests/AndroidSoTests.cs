using System;
using System.IO;
using Xunit;

public class AndroidSoTests
{
    [Fact]
    public void AndroidBuildEmitsElfSharedLibrary()
    {
        string dir = Path.Combine(Path.GetTempPath(), "vire-android-so-" + Guid.NewGuid().ToString("N"));
        Directory.CreateDirectory(dir);
        try
        {
            if (!OperatingSystem.IsWindows())
            {
                File.WriteAllText(Path.Combine(dir, "add.c"), "int add(int a,int b){return a+b;}\n");
                VireError err = Assert.Throws<VireError>(() => VireBuild.Compile(dir, "android", "add.c", 1, 1));
                Assert.Contains("not installed", err.Message);
                return;
            }
            File.WriteAllText(Path.Combine(dir, "add.c"), "int add(int a,int b){return a+b;}\n");
            string rel = VireBuild.Compile(dir, "android", "add.c", 1, 1);
            Assert.Equal("data/add.so", rel);
            string so = Path.Combine(dir, "data", "add.so");
            Assert.True(new FileInfo(so).Length > 100);
            byte[] head = new byte[4];
            using (FileStream stream = File.OpenRead(so))
            {
                Assert.Equal(4, stream.Read(head, 0, 4));
            }
            Assert.Equal(0x7F, head[0]);
            Assert.Equal((byte)'E', head[1]);
            Assert.Equal((byte)'L', head[2]);
            Assert.Equal((byte)'F', head[3]);
        }
        finally
        {
            try { Directory.Delete(dir, true); } catch (IOException) { }
        }
    }
}
