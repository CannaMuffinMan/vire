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
            ForeignHost.PlaceKernel32(dir);
            int pid = VireForeign.CallArgs(dir, "kernel32.dll", "GetCurrentProcessId", new int[0], 1, 1);
            Assert.Equal(Environment.ProcessId, pid);

            int feature = VireForeign.CallArgs(dir, "kernel32.dll", "IsProcessorFeaturePresent", new int[] { PfXmmiInstructionsAvailable }, 1, 1);
            int expectedFeature = OperatingSystem.IsWindows()
                ? IsProcessorFeaturePresent(PfXmmiInstructionsAvailable)
                : 1;
            Assert.Equal(expectedFeature, feature);

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
