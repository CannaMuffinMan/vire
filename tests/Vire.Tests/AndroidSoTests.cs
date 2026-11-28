using System;
using System.IO;
using Xunit;

public class AndroidSoTests
{
    [Fact]
    public void AndroidBuildFailsClosedWhenNdkMissing()
    {
        string dir = Path.Combine(Path.GetTempPath(), "vire-android-closed-" + Guid.NewGuid().ToString("N"));
        string empty = Path.Combine(dir, "ndk");
        Directory.CreateDirectory(dir);
        Directory.CreateDirectory(empty);
        File.WriteAllText(Path.Combine(dir, "add.c"), "int add(int a,int b){return a+b;}\n");
        string prevNdkHome = Environment.GetEnvironmentVariable("ANDROID_NDK_HOME");
        string prevNdkRoot = Environment.GetEnvironmentVariable("ANDROID_NDK_ROOT");
        try
        {
            Environment.SetEnvironmentVariable("ANDROID_NDK_HOME", empty);
            Environment.SetEnvironmentVariable("ANDROID_NDK_ROOT", empty);
            VireError err = Assert.Throws<VireError>(() => VireBuild.Compile(dir, "android", "add.c", 1, 1));
            Assert.Contains("phone SDK is not installed", err.Message);
            Assert.Contains("ANDROID_NDK_HOME", err.Message);
            Assert.False(File.Exists(Path.Combine(dir, "data", "add.so")));
        }
        finally
        {
            Environment.SetEnvironmentVariable("ANDROID_NDK_HOME", prevNdkHome);
            Environment.SetEnvironmentVariable("ANDROID_NDK_ROOT", prevNdkRoot);
            try { Directory.Delete(dir, true); } catch (IOException) { }
        }
    }

    [Fact]
    public void AndroidBuildEmitsElfSharedLibrary()
    {
        string dir = Path.Combine(Path.GetTempPath(), "vire-android-so-" + Guid.NewGuid().ToString("N"));
        Directory.CreateDirectory(dir);
        try
        {
            File.WriteAllText(Path.Combine(dir, "add.c"), "int add(int a,int b){return a+b;}\n");
            try
            {
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
            catch (VireError err)
            {
                if (err.Message.IndexOf("phone SDK is not installed", StringComparison.Ordinal) >= 0)
                {
                    Assert.Fail("env ANDROID_NDK_HOME or ANDROID_NDK_ROOT (NDK clang --target=aarch64-linux-android35) required; " + err.Message);
                }
                throw;
            }
        }
        finally
        {
            try { Directory.Delete(dir, true); } catch (IOException) { }
        }
    }
}
