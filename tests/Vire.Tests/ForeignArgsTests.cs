using System;
using System.IO;
using System.Runtime.InteropServices;
using Xunit;

public class ForeignArgsTests
{
    const int PfXmmiInstructionsAvailable = 6;

    [DllImport("kernel32.dll")]
    static extern int IsProcessorFeaturePresent(int processorFeature);

    [Fact]
    public void CallArgsPassesWholeNumbersInsideProgramFolder()
    {
        string dir = Path.Combine(Path.GetTempPath(), "vire-foreign-args-" + Guid.NewGuid().ToString("N"));
        Directory.CreateDirectory(dir);
        try
        {
            if (!OperatingSystem.IsWindows())
            {
                File.WriteAllBytes(Path.Combine(dir, "kernel32.dll"), new byte[] { 0x4D, 0x5A });
                VireError opened = Assert.Throws<VireError>(() => VireForeign.CallArgs(dir, "kernel32.dll", "GetCurrentProcessId", new int[0], 1, 1));
                Assert.Contains("could not open that dll", opened.Message);
                VireError linuxParent = Assert.Throws<VireError>(() => VireForeign.CallArgs(dir, "../kernel32.dll", "GetCurrentProcessId", new int[0], 1, 1));
                Assert.Contains("program folder", linuxParent.Message);
                return;
            }
            File.Copy(Path.Combine(Environment.SystemDirectory, "kernel32.dll"), Path.Combine(dir, "kernel32.dll"));
            int pid = VireForeign.CallArgs(dir, "kernel32.dll", "GetCurrentProcessId", new int[0], 1, 1);
            Assert.Equal(Environment.ProcessId, pid);

            int feature = VireForeign.CallArgs(dir, "kernel32.dll", "IsProcessorFeaturePresent", new int[] { PfXmmiInstructionsAvailable }, 1, 1);
            Assert.Equal(IsProcessorFeaturePresent(PfXmmiInstructionsAvailable), feature);

            VireError parent = Assert.Throws<VireError>(() => VireForeign.CallArgs(dir, "../kernel32.dll", "GetCurrentProcessId", new int[0], 1, 1));
            Assert.Contains("program folder", parent.Message);
            Assert.Throws<VireError>(() => VireForeign.CallArgs(dir, "kernel32.dll", "GetCurrentProcessId", new int[] { 1, 2, 3, 4, 5 }, 1, 1));
        }
        finally
        {
            try { Directory.Delete(dir, true); } catch (IOException) { } catch (UnauthorizedAccessException) { }
        }
    }
}
