using System;
using System.Diagnostics;
using System.IO;

static class ForeignHost
{
    public static void PlaceKernel32(string dir)
    {
        string dest = Path.Combine(dir, "kernel32.dll");
        if (OperatingSystem.IsWindows())
        {
            File.Copy(Path.Combine(Environment.SystemDirectory, "kernel32.dll"), dest);
            return;
        }
        string src = Path.Combine(dir, "kernel32.c");
        File.WriteAllText(src, string.Join("\n", new string[]
        {
            "#include <time.h>",
            "#include <unistd.h>",
            "__attribute__((visibility(\"default\"))) int GetTickCount(void) {",
            "    struct timespec ts;",
            "    clock_gettime(CLOCK_MONOTONIC, &ts);",
            "    return (int)(ts.tv_sec * 1000u + (unsigned)(ts.tv_nsec / 1000000));",
            "}",
            "__attribute__((visibility(\"default\"))) int GetCurrentProcessId(void) { return (int)getpid(); }",
            "__attribute__((visibility(\"default\"))) int IsProcessorFeaturePresent(int f) { (void)f; return 1; }",
            ""
        }));
        CompileShared(dir, src, dest);
    }

    public static void CompileShared(string dir, string source, string output)
    {
        string cc = Which("gcc") ?? Which("clang");
        if (cc == null) throw new InvalidOperationException("the C compiler is not installed");
        ProcessStartInfo info = new ProcessStartInfo(cc);
        info.WorkingDirectory = dir;
        info.UseShellExecute = false;
        info.RedirectStandardOutput = true;
        info.RedirectStandardError = true;
        info.ArgumentList.Add("-shared");
        info.ArgumentList.Add("-fPIC");
        info.ArgumentList.Add("-O2");
        info.ArgumentList.Add("-o");
        info.ArgumentList.Add(output);
        info.ArgumentList.Add(source);
        using (Process process = Process.Start(info))
        {
            string stdout = process.StandardOutput.ReadToEnd();
            string stderr = process.StandardError.ReadToEnd();
            process.WaitForExit();
            if (process.ExitCode != 0)
                throw new InvalidOperationException("cc failed " + process.ExitCode + " " + stdout + " " + stderr);
        }
    }

    static string Which(string name)
    {
        string path = Environment.GetEnvironmentVariable("PATH") ?? "";
        foreach (string dir in path.Split(Path.PathSeparator))
        {
            if (string.IsNullOrEmpty(dir)) continue;
            string candidate = Path.Combine(dir, name);
            if (File.Exists(candidate)) return candidate;
        }
        return null;
    }
}
