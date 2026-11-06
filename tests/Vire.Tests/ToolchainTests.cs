using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.IO;
using Xunit;

public class ToolchainTests
{
    [Fact]
    public void BuildCompilesCAndroidAndDriver()
    {
        string dir = Path.Combine(Path.GetTempPath(), "vire-build-" + Guid.NewGuid().ToString("N"));
        Directory.CreateDirectory(dir);
        Directory.CreateDirectory(Path.Combine(dir, "data"));
        try
        {
            File.WriteAllText(Path.Combine(dir, "hello.c"), "int main(void){return 0;}\n");
            File.WriteAllText(Path.Combine(dir, "add.c"), "int add(int a, int b){return a+b;}\n");
            File.WriteAllText(Path.Combine(dir, "entry.c"),
                "#include <ntddk.h>\nNTSTATUS DriverEntry(PDRIVER_OBJECT DriverObject, PUNICODE_STRING RegistryPath){UNREFERENCED_PARAMETER(DriverObject);UNREFERENCED_PARAMETER(RegistryPath);return STATUS_SUCCESS;}\n");
            string src = "define main\n  say (build with \"c\", \"hello.c\")\n  say (build with \"android\", \"add.c\")\n  say (build with \"driver\", \"entry.c\")\nend\n";
            File.WriteAllText(Path.Combine(dir, "prog.vire"), src);
            Dictionary<string, Func> funcs = Program.Load(Path.Combine(dir, "prog.vire"), dir, new HashSet<string>());
            Machine machine = new Machine(funcs, dir);
            if (!OperatingSystem.IsWindows())
            {
                VireError err = Assert.Throws<VireError>(() => machine.Call("main", new List<object>(), 1, 1));
                Assert.Contains("not installed", err.Message);
                return;
            }
            TextWriter previous = Console.Out;
            StringWriter sink = new StringWriter();
            Console.SetOut(sink);
            try { machine.Call("main", new List<object>(), 1, 1); }
            finally { Console.SetOut(previous); }
            string text = sink.ToString().Replace("\r\n", "\n");
            Assert.Contains("data/hello.exe", text);
            Assert.Contains("data/add.so", text);
            Assert.Contains("data/entry.sys", text);
            Assert.True(new FileInfo(Path.Combine(dir, "data", "hello.exe")).Length > 100);
            Assert.True(new FileInfo(Path.Combine(dir, "data", "add.so")).Length > 100);
            Assert.True(new FileInfo(Path.Combine(dir, "data", "entry.obj")).Length > 8);
            Assert.True(new FileInfo(Path.Combine(dir, "data", "entry.sys")).Length > 512);
            Process hello = Process.Start(new ProcessStartInfo
            {
                FileName = Path.Combine(dir, "data", "hello.exe"),
                UseShellExecute = false,
                WorkingDirectory = dir
            });
            Assert.NotNull(hello);
            Assert.True(hello.WaitForExit(10000));
            Assert.Equal(0, hello.ExitCode);
        }
        finally
        {
            try { Directory.Delete(dir, true); } catch (IOException) { }
        }
    }
}
