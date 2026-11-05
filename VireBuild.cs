using System;
using System.Diagnostics;
using System.IO;

static class VireBuild
{
    public static string Compile(string root, object kindObj, object sourceObj, int line, int col)
    {
        string kind = kindObj as string;
        string rel = sourceObj as string;
        if (kind == null || rel == null) throw new VireError("build needs text", line, col);
        string source = VirePaths.CombineUnder(root, rel, line, col);
        if (!source.EndsWith(".c", StringComparison.OrdinalIgnoreCase))
            throw new VireError("build only compiles a .c file", line, col);
        VirePaths.RefuseFileReparse(source, root, line, col);
        string stem = Path.GetFileNameWithoutExtension(source);
        if (stem.Length == 0 || stem.IndexOf('.') >= 0)
            throw new VireError("build needs a plain file name", line, col);
        for (int i = 0; i < stem.Length; i++)
        {
            char ch = stem[i];
            if (ch >= '0' && ch <= '9') continue;
            if (ch >= 'A' && ch <= 'Z') continue;
            if (ch >= 'a' && ch <= 'z') continue;
            if (ch == '_') continue;
            throw new VireError("build needs a plain file name", line, col);
        }
        string data = Path.Combine(root, "data");
        Directory.CreateDirectory(data);
        if (kind == "c") return RunC(root, source, Path.Combine(data, stem + ".exe"), line, col);
        if (kind == "android") return RunAndroid(root, source, Path.Combine(data, stem + ".o"), line, col);
        if (kind == "driver") return RunDriver(root, source, Path.Combine(data, stem + ".obj"), line, col);
        throw new VireError("build kind must be c, android, or driver", line, col);
    }

    static string RunC(string root, string source, string output, int line, int col)
    {
        string cl = FindCl();
        string kit = FindKit();
        string msvc = Path.GetDirectoryName(Path.GetDirectoryName(Path.GetDirectoryName(Path.GetDirectoryName(cl))));
        string include = string.Join(";", new string[]
        {
            Path.Combine(msvc, "include"),
            Path.Combine(kit, "ucrt"),
            Path.Combine(kit, "um"),
            Path.Combine(kit, "shared")
        });
        string lib = string.Join(";", new string[]
        {
            Path.Combine(msvc, "lib", "x64"),
            Path.Combine(KitLib(kit), "ucrt", "x64"),
            Path.Combine(KitLib(kit), "um", "x64")
        });
        RunTool(cl, new string[] { "/nologo", "/Fe:" + output, source }, include, lib, Path.GetDirectoryName(cl), root, line, col);
        if (!File.Exists(output)) throw new VireError("could not compile", line, col);
        return "data/" + Path.GetFileName(output);
    }

    static string RunAndroid(string root, string source, string output, int line, int col)
    {
        string so = Path.Combine(Path.GetDirectoryName(output), Path.GetFileNameWithoutExtension(output) + ".so");
        string clang = FindClang();
        RunTool(clang, new string[] { "--target=aarch64-linux-android35", "-shared", "-fPIC", "-o", so, source }, "", "", Path.GetDirectoryName(clang), root, line, col);
        if (!File.Exists(so) || new FileInfo(so).Length < 8) throw new VireError("could not compile", line, col);
        return "data/" + Path.GetFileName(so);
    }

    static string RunDriver(string root, string source, string output, int line, int col)
    {
        string cl = FindCl();
        string kit = FindKit();
        string include = string.Join(";", new string[]
        {
            Path.Combine(kit, "km"),
            Path.Combine(kit, "km", "crt"),
            Path.Combine(kit, "shared")
        });
        RunTool(cl, new string[] { "/nologo", "/c", "/kernel", "/GS-", "/D_AMD64_", "/Fo" + output, source }, include, "", Path.GetDirectoryName(cl), root, line, col);
        if (!File.Exists(output) || new FileInfo(output).Length < 8) throw new VireError("could not compile", line, col);
        string sys = Path.Combine(Path.GetDirectoryName(output), Path.GetFileNameWithoutExtension(output) + ".sys");
        string link = FindLink(cl);
        string lib = Path.Combine(KitLib(kit), "km", "x64");
        RunTool(link, new string[]
        {
            "/nologo",
            "/DRIVER",
            "/SUBSYSTEM:NATIVE",
            "/ENTRY:DriverEntry",
            "/NODEFAULTLIB",
            "/OUT:" + sys,
            output
        }, "", lib, Path.GetDirectoryName(link), root, line, col);
        if (!File.Exists(sys) || new FileInfo(sys).Length <= 512) throw new VireError("could not compile", line, col);
        return "data/" + Path.GetFileName(sys);
    }

    static void RunTool(string file, string[] args, string include, string lib, string toolDir, string root, int line, int col)
    {
        ProcessStartInfo info = new ProcessStartInfo();
        info.FileName = file;
        info.WorkingDirectory = root;
        info.UseShellExecute = false;
        info.RedirectStandardOutput = true;
        info.RedirectStandardError = true;
        info.CreateNoWindow = true;
        for (int i = 0; i < args.Length; i++) info.ArgumentList.Add(args[i]);
        if (include.Length > 0) info.Environment["INCLUDE"] = include;
        if (lib.Length > 0) info.Environment["LIB"] = lib;
        string path = Environment.GetEnvironmentVariable("PATH") ?? "";
        info.Environment["PATH"] = toolDir + ";" + path;
        using (Process proc = Process.Start(info))
        {
            if (proc == null) throw new VireError("could not compile", line, col);
            if (!proc.WaitForExit(60000))
            {
                try { proc.Kill(true); } catch (Exception) { }
                throw new VireError("could not compile", line, col);
            }
            string err = proc.StandardError.ReadToEnd();
            proc.StandardOutput.ReadToEnd();
            if (proc.ExitCode != 0)
            {
                string brief = FirstLine(err);
                if (brief.Length == 0) brief = "could not compile";
                throw new VireError(brief, line, col);
            }
        }
    }

    static string FirstLine(string text)
    {
        if (text == null) return "";
        int n = text.IndexOf('\n');
        string line = n >= 0 ? text.Substring(0, n) : text;
        line = line.Trim();
        if (line.Length > 180) line = line.Substring(0, 180);
        return line;
    }

    static string FindCl()
    {
        string root = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.ProgramFilesX86), "Microsoft Visual Studio", "2022", "BuildTools", "VC", "Tools", "MSVC");
        if (!Directory.Exists(root)) throw new VireError("the C compiler is not installed", 1);
        string[] versions = Directory.GetDirectories(root);
        Array.Sort(versions);
        for (int i = versions.Length - 1; i >= 0; i--)
        {
            string cl = Path.Combine(versions[i], "bin", "Hostx64", "x64", "cl.exe");
            if (File.Exists(cl)) return cl;
        }
        throw new VireError("the C compiler is not installed", 1);
    }

    static string FindLink(string cl)
    {
        string link = Path.Combine(Path.GetDirectoryName(cl), "link.exe");
        if (File.Exists(link)) return link;
        throw new VireError("the C compiler is not installed", 1);
    }

    static string FindKit()
    {
        string root = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.ProgramFilesX86), "Windows Kits", "10", "Include");
        if (!Directory.Exists(root)) throw new VireError("the driver kit is not installed", 1);
        string[] versions = Directory.GetDirectories(root);
        Array.Sort(versions);
        for (int i = versions.Length - 1; i >= 0; i--)
        {
            if (File.Exists(Path.Combine(versions[i], "km", "ntddk.h"))) return versions[i];
        }
        throw new VireError("the driver kit is not installed", 1);
    }

    static string KitLib(string include)
    {
        string ver = Path.GetFileName(include);
        return Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.ProgramFilesX86), "Windows Kits", "10", "Lib", ver);
    }

    static string FindClang()
    {
        string ndk = Environment.GetEnvironmentVariable("ANDROID_SDK_ROOT");
        if (string.IsNullOrEmpty(ndk)) ndk = "D:\\Android";
        string root = Path.Combine(ndk, "ndk");
        if (!Directory.Exists(root)) throw new VireError("the phone SDK is not installed", 1);
        string[] versions = Directory.GetDirectories(root);
        Array.Sort(versions);
        for (int i = versions.Length - 1; i >= 0; i--)
        {
            string clang = Path.Combine(versions[i], "toolchains", "llvm", "prebuilt", "windows-x86_64", "bin", "clang.exe");
            if (File.Exists(clang)) return clang;
        }
        throw new VireError("the phone SDK is not installed", 1);
    }
}
