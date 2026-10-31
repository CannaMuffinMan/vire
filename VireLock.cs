using System;
using System.Collections.Generic;
using System.IO;
using System.Security.Cryptography;
using System.Text;

sealed class VireLockEntry
{
    public string Name;
    public string Version;
    public string Path;
    public string Hash;
    public int Line;
}

sealed class VireLockFile
{
    public List<VireLockEntry> Packages = new List<VireLockEntry>();
}

static class VireLock
{
    public const string FileName = "vire.lock";
    public const string Header = "vire.lock 1";
    public const int MaxLockBytes = 262144;
    public const int MaxLockLines = 512;
    public const int MaxLineChars = 1024;
    public const int MaxPackages = 64;
    public const int MaxFilesPerPackage = 4096;
    public const int MaxBytesPerPackage = 8 * 1024 * 1024;
    public const int MaxRelChars = 240;
    public const int MaxNameChars = 64;
    public const int MaxVersionChars = 32;
    public const int MaxWalkDepth = 16;

    public static int LockProject(string projectDir)
    {
        string root = DemandProject(projectDir);
        string text = BuildLockText(root);
        string dest = Path.Combine(root, FileName);
        VirePaths.RefuseReparse(dest, root, 1);
        VireFiles.WriteAllText(dest, text);
        Console.WriteLine("wrote " + FileName);
        return 0;
    }

    public static int VerifyProject(string projectDir)
    {
        string root = DemandProject(projectDir);
        VerifyOrThrow(root);
        Console.WriteLine("lock ok");
        return 0;
    }

    public static void VerifyOrThrow(string projectDir)
    {
        string root = DemandProject(projectDir);
        string path = Path.Combine(root, FileName);
        if (!File.Exists(path))
            throw new VireError("vire.lock is required to use a package (run vire pkg lock)", 1);
        VireLockFile lockfile = LoadFile(path);
        foreach (VireLockEntry entry in lockfile.Packages)
        {
            string actual = HashPackage(root, entry.Path, 1);
            if (!FixedEqual(actual, entry.Hash))
                throw new VireError("package " + entry.Name + " does not match vire.lock", 1);
        }
    }

    public static void GuardUse(string projectDir, string rel, int line)
    {
        GuardUse(projectDir, rel, line, 1);
    }

    public static void GuardUse(string projectDir, string rel, int line, int column)
    {
        string pkg;
        if (!TryVendoredPackage(rel, out pkg)) return;
        DemandPackage(projectDir, pkg, line, column);
    }

    public static void GuardNeed(string projectDir, string name, int line)
    {
        GuardNeed(projectDir, name, line, 1);
    }

    public static void GuardNeed(string projectDir, string name, int line, int column)
    {
        DemandPackage(projectDir, name, line, column);
    }

    public static object BuiltinGuard(List<object> args, int line, int column)
    {
        if (args == null || args.Count != 3)
            throw new VireError("pkgguard takes 3 values, got " + (args == null ? 0 : args.Count), line, column);
        string kind = args[0] as string;
        string root = args[1] as string;
        string spec = args[2] as string;
        if (kind == null || root == null || spec == null)
            throw new VireError("pkgguard needs text", line, column);
        if (kind == "use") GuardUse(root, spec, line, column);
        else if (kind == "need") GuardNeed(root, spec, line, column);
        else throw new VireError("pkgguard kind must be use or need", line, column);
        return 0;
    }

    public static VireLockFile Parse(byte[] raw)
    {
        if (raw == null) throw new VireError("vire.lock is malformed", 1);
        if (raw.Length > MaxLockBytes) throw new VireError("vire.lock is too large", 1);
        for (int i = 0; i < raw.Length; i++)
        {
            if (raw[i] == 0) throw new VireError("vire.lock is malformed", 1);
            if (raw[i] == (byte)'\r') throw new VireError("vire.lock must use lf line endings", 1);
        }
        if (raw.Length >= 3 && raw[0] == 0xef && raw[1] == 0xbb && raw[2] == 0xbf)
            throw new VireError("vire.lock is malformed", 1);
        string text;
        try { text = new UTF8Encoding(false, true).GetString(raw); }
        catch (DecoderFallbackException) { throw new VireError("vire.lock is malformed", 1); }
        return ParseText(text);
    }

    public static VireLockFile ParseText(string text)
    {
        if (text == null) throw new VireError("vire.lock is malformed", 1);
        if (text.Length > MaxLockBytes) throw new VireError("vire.lock is too large", 1);
        if (text.IndexOf('\0') >= 0 || text.IndexOf('\r') >= 0)
            throw new VireError(text.IndexOf('\r') >= 0 ? "vire.lock must use lf line endings" : "vire.lock is malformed", 1);
        string[] lines = text.Split('\n');
        if (lines.Length > MaxLockLines) throw new VireError("vire.lock has too many lines", 1);
        if (lines.Length == 0 || lines[0] != Header)
            throw new VireError("vire.lock must start with '" + Header + "'", 1);
        VireLockFile file = new VireLockFile();
        HashSet<string> names = new HashSet<string>(StringComparer.Ordinal);
        int last = lines.Length;
        if (last > 0 && lines[last - 1].Length == 0) last--;
        for (int i = 1; i < last; i++)
        {
            string line = lines[i];
            int n = i + 1;
            if (line.Length > MaxLineChars) throw new VireError("vire.lock line is too long", n);
            if (line.Length == 0) continue;
            if (line[0] == '#') continue;
            if (!line.StartsWith("pkg ", StringComparison.Ordinal))
                throw new VireError("vire.lock is malformed", n);
            string[] parts = SplitFields(line);
            if (parts.Length != 5) throw new VireError("vire.lock is malformed", n);
            VireLockEntry entry = new VireLockEntry();
            entry.Name = parts[1];
            entry.Version = parts[2];
            entry.Path = parts[3];
            entry.Hash = parts[4];
            entry.Line = n;
            CheckPackageName(entry.Name, n);
            CheckVersion(entry.Version, n);
            CheckLockPath(entry.Path, n);
            CheckHash(entry.Hash, n);
            if (!names.Add(entry.Name)) throw new VireError("package " + entry.Name + " is listed twice", n);
            if (file.Packages.Count >= MaxPackages) throw new VireError("vire.lock lists too many packages", n);
            file.Packages.Add(entry);
        }
        return file;
    }

    public static string HashPackage(string projectDir, string rel, int line)
    {
        string root = DemandProject(projectDir);
        CheckLockPath(rel, line);
        string full = VirePaths.CombineUnder(root, rel, line);
        if (!Directory.Exists(full))
            throw new VireError("package folder is missing", line);
        VirePaths.RefuseReparse(full, root, line);
        List<string> files = new List<string>();
        long bytes = 0;
        WalkFiles(root, full, full, 0, files, ref bytes, line);
        files.Sort(StringComparer.Ordinal);
        using (SHA256 sha = SHA256.Create())
        {
            for (int i = 0; i < files.Count; i++)
            {
                string relFile = files[i];
                byte[] nameBytes = Encoding.UTF8.GetBytes(relFile);
                sha.TransformBlock(nameBytes, 0, nameBytes.Length, null, 0);
                sha.TransformBlock(new byte[] { 10 }, 0, 1, null, 0);
                string abs = VirePaths.CombineUnder(root, rel + "/" + relFile, line);
                FileInfo info = new FileInfo(abs);
                if (!info.Exists) throw new VireError("package file is missing", line);
                if (info.Length > MaxBytesPerPackage) throw new VireError("package is too large to hash", line);
                byte[] len = new byte[8];
                ulong length = (ulong)info.Length;
                for (int b = 7; b >= 0; b--)
                {
                    len[b] = (byte)(length & 0xff);
                    length >>= 8;
                }
                sha.TransformBlock(len, 0, 8, null, 0);
                byte[] body;
                try { body = File.ReadAllBytes(abs); }
                catch (IOException) { throw new VireError("could not read a package file", line); }
                catch (UnauthorizedAccessException) { throw new VireError("could not read a package file", line); }
                if (body.Length > 0) sha.TransformBlock(body, 0, body.Length, null, 0);
            }
            sha.TransformFinalBlock(Array.Empty<byte>(), 0, 0);
            return ToHex(sha.Hash);
        }
    }

    public static bool TryVendoredPackage(string rel, out string name)
    {
        name = null;
        if (string.IsNullOrEmpty(rel)) return false;
        string slash = rel.Replace('\\', '/');
        while (slash.StartsWith("./", StringComparison.Ordinal)) slash = slash.Substring(2);
        string[] parts = slash.Split('/');
        if (parts.Length < 2) return false;
        if (!IsVendoredRoot(parts[0])) return false;
        name = parts[1];
        return name.Length > 0;
    }

    public static string PackageRel(string projectDir, string name)
    {
        string root = DemandProject(projectDir);
        string packages = Path.Combine(root, "packages", name);
        if (Directory.Exists(packages)) return "packages/" + name;
        string deps = Path.Combine(root, "deps", name);
        if (Directory.Exists(deps)) return "deps/" + name;
        return "packages/" + name;
    }

    static void DemandPackage(string projectDir, string name, int line, int column)
    {
        CheckPackageName(name, line);
        string root = DemandProject(projectDir);
        string lockPath = Path.Combine(root, FileName);
        if (!File.Exists(lockPath))
            throw new VireError("vire.lock is required to use a package (run vire pkg lock)", line, column);
        VireLockFile lockfile = LoadFile(lockPath);
        VireLockEntry found = null;
        for (int i = 0; i < lockfile.Packages.Count; i++)
        {
            if (lockfile.Packages[i].Name == name) { found = lockfile.Packages[i]; break; }
        }
        if (found == null)
            throw new VireError("package " + name + " is not in vire.lock", line, column);
        string actual = HashPackage(root, found.Path, line);
        if (!FixedEqual(actual, found.Hash))
            throw new VireError("package " + name + " does not match vire.lock", line, column);
    }

    static VireLockFile LoadFile(string path)
    {
        FileInfo info;
        try { info = new FileInfo(path); }
        catch (IOException) { throw new VireError("could not read vire.lock", 1); }
        catch (UnauthorizedAccessException) { throw new VireError("could not read vire.lock", 1); }
        if (!info.Exists) throw new VireError("vire.lock is required to use a package (run vire pkg lock)", 1);
        if (info.Length > MaxLockBytes) throw new VireError("vire.lock is too large", 1);
        byte[] raw;
        try { raw = File.ReadAllBytes(path); }
        catch (IOException) { throw new VireError("could not read vire.lock", 1); }
        catch (UnauthorizedAccessException) { throw new VireError("could not read vire.lock", 1); }
        return Parse(raw);
    }

    static string BuildLockText(string root)
    {
        List<VireLockEntry> entries = new List<VireLockEntry>();
        CollectRoot(root, "packages", entries);
        CollectRoot(root, "deps", entries);
        entries.Sort(delegate (VireLockEntry a, VireLockEntry b)
        {
            return string.CompareOrdinal(a.Name, b.Name);
        });
        if (entries.Count > MaxPackages) throw new VireError("too many packages to lock", 1);
        StringBuilder text = new StringBuilder();
        text.Append(Header);
        text.Append('\n');
        HashSet<string> names = new HashSet<string>(StringComparer.Ordinal);
        for (int i = 0; i < entries.Count; i++)
        {
            VireLockEntry entry = entries[i];
            if (!names.Add(entry.Name))
                throw new VireError("package " + entry.Name + " is listed twice", 1);
            text.Append("pkg ");
            text.Append(entry.Name);
            text.Append(' ');
            text.Append(entry.Version);
            text.Append(' ');
            text.Append(entry.Path);
            text.Append(' ');
            text.Append(entry.Hash);
            text.Append('\n');
        }
        return text.ToString();
    }

    static void CollectRoot(string root, string folder, List<VireLockEntry> entries)
    {
        string full = Path.Combine(root, folder);
        if (!Directory.Exists(full)) return;
        VirePaths.RefuseReparse(full, root, 1);
        string[] dirs;
        try { dirs = Directory.GetDirectories(full); }
        catch (IOException) { throw new VireError("could not read " + folder, 1); }
        catch (UnauthorizedAccessException) { throw new VireError("could not read " + folder, 1); }
        for (int i = 0; i < dirs.Length; i++)
        {
            string name = Path.GetFileName(dirs[i]);
            CheckPackageName(name, 1);
            VirePaths.RefuseReparse(dirs[i], root, 1);
            VireLockEntry entry = new VireLockEntry();
            entry.Name = name;
            entry.Version = ReadVersion(dirs[i]);
            entry.Path = folder + "/" + name;
            entry.Hash = HashPackage(root, entry.Path, 1);
            entries.Add(entry);
        }
    }

    static string ReadVersion(string dir)
    {
        string path = Path.Combine(dir, "VERSION");
        if (!File.Exists(path)) return "0";
        string text;
        try { text = File.ReadAllText(path); }
        catch (IOException) { return "0"; }
        catch (UnauthorizedAccessException) { return "0"; }
        string first = text.Replace('\r', '\n').Split('\n')[0].Trim();
        if (first.Length == 0 || first.Length > MaxVersionChars) return "0";
        try { CheckVersion(first, 1); return first; }
        catch (VireError) { return "0"; }
    }

    static void WalkFiles(string root, string packageRoot, string dir, int depth, List<string> files, ref long bytes, int line)
    {
        if (depth > MaxWalkDepth) throw new VireError("package folder is nested too deeply", line);
        VirePaths.RefuseReparse(dir, root, line);
        string[] found;
        try { found = Directory.GetFiles(dir); }
        catch (IOException) { throw new VireError("could not read a package file", line); }
        catch (UnauthorizedAccessException) { throw new VireError("could not read a package file", line); }
        for (int i = 0; i < found.Length; i++)
        {
            VirePaths.RefuseReparse(found[i], root, line);
            if (files.Count >= MaxFilesPerPackage) throw new VireError("package has too many files", line);
            FileInfo info = new FileInfo(found[i]);
            if (info.Length < 0 || bytes + info.Length > MaxBytesPerPackage)
                throw new VireError("package is too large to hash", line);
            bytes += info.Length;
            string rel = found[i].Substring(packageRoot.Length).TrimStart(Path.DirectorySeparatorChar, Path.AltDirectorySeparatorChar);
            rel = rel.Replace('\\', '/');
            if (rel.Length == 0 || rel.Length > MaxRelChars) throw new VireError("package path is too long", line);
            VirePaths.CheckName(rel, line);
            files.Add(rel);
        }
        string[] kids;
        try { kids = Directory.GetDirectories(dir); }
        catch (IOException) { throw new VireError("could not read a package file", line); }
        catch (UnauthorizedAccessException) { throw new VireError("could not read a package file", line); }
        for (int i = 0; i < kids.Length; i++)
            WalkFiles(root, packageRoot, kids[i], depth + 1, files, ref bytes, line);
    }

    static string DemandProject(string projectDir)
    {
        if (string.IsNullOrWhiteSpace(projectDir) || projectDir == ".")
            projectDir = Directory.GetCurrentDirectory();
        string root;
        try { root = Path.GetFullPath(projectDir); }
        catch (ArgumentException) { throw new VireError("files stay inside the program folder", 1); }
        catch (NotSupportedException) { throw new VireError("files stay inside the program folder", 1); }
        if (!Directory.Exists(root)) throw new VireError("files stay inside the program folder", 1);
        return root;
    }

    static void CheckPackageName(string name, int line)
    {
        if (name == null || name.Length == 0 || name.Length > MaxNameChars)
            throw new VireError("package names are plain words", line);
        if (VirePaths.IsDeviceName(name)) throw new VireError("package names are plain words", line);
        for (int i = 0; i < name.Length; i++)
        {
            char ch = name[i];
            if (!char.IsLetterOrDigit(ch) && ch != '_') throw new VireError("package names are plain words", line);
        }
    }

    static void CheckVersion(string version, int line)
    {
        if (version == null || version.Length == 0 || version.Length > MaxVersionChars)
            throw new VireError("vire.lock is malformed", line);
        int parts = 1;
        int run = 0;
        for (int i = 0; i < version.Length; i++)
        {
            char ch = version[i];
            if (ch == '.')
            {
                if (run == 0) throw new VireError("vire.lock is malformed", line);
                parts++;
                run = 0;
                if (parts > 4) throw new VireError("vire.lock is malformed", line);
                continue;
            }
            if (ch < '0' || ch > '9') throw new VireError("vire.lock is malformed", line);
            run++;
        }
        if (run == 0) throw new VireError("vire.lock is malformed", line);
    }

    static void CheckLockPath(string rel, int line)
    {
        if (rel == null || rel.Length == 0 || rel.Length > MaxRelChars)
            throw new VireError("vire.lock is malformed", line);
        if (rel.IndexOf('\\') >= 0) throw new VireError("vire.lock is malformed", line);
        VirePaths.CheckName(rel, line);
        string pkg;
        if (!TryVendoredPackage(rel, out pkg))
            throw new VireError("lock paths stay under packages/ or deps/", line);
        CheckPackageName(pkg, line);
    }

    static void CheckHash(string hash, int line)
    {
        if (hash == null || hash.Length != 64) throw new VireError("vire.lock is malformed", line);
        for (int i = 0; i < hash.Length; i++)
        {
            char ch = hash[i];
            bool hex = (ch >= '0' && ch <= '9') || (ch >= 'a' && ch <= 'f');
            if (!hex) throw new VireError("vire.lock is malformed", line);
        }
    }

    static bool IsVendoredRoot(string part)
    {
        return part == "packages" || part == "deps";
    }

    static string[] SplitFields(string line)
    {
        List<string> parts = new List<string>();
        int i = 0;
        while (i < line.Length)
        {
            if (line[i] == ' ')
            {
                i++;
                continue;
            }
            int start = i;
            while (i < line.Length && line[i] != ' ') i++;
            parts.Add(line.Substring(start, i - start));
            if (parts.Count > 8) break;
        }
        return parts.ToArray();
    }

    static bool FixedEqual(string left, string right)
    {
        if (left == null || right == null) return false;
        byte[] a = Encoding.UTF8.GetBytes(left);
        byte[] b = Encoding.UTF8.GetBytes(right);
        if (a.Length != b.Length) return false;
        return CryptographicOperations.FixedTimeEquals(a, b);
    }

    static string ToHex(byte[] bytes)
    {
        StringBuilder text = new StringBuilder(bytes.Length * 2);
        for (int i = 0; i < bytes.Length; i++) text.Append(bytes[i].ToString("x2"));
        return text.ToString();
    }
}
