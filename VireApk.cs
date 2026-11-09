using System;
using System.Diagnostics;
using System.IO;
using System.IO.Compression;
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
        string tools = FindBuildTools();
        string aapt = FirstExisting(Path.Combine(tools, "aapt.exe"), Path.Combine(tools, "aapt"));
        string zipalign = FirstExisting(Path.Combine(tools, "zipalign.exe"), Path.Combine(tools, "zipalign"));
        string apksignerJar = Path.Combine(tools, "lib", "apksigner.jar");
        string javaHome = FindJavaHome();
        string java = FirstExisting(Path.Combine(javaHome, "bin", "java.exe"), Path.Combine(javaHome, "bin", "java"));
        string androidJar = FindAndroidJar();
        if (aapt == null || zipalign == null || !File.Exists(apksignerJar) || androidJar == null)
            return PackZipSigned(root, javaHome, line, col);
        if (java == null) throw new VireError("java is not installed", line, col);
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
                "package", "-f", "-M", manifest, "-I", androidJar, "-F", output
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
        string javaHome = FindJavaHome();
        string keytool = FirstExisting(Path.Combine(javaHome, "bin", "keytool.exe"), Path.Combine(javaHome, "bin", "keytool"));
        if (keytool == null) throw new VireError("keytool is not installed", line, col);
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
        string javaHome = FindJavaHome();
        string tools = FindBuildTools();
        info.Environment["PATH"] = tools + Path.PathSeparator + Path.Combine(javaHome, "bin") + Path.PathSeparator + path;
        if (java) info.Environment["JAVA_HOME"] = javaHome;
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

    static string PackZipSigned(string root, string javaHome, int line, int col)
    {
        string java = FirstExisting(Path.Combine(javaHome, "bin", "java.exe"), Path.Combine(javaHome, "bin", "java"));
        string jarsigner = FirstExisting(Path.Combine(javaHome, "bin", "jarsigner.exe"), Path.Combine(javaHome, "bin", "jarsigner"));
        if (java == null) throw new VireError("java is not installed", line, col);
        if (jarsigner == null) throw new VireError("jarsigner is not installed", line, col);
        string data = Path.Combine(root, "data");
        Directory.CreateDirectory(data);
        string output = Path.Combine(data, "app.apk");
        string work = Path.Combine(Path.GetTempPath(), "vire-apk-" + Guid.NewGuid().ToString("N"));
        Directory.CreateDirectory(work);
        try
        {
            using (FileStream stream = File.Create(output))
            using (ZipArchive zip = new ZipArchive(stream, ZipArchiveMode.Create))
            {
                ZipArchiveEntry entry = zip.CreateEntry("AndroidManifest.xml", CompressionLevel.Optimal);
                using (StreamWriter writer = new StreamWriter(entry.Open(), new UTF8Encoding(false)))
                    writer.Write(ManifestText());
            }
            string keystore = Path.Combine(data, "debug.keystore");
            EnsureDebugKeystore(keystore, work, line, col);
            RunTool(jarsigner, new string[]
            {
                "-keystore", keystore,
                "-storepass", DebugStorePass,
                "-keypass", DebugStorePass,
                output,
                DebugAlias
            }, work, line, col, true);
            if (!File.Exists(output) || new FileInfo(output).Length < 8)
                throw new VireError("aapt did not write data/app.apk", line, col);
            return "data/app.apk";
        }
        finally
        {
            try { Directory.Delete(work, true); } catch (Exception) { }
        }
    }

    static string FindBuildTools()
    {
        string sdk = Environment.GetEnvironmentVariable("ANDROID_SDK_ROOT");
        if (string.IsNullOrEmpty(sdk)) sdk = Environment.GetEnvironmentVariable("ANDROID_HOME");
        if (!string.IsNullOrEmpty(sdk))
        {
            string root = Path.Combine(sdk, "build-tools");
            if (Directory.Exists(root))
            {
                string[] versions = Directory.GetDirectories(root);
                Array.Sort(versions);
                if (versions.Length > 0) return versions[versions.Length - 1];
            }
        }
        if (Directory.Exists(BuildTools)) return BuildTools;
        return BuildTools;
    }

    static string FindAndroidJar()
    {
        if (File.Exists(AndroidJar)) return AndroidJar;
        string sdk = Environment.GetEnvironmentVariable("ANDROID_SDK_ROOT");
        if (string.IsNullOrEmpty(sdk)) sdk = Environment.GetEnvironmentVariable("ANDROID_HOME");
        if (string.IsNullOrEmpty(sdk)) return null;
        string jar = Path.Combine(sdk, "platforms", "android-35", "android.jar");
        return File.Exists(jar) ? jar : null;
    }

    static string FindJavaHome()
    {
        string home = Environment.GetEnvironmentVariable("JAVA_HOME");
        if (!string.IsNullOrEmpty(home) && Directory.Exists(home)) return home;
        if (Directory.Exists(JdkHome)) return JdkHome;
        string java = FindOnPath(OperatingSystem.IsWindows() ? "java.exe" : "java");
        if (java == null) return "";
        string bin = Path.GetDirectoryName(java);
        if (bin == null) return "";
        string parent = Path.GetDirectoryName(bin);
        return parent ?? "";
    }

    static string FindOnPath(string name)
    {
        string path = Environment.GetEnvironmentVariable("PATH") ?? "";
        string[] dirs = path.Split(Path.PathSeparator);
        for (int i = 0; i < dirs.Length; i++)
        {
            if (string.IsNullOrEmpty(dirs[i])) continue;
            string candidate = Path.Combine(dirs[i], name);
            if (File.Exists(candidate)) return candidate;
        }
        return null;
    }

    static string FirstExisting(string a, string b)
    {
        if (!string.IsNullOrEmpty(a) && File.Exists(a)) return a;
        if (!string.IsNullOrEmpty(b) && File.Exists(b)) return b;
        return null;
    }
}
