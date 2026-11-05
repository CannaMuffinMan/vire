using System;
using System.Diagnostics;
using System.IO;
using System.Text;

static class VireApk
{
    const string BuildTools = @"D:\Android\build-tools\35.0.0";
    const string AndroidJar = @"D:\Android\platforms\android-35\android.jar";
    const string JdkHome = @"C:\Program Files\Microsoft\jdk-21.0.13.21-hotspot";
    // Debug signature only. Not a production certificate. Password is a fixed test value and is not logged.
    const string DebugAlias = "androiddebugkey";
    const string DebugStorePass = "android";

    public static string Pack(string root, int line, int col)
    {
        string aapt = Path.Combine(BuildTools, "aapt.exe");
        string zipalign = Path.Combine(BuildTools, "zipalign.exe");
        string apksignerJar = Path.Combine(BuildTools, "lib", "apksigner.jar");
        string java = Path.Combine(JdkHome, "bin", "java.exe");
        if (!File.Exists(aapt)) throw new VireError("aapt is not installed: " + aapt, line, col);
        if (!File.Exists(zipalign)) throw new VireError("zipalign is not installed: " + zipalign, line, col);
        if (!File.Exists(apksignerJar)) throw new VireError("apksigner is not installed: " + apksignerJar, line, col);
        if (!File.Exists(java)) throw new VireError("java is not installed: " + java, line, col);
        if (!File.Exists(AndroidJar)) throw new VireError("android.jar is not installed: " + AndroidJar, line, col);
        string data = Path.Combine(root, "data");
        Directory.CreateDirectory(data);
        string output = Path.Combine(data, "app.apk");
        string work = Path.Combine(Path.GetTempPath(), "vire-apk-" + Guid.NewGuid().ToString("N"));
        Directory.CreateDirectory(work);
        try
        {
            string manifest = Path.Combine(work, "AndroidManifest.xml");
            File.WriteAllText(manifest, ManifestText(), new UTF8Encoding(false));
            RunTool(aapt, new string[]
            {
                "package", "-f", "-M", manifest, "-I", AndroidJar, "-F", output
            }, work, line, col, false);
            if (!File.Exists(output) || new FileInfo(output).Length < 8)
                throw new VireError("aapt did not write data/app.apk", line, col);
            string aligned = Path.Combine(work, "aligned.apk");
            RunTool(zipalign, new string[] { "-f", "-p", "4", output, aligned }, work, line, col, false);
            File.Copy(aligned, output, true);
            string keystore = Path.Combine(data, "debug.keystore");
            EnsureDebugKeystore(keystore, work, line, col);
            RunTool(java, new string[]
            {
                "-jar", apksignerJar,
                "sign",
                "--ks", keystore,
                "--ks-key-alias", DebugAlias,
                "--ks-pass", "pass:" + DebugStorePass,
                "--key-pass", "pass:" + DebugStorePass,
                "--v4-signing-enabled", "false",
                output
            }, work, line, col, true);
            RunTool(java, new string[] { "-jar", apksignerJar, "verify", "--min-sdk-version", "21", output }, work, line, col, true);
            return "data/app.apk";
        }
        finally
        {
            try { Directory.Delete(work, true); } catch (Exception) { }
        }
    }

    static void EnsureDebugKeystore(string keystore, string work, int line, int col)
    {
        if (File.Exists(keystore)) return;
        string keytool = Path.Combine(JdkHome, "bin", "keytool.exe");
        if (!File.Exists(keytool)) throw new VireError("keytool is not installed: " + keytool, line, col);
        RunTool(keytool, new string[]
        {
            "-genkeypair",
            "-keystore", keystore,
            "-alias", DebugAlias,
            "-keyalg", "RSA",
            "-keysize", "2048",
            "-validity", "10000",
            "-storepass", DebugStorePass,
            "-keypass", DebugStorePass,
            "-dname", "CN=Android Debug, O=Android, C=US",
            "-noprompt"
        }, work, line, col, true);
        if (!File.Exists(keystore)) throw new VireError("debug keystore was not created", line, col);
    }

    static string ManifestText()
    {
        return "<?xml version=\"1.0\" encoding=\"utf-8\"?>\n"
            + "<manifest xmlns:android=\"http://schemas.android.com/apk/res/android\" package=\"dev.vire.app\" android:versionCode=\"1\" android:versionName=\"1\">\n"
            + "  <uses-sdk android:minSdkVersion=\"21\" android:targetSdkVersion=\"35\" />\n"
            + "  <application android:label=\"Vire\" />\n"
            + "</manifest>\n";
    }

    static void RunTool(string file, string[] args, string work, int line, int col, bool java)
    {
        ProcessStartInfo info = new ProcessStartInfo();
        info.FileName = file;
        info.WorkingDirectory = work;
        info.UseShellExecute = false;
        info.RedirectStandardOutput = true;
        info.RedirectStandardError = true;
        info.CreateNoWindow = true;
        for (int i = 0; i < args.Length; i++) info.ArgumentList.Add(args[i]);
        string path = Environment.GetEnvironmentVariable("PATH") ?? "";
        info.Environment["PATH"] = BuildTools + ";" + Path.Combine(JdkHome, "bin") + ";" + path;
        if (java) info.Environment["JAVA_HOME"] = JdkHome;
        try
        {
            using (Process proc = Process.Start(info))
            {
                if (proc == null) throw new VireError("could not start " + Path.GetFileName(file), line, col);
                if (!proc.WaitForExit(60000))
                {
                    try { proc.Kill(true); } catch (Exception) { }
                    throw new VireError(Path.GetFileName(file) + " timed out", line, col);
                }
                string err = Redact(proc.StandardError.ReadToEnd());
                string stdout = Redact(proc.StandardOutput.ReadToEnd());
                if (proc.ExitCode != 0)
                {
                    string brief = FirstLine(err);
                    if (brief.Length == 0) brief = FirstLine(stdout);
                    if (brief.Length == 0) brief = Path.GetFileName(file) + " failed with exit " + proc.ExitCode;
                    throw new VireError(brief, line, col);
                }
            }
        }
        catch (VireError)
        {
            throw;
        }
        catch (Exception ex)
        {
            throw new VireError(Redact(ex.Message), line, col);
        }
    }

    static string Redact(string text)
    {
        if (text == null) return "";
        return text.Replace(DebugStorePass, "***");
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
}
