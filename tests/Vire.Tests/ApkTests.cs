using System;
using System.IO;
using System.IO.Compression;
using Xunit;

public class ApkTests
{
    [Fact]
    public void PackWritesApkWithManifest()
    {
        string dir = Path.Combine(Path.GetTempPath(), "vire-apk-" + Guid.NewGuid().ToString("N"));
        Directory.CreateDirectory(dir);
        try
        {
            if (!OperatingSystem.IsWindows())
            {
                VireError err = Assert.Throws<VireError>(() => VireApk.Pack(dir, 1, 1));
                Assert.Contains("not installed", err.Message);
                return;
            }
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
        finally
        {
            try { Directory.Delete(dir, true); } catch (IOException) { }
        }
    }
}
