using System;
using System.Diagnostics;
using System.IO;
using System.Text;
using Xunit;

static class DualMode
{
    public static string TestKeyB64()
    {
        byte[] key = new byte[32];
        for (int i = 0; i < key.Length; i++) key[i] = (byte)(i + 3);
        return Convert.ToBase64String(key);
    }

    public static string FindRoot()
    {
        string dir = AppContext.BaseDirectory;
        for (int i = 0; i < 8; i++)
        {
            if (File.Exists(Path.Combine(dir, "vire.csproj")) && File.Exists(Path.Combine(dir, "tests.vire")))
                return dir;
            DirectoryInfo parent = Directory.GetParent(dir);
            if (parent == null) break;
            dir = parent.FullName;
        }
        throw new InvalidOperationException("could not find the vire repo root");
    }

    public static DualRun RunSource(string sourceText, string[] extraFiles)
    {
        string root = FindRoot();
        string work = Path.Combine(root, "data", "conformance", Guid.NewGuid().ToString("N"));
        Directory.CreateDirectory(work);
        Directory.CreateDirectory(Path.Combine(work, "data"));
        try
        {
            string dest = Path.Combine(work, "prog.vire");
            File.WriteAllText(dest, sourceText);
            if (extraFiles != null)
            {
                for (int i = 0; i < extraFiles.Length; i += 2)
                {
                    string rel = extraFiles[i];
                    string body = extraFiles[i + 1];
                    string full = Path.Combine(work, rel.Replace('/', Path.DirectorySeparatorChar));
                    string parent = Path.GetDirectoryName(full);
                    if (parent != null) Directory.CreateDirectory(parent);
                    File.WriteAllText(full, body);
                }
            }
            return CompareFile(root, dest, work);
        }
        finally
        {
            try { Directory.Delete(work, true); } catch (IOException) { }
        }
    }

    public static DualRun CompareFile(string root, string source, string work)
    {
        try
        {
        string destName = Path.GetFileName(source);
        Proc interp = RunVire(root, new string[] { destName }, work);
        string relDir = Path.Combine("data", "conformance", Path.GetFileName(work));
        string relSrc = Path.Combine(relDir, destName).Replace('\\', '/');
        string relVc = Path.Combine(relDir, Path.ChangeExtension(destName, ".vc")).Replace('\\', '/');
        Proc compile = RunVire(root, new string[] { "compiler.vire", relSrc, relVc }, root);
        if (compile.Code != 0)
        {
            return new DualRun(false, interp.Code, compile.Code, interp.Out, compile.Out, interp.Err, compile.Err);
        }
        Proc compiled = RunVire(root, new string[] { "run", relVc }, root);
        bool matched = interp.Code == compiled.Code
            && Norm(interp.Out) == Norm(compiled.Out)
            && Norm(interp.Err) == Norm(compiled.Err);
        return new DualRun(matched, interp.Code, compiled.Code, interp.Out, compiled.Out, interp.Err, compiled.Err);
        }
        finally
        {
            try { Directory.Delete(work, true); } catch (IOException) { }
        }
    }

    public static string Norm(string text)
    {
        return (text ?? "").Replace("\r\n", "\n");
    }

    public static Proc RunVire(string root, string[] args, string cwd)
    {
        string dll = typeof(Program).Assembly.Location;
        string dotnet = Environment.GetEnvironmentVariable("DOTNET_HOST_PATH");
        if (string.IsNullOrEmpty(dotnet)) dotnet = "dotnet";
        ProcessStartInfo info = new ProcessStartInfo();
        info.FileName = dotnet;
        StringBuilder argv = new StringBuilder();
        argv.Append("exec \"").Append(dll).Append("\"");
        foreach (string arg in args)
            argv.Append(" \"").Append(arg.Replace("\"", "\\\"")).Append("\"");
        info.Arguments = argv.ToString();
        info.WorkingDirectory = cwd;
        info.RedirectStandardOutput = true;
        info.RedirectStandardError = true;
        info.UseShellExecute = false;
        info.Environment["VIRE_SEAL_KEY"] = TestKeyB64();
        info.Environment["VIRE_BUDGET"] = "5000000";
        Process process = Process.Start(info);
        string stdout = process.StandardOutput.ReadToEnd();
        string stderr = process.StandardError.ReadToEnd();
        Assert.True(process.WaitForExit(120000), "vire process timed out");
        return new Proc(process.ExitCode, stdout, stderr);
    }

    public sealed class DualRun
    {
        public bool Matched;
        public int InterpCode;
        public int CompCode;
        public string InterpOut;
        public string CompOut;
        public string InterpErr;
        public string CompErr;

        public DualRun(bool matched, int interpCode, int compCode, string interpOut, string compOut, string interpErr, string compErr)
        {
            Matched = matched;
            InterpCode = interpCode;
            CompCode = compCode;
            InterpOut = interpOut;
            CompOut = compOut;
            InterpErr = interpErr;
            CompErr = compErr;
        }
    }

    public sealed class Proc
    {
        public int Code;
        public string Out;
        public string Err;
        public Proc(int code, string stdout, string stderr)
        {
            Code = code;
            Out = stdout;
            Err = stderr;
        }
    }
}
