using System;
using System.IO;
using System.Runtime.InteropServices;

static class VirePaths
{
    static readonly string[] Devices =
    {
        "CON", "PRN", "AUX", "NUL",
        "COM1", "COM2", "COM3", "COM4", "COM5", "COM6", "COM7", "COM8", "COM9",
        "LPT1", "LPT2", "LPT3", "LPT4", "LPT5", "LPT6", "LPT7", "LPT8", "LPT9",
        "CONIN$", "CONOUT$"
    };

    static readonly string[] BlockedWriteExt =
    {
        ".exe", ".dll", ".bat", ".cmd", ".ps1", ".com", ".scr", ".vbs", ".msi",
        ".vire", ".cs", ".sh", ".psm1", ".lnk", ".reg", ".hta", ".jar"
    };

    public static void CheckName(string raw, int line)
    {
        CheckName(raw, line, 1);
    }

    public static void CheckName(string raw, int line, int column)
    {
        if (raw == null || raw.Trim().Length == 0)
            throw new VireError("a file path must be text", line, column);
        if (raw.IndexOf('\0') >= 0)
            throw new VireError("files stay inside the program folder", line, column);
        if (Path.IsPathRooted(raw))
            throw new VireError("files stay inside the program folder", line, column);
        if (raw.IndexOf(':') >= 0)
            throw new VireError("files stay inside the program folder", line, column);
        string slash = raw.Replace('\\', '/');
        if (slash.StartsWith("/") || slash.StartsWith("//"))
            throw new VireError("files stay inside the program folder", line, column);
        string[] parts = slash.Split('/');
        if (parts.Length == 0)
            throw new VireError("files stay inside the program folder", line, column);
        for (int i = 0; i < parts.Length; i++)
        {
            string part = parts[i];
            if (part.Length == 0)
            {
                if (i == 0 || i == parts.Length - 1) continue;
                throw new VireError("files stay inside the program folder", line, column);
            }
            if (part == "." || part == "..")
                throw new VireError("files stay inside the program folder", line, column);
            if (part.EndsWith(".") || part.EndsWith(" "))
                throw new VireError("files stay inside the program folder", line, column);
            for (int n = 0; n < part.Length; n++)
            {
                char ch = part[n];
                if (ch < 32 || ch == '<' || ch == '>' || ch == '"' || ch == '|' || ch == '?' || ch == '*')
                    throw new VireError("files stay inside the program folder", line, column);
            }
            if (IsDeviceName(part))
                throw new VireError("files stay inside the program folder", line, column);
        }
    }

    public static bool IsDeviceName(string segment)
    {
        if (segment == null || segment.Length == 0) return false;
        string name = segment;
        int colon = name.IndexOf(':');
        if (colon >= 0) name = name.Substring(0, colon);
        int dot = name.IndexOf('.');
        if (dot >= 0) name = name.Substring(0, dot);
        name = name.TrimEnd('.', ' ').ToUpperInvariant();
        int tilde = name.IndexOf('~');
        if (tilde > 0 && tilde < name.Length - 1)
        {
            bool digits = true;
            for (int i = tilde + 1; i < name.Length; i++)
            {
                if (name[i] < '0' || name[i] > '9') digits = false;
            }
            if (digits) name = name.Substring(0, tilde);
        }
        for (int i = 0; i < Devices.Length; i++)
            if (name == Devices[i]) return true;
        return false;
    }

    public static string NormalizedExtension(string path)
    {
        string leaf = LeafOf(path);
        return Path.GetExtension(leaf);
    }

    public static string LeafOf(string path)
    {
        string leaf = Path.GetFileName(path ?? "");
        int colon = leaf.IndexOf(':');
        if (colon >= 0) leaf = leaf.Substring(0, colon);
        return leaf.TrimEnd('.', ' ').ToLowerInvariant();
    }

    static string ShortExtension(string ext)
    {
        if (ext == null || ext.Length < 2 || ext[0] != '.') return "";
        string body = ext.Substring(1);
        if (body.Length > 3) body = body.Substring(0, 3);
        return "." + body;
    }

    static bool ShortExtensionBlocked(string ext)
    {
        if (ext == null || ext.Length < 5) return false;
        string shortExt = ShortExtension(ext);
        if (shortExt.Length != 4) return false;
        for (int i = 0; i < BlockedWriteExt.Length; i++)
        {
            string blocked = BlockedWriteExt[i];
            if (blocked.Length == 4 && shortExt == blocked) return true;
        }
        if (shortExt == ".vir") return true;
        return false;
    }

    public static bool InFolder(string folder, string path)
    {
        string fullFolder = Path.GetFullPath(folder);
        string fullPath = Path.GetFullPath(path);
        string prefix = fullFolder.TrimEnd(Path.DirectorySeparatorChar, Path.AltDirectorySeparatorChar)
            + Path.DirectorySeparatorChar;
        return string.Equals(fullPath, fullFolder, StringComparison.OrdinalIgnoreCase) ||
            fullPath.StartsWith(prefix, StringComparison.OrdinalIgnoreCase);
    }

    public static bool UnderWritableZone(string root, string path)
    {
        string data = Path.GetFullPath(Path.Combine(root, "data"));
        string site = Path.GetFullPath(Path.Combine(root, "site"));
        return InFolder(data, path) || InFolder(site, path);
    }

    public static string CombineUnder(string root, string rel, int line)
    {
        return CombineUnder(root, rel, line, 1);
    }

    public static string CombineUnder(string root, string rel, int line, int column)
    {
        CheckName(rel, line, column);
        string full;
        try { full = Path.GetFullPath(Path.Combine(root, rel)); }
        catch (ArgumentException) { throw new VireError("files stay inside the program folder", line, column); }
        catch (NotSupportedException) { throw new VireError("files stay inside the program folder", line, column); }
        string baseFull = Path.GetFullPath(root);
        if (!InFolder(baseFull, full))
            throw new VireError("files stay inside the program folder", line, column);
        RefuseReparse(full, baseFull, line, column);
        return full;
    }

    public static string DataOrSite(string root, string rel, int line)
    {
        return DataOrSite(root, rel, line, 1);
    }

    public static string DataOrSite(string root, string rel, int line, int column)
    {
        string full = CombineUnder(root, rel, line, column);
        if (!UnderWritableZone(root, full))
            throw new VireError("files stay in data or site", line, column);
        return full;
    }

    public static string ProgramFile(string root, string rel, int line)
    {
        return ProgramFile(root, rel, line, 1);
    }

    public static string ProgramFile(string root, string rel, int line, int column)
    {
        if (rel == null || !rel.EndsWith(".vire", StringComparison.OrdinalIgnoreCase))
            throw new VireError("run needs a vire file in this folder", line, column);
        string full = CombineUnder(root, rel, line, column);
        if (UnderWritableZone(root, full))
            throw new VireError("run stays out of data and site", line, column);
        return full;
    }

    public static string UseFile(string root, string rel, int line)
    {
        return UseFile(root, rel, line, 1);
    }

    public static string UseFile(string root, string rel, int line, int column)
    {
        CheckName(rel, line, column);
        if (!rel.EndsWith(".vire", StringComparison.OrdinalIgnoreCase))
            throw new VireError("use stays inside the program folder and only opens .vire files", line, column);
        string full = CombineUnder(root, rel, line, column);
        if (UnderWritableZone(root, full))
            throw new VireError("use stays out of data and site", line, column);
        return full;
    }

    public static void RefuseProgram(string path, int line)
    {
        RefuseProgram(path, line, 1);
    }

    public static void RefuseProgram(string path, int line, int column)
    {
        if (HasStreamOrDevice(path))
            throw new VireError("vire will not write a program file", line, column);
        string leaf = LeafOf(path);
        if (leaf == "deps.lock")
            throw new VireError("vire will not write a program file", line, column);
        string ext = Path.GetExtension(leaf);
        if (ShortExtensionBlocked(ext))
            throw new VireError("vire will not write a program file", line, column);
        for (int i = 0; i < BlockedWriteExt.Length; i++)
        {
            if (ext == BlockedWriteExt[i])
                throw new VireError("vire will not write a program file", line, column);
        }
    }

    public static bool HasStreamOrDevice(string path)
    {
        if (string.IsNullOrEmpty(path)) return false;
        string text = path;
        if (text.StartsWith(@"\\.\", StringComparison.OrdinalIgnoreCase) ||
            text.StartsWith(@"\\?\", StringComparison.OrdinalIgnoreCase))
            return true;
        int colon = text.IndexOf(':');
        if (colon >= 0)
        {
            bool drive = colon == 1 && text.Length >= 2 && char.IsLetter(text[0]);
            if (!drive || text.IndexOf(':', colon + 1) >= 0) return true;
        }
        string leaf = Path.GetFileName(text.TrimEnd('.', ' ', '\\', '/'));
        return IsDeviceName(leaf);
    }

    public static bool LockHexEqual(string hashed, string locked)
    {
        int diff = 0;
        if (hashed == null || locked == null) diff = 1;
        int leftLen = hashed == null ? 0 : hashed.Length;
        int rightLen = locked == null ? 0 : locked.Length;
        diff |= leftLen ^ rightLen;
        for (int i = 0; i < 64; i++)
        {
            int a = hashed != null && i < hashed.Length ? hashed[i] : 0;
            int b = locked != null && i < locked.Length ? locked[i] : 0;
            diff |= a ^ b;
        }
        return diff == 0;
    }

    public static void RefuseFileReparse(string path, string root, int line, int column)
    {
        RefuseReparse(path, root, line, column);
        try
        {
            FileAttributes attrs = File.GetAttributes(path);
            if ((attrs & FileAttributes.ReparsePoint) != 0)
                throw new VireError("files stay inside the program folder", line, column);
        }
        catch (VireError) { throw; }
        catch (FileNotFoundException) { }
        catch (DirectoryNotFoundException) { }
        catch (IOException) { throw new VireError("files stay inside the program folder", line, column); }
        catch (UnauthorizedAccessException) { throw new VireError("files stay inside the program folder", line, column); }
    }

    public static void RefuseReparse(string path, string root, int line)
    {
        RefuseReparse(path, root, line, 1);
    }

    public static void RefuseReparse(string path, string root, int line, int column)
    {
        string cursor = path;
        string rootFull = Path.GetFullPath(root);
        while (!string.IsNullOrEmpty(cursor) && InFolder(rootFull, cursor))
        {
            try
            {
                if (File.Exists(cursor) || Directory.Exists(cursor))
                {
                    FileAttributes attr = File.GetAttributes(cursor);
                    if ((attr & FileAttributes.ReparsePoint) != 0)
                        throw new VireError("files stay inside the program folder", line, column);
                    if ((attr & FileAttributes.Directory) == 0 && LinkCount(cursor) > 1)
                        throw new VireError("files stay inside the program folder", line, column);
                }
            }
            catch (VireError) { throw; }
            catch (IOException) { throw new VireError("files stay inside the program folder", line, column); }
            catch (UnauthorizedAccessException) { throw new VireError("files stay inside the program folder", line, column); }
            string parent = Path.GetDirectoryName(cursor);
            if (string.IsNullOrEmpty(parent) || string.Equals(parent, cursor, StringComparison.OrdinalIgnoreCase)) break;
            cursor = parent;
        }
    }

    static int LinkCount(string path)
    {
        if (!OperatingSystem.IsWindows()) return 1;
        IntPtr handle = CreateFileW(path, 0, 7, IntPtr.Zero, 3, 0x02000000, IntPtr.Zero);
        if (handle == new IntPtr(-1)) return 1;
        try
        {
            ByHandleInfo info;
            if (!GetFileInformationByHandle(handle, out info)) return 1;
            return (int)info.NumberOfLinks;
        }
        finally
        {
            CloseHandle(handle);
        }
    }

    [StructLayout(LayoutKind.Sequential)]
    struct ByHandleInfo
    {
        public uint FileAttributes;
        public uint CreationLow;
        public uint CreationHigh;
        public uint AccessLow;
        public uint AccessHigh;
        public uint WriteLow;
        public uint WriteHigh;
        public uint VolumeSerialNumber;
        public uint FileSizeHigh;
        public uint FileSizeLow;
        public uint NumberOfLinks;
        public uint FileIndexHigh;
        public uint FileIndexLow;
    }

    [DllImport("kernel32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
    static extern IntPtr CreateFileW(string name, uint access, uint share, IntPtr security, uint disposition, uint flags, IntPtr template);

    [DllImport("kernel32.dll", SetLastError = true)]
    static extern bool GetFileInformationByHandle(IntPtr handle, out ByHandleInfo info);

    [DllImport("kernel32.dll", SetLastError = true)]
    static extern bool CloseHandle(IntPtr handle);
}
