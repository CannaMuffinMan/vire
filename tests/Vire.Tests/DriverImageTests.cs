using System;
using System.IO;
using Xunit;

public class DriverImageTests
{
    [Fact]
    public void LinkedDriverImageIsPe()
    {
        string dir = Path.Combine(Path.GetTempPath(), "vire-driver-pe-" + Guid.NewGuid().ToString("N"));
        Directory.CreateDirectory(dir);
        try
        {
            if (!OperatingSystem.IsWindows())
            {
                File.WriteAllText(Path.Combine(dir, "entry.c"), "int x;\n");
                VireError err = Assert.Throws<VireError>(() => VireBuild.Compile(dir, "driver", "entry.c", 1, 1));
                Assert.Contains("not installed", err.Message);
                return;
            }
            File.WriteAllText(Path.Combine(dir, "entry.c"),
                "#include <ntddk.h>\nNTSTATUS DriverEntry(PDRIVER_OBJECT DriverObject, PUNICODE_STRING RegistryPath){UNREFERENCED_PARAMETER(DriverObject);UNREFERENCED_PARAMETER(RegistryPath);return STATUS_SUCCESS;}\n");
            string rel = VireBuild.Compile(dir, "driver", "entry.c", 1, 1);
            Assert.Equal("data/entry.sys", rel);
            string sys = Path.Combine(dir, "data", "entry.sys");
            byte[] image = File.ReadAllBytes(sys);
            Assert.True(image.Length > 0x40);
            Assert.Equal((byte)'M', image[0]);
            Assert.Equal((byte)'Z', image[1]);
            int pe = image[0x3C] | (image[0x3D] << 8) | (image[0x3E] << 16) | (image[0x3F] << 24);
            Assert.True(pe >= 0 && pe + 4 <= image.Length);
            Assert.Equal((byte)'P', image[pe]);
            Assert.Equal((byte)'E', image[pe + 1]);
            Assert.Equal((byte)0, image[pe + 2]);
            Assert.Equal((byte)0, image[pe + 3]);
        }
        finally
        {
            try { Directory.Delete(dir, true); } catch (IOException) { }
        }
    }
}
