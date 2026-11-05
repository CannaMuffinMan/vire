using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.IO;
using Xunit;

public class ForeignTextTests
{
    [Fact]
    public void ForeignPassesTextAndReturnsTextOrIntFromFixtureDll()
    {
        string root = Worktree();
        string dir = Path.Combine(root, "tests", "fixtures", "foreign-text");
        Directory.CreateDirectory(dir);
        string dll = Path.Combine(dir, "echo.dll");
        try
        {
            CompileEcho(dir);
            Assert.True(File.Exists(dll));

            string src = string.Join("\n", new string[]
            {
                "define main",
                "  return (foreign with \"echo.dll\", \"vire_echo\", \"text\", \"hi\")",
                "end",
                ""
            });
            File.WriteAllText(Path.Combine(dir, "prog.vire"), src);
            Dictionary<string, Func> funcs = Program.Load(Path.Combine(dir, "prog.vire"), dir, new HashSet<string>());
            Machine machine = new Machine(funcs, dir);
            object echoed = machine.Call("main", new List<object>(), 1, 1);
            Assert.Equal("hi", echoed);

            object len = machine.Call("foreign", new List<object> { "echo.dll", "vire_len", "hi" }, 1, 1);
            Assert.Equal(2, len);
            object cafe = machine.Call("foreign", new List<object> { "echo.dll", "vire_echo", "text", "caf\u00e9" }, 1, 1);
            Assert.Equal("caf\u00e9", cafe);

            Budget budget = new Budget();
            CompiledMachine compiled = new CompiledMachine(new Dictionary<string, object>(), dir, new List<object>(), budget);
            object compiledEcho = compiled.Call("foreign", new List<object> { "echo.dll", "vire_echo", "text", "hi" }, 1, 1);
            Assert.Equal("hi", compiledEcho);
            object compiledLen = compiled.Call("foreign", new List<object> { "echo.dll", "vire_len", "number", "hi" }, 1, 1);
            Assert.Equal(2, compiledLen);

            VireError system = Assert.Throws<VireError>(() => machine.Call("foreign", new List<object> { "C:/Windows/System32/kernel32.dll", "GetTickCount" }, 1, 1));
            Assert.Contains("program folder", system.Message);
            VireError parent = Assert.Throws<VireError>(() => machine.Call("foreign", new List<object> { "../echo.dll", "vire_len", "hi" }, 1, 1));
            Assert.Contains("program folder", parent.Message);
            VireError remote = Assert.Throws<VireError>(() => machine.Call("foreign", new List<object> { "https://example.com/echo.dll", "vire_len" }, 1, 1));
            Assert.Contains("program folder", remote.Message);
        }
        finally
        {
            foreach (string name in new string[] { "echo.dll", "echo.obj", "echo.c", "echo.lib", "echo.exp", "prog.vire" })
            {
                try { File.Delete(Path.Combine(dir, name)); } catch (IOException) { } catch (UnauthorizedAccessException) { }
            }
        }
    }

    static void CompileEcho(string dir)
    {
        string src = string.Join("\n", new string[]
        {
            "#include <string.h>",
            "static char buf[4097];",
            "__declspec(dllexport) int vire_len(const char* s) {",
            "    if (!s) return -1;",
            "    return (int)strlen(s);",
            "}",
            "__declspec(dllexport) const char* vire_echo(const char* s) {",
            "    buf[0] = 0;",
            "    if (!s) return buf;",
            "    strncpy(buf, s, 4096);",
            "    buf[4096] = 0;",
            "    return buf;",
            "}",
            ""
        });
        File.WriteAllText(Path.Combine(dir, "echo.c"), src);
        string vcvars = @"C:\Program Files (x86)\Microsoft Visual Studio\2022\BuildTools\VC\Auxiliary\Build\vcvars64.bat";
        string cl = @"C:\Program Files (x86)\Microsoft Visual Studio\2022\BuildTools\VC\Tools\MSVC\14.44.35207\bin\Hostx64\x64\cl.exe";
        string command = "call \"" + vcvars + "\" && \"" + cl + "\" /nologo /LD /O2 /utf-8 echo.c /Fe:echo.dll";
        ProcessStartInfo info = new ProcessStartInfo("cmd.exe", "/d /c " + command);
        info.WorkingDirectory = dir;
        info.UseShellExecute = false;
        info.RedirectStandardOutput = true;
        info.RedirectStandardError = true;
        using (Process process = Process.Start(info))
        {
            string stdout = process.StandardOutput.ReadToEnd();
            string stderr = process.StandardError.ReadToEnd();
            process.WaitForExit();
            if (process.ExitCode != 0)
                throw new InvalidOperationException("cl failed " + process.ExitCode + " " + stdout + " " + stderr);
        }
    }

    static string Worktree()
    {
        string dir = AppContext.BaseDirectory;
        while (!string.IsNullOrEmpty(dir))
        {
            if (File.Exists(Path.Combine(dir, "vire.csproj"))) return dir;
            dir = Path.GetDirectoryName(dir);
        }
        throw new InvalidOperationException("worktree not found");
    }
}
