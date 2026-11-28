using System;
using System.IO;
using System.IO.Compression;
using Xunit;

public class ApkTests
{
    [Fact]
    public void PackIsHostOnlyNotGuestBuiltin()
    {
        string src = File.ReadAllText(Path.Combine(DualMode.FindRoot(), "Vire.cs"));
        int start = src.IndexOf("static readonly HashSet<string> Builtins", StringComparison.Ordinal);
        Assert.True(start >= 0);
        int end = src.IndexOf("});", start, StringComparison.Ordinal);
        Assert.True(end > start);
        string builtins = src.Substring(start, end - start);
        Assert.DoesNotContain("\"apk\"", builtins);
        Assert.DoesNotContain("\"pack\"", builtins);
    }

    [Fact]
    public void PackFailsClosedWhenAndroidSdkMissing()
    {
        string dir = Path.Combine(Path.GetTempPath(), "vire-apk-closed-" + Guid.NewGuid().ToString("N"));
        string emptySdk = Path.Combine(dir, "sdk");
        Directory.CreateDirectory(dir);
        Directory.CreateDirectory(emptySdk);
        string prevSdk = Environment.GetEnvironmentVariable("ANDROID_SDK_ROOT");
        string prevHome = Environment.GetEnvironmentVariable("ANDROID_HOME");
        try
        {
            Environment.SetEnvironmentVariable("ANDROID_SDK_ROOT", emptySdk);
            Environment.SetEnvironmentVariable("ANDROID_HOME", emptySdk);
            VireError err = Assert.Throws<VireError>(() => VireApk.Pack(dir, 1, 1));
            Assert.Contains("not installed", err.Message);
            Assert.Contains("ANDROID_SDK_ROOT", err.Message);
            Assert.False(File.Exists(Path.Combine(dir, "data", "app.apk")));
        }
        finally
        {
            Environment.SetEnvironmentVariable("ANDROID_SDK_ROOT", prevSdk);
            Environment.SetEnvironmentVariable("ANDROID_HOME", prevHome);
            try { Directory.Delete(dir, true); } catch (IOException) { }
        }
    }

    [Fact]
    public void PackWritesApkWithManifest()
    {
        string dir = Path.Combine(Path.GetTempPath(), "vire-apk-" + Guid.NewGuid().ToString("N"));
        Directory.CreateDirectory(dir);
        try
        {
            try
            {
                string rel = VireApk.Pack(dir, 1, 1);
                Assert.Equal("data/app.apk", rel);
                string apk = Path.Combine(dir, "data", "app.apk");
                Assert.True(File.Exists(Path.Combine(dir, "data", "debug.keystore")));
                using (ZipArchive zip = ZipFile.OpenRead(apk))
                {
                    Assert.NotNull(zip.GetEntry("AndroidManifest.xml"));
                    bool signed = false;
                    foreach (ZipArchiveEntry entry in zip.Entries)
                    {
                        if (entry.FullName.StartsWith("META-INF/", StringComparison.Ordinal) && entry.FullName.EndsWith(".SF", StringComparison.Ordinal))
                            signed = true;
                    }
                    Assert.True(signed);
                }
            }
            catch (VireError err)
            {
                if (err.Message.IndexOf("not installed", StringComparison.Ordinal) >= 0)
                {
                    Assert.Fail("env ANDROID_SDK_ROOT or ANDROID_HOME (build-tools aapt/zipalign/apksigner.jar, platforms/android-35/android.jar) and JAVA_HOME required; " + err.Message);
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
