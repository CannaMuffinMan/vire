using System;
using System.IO;
using System.Runtime.InteropServices;
using System.Text;
using Microsoft.Win32.SafeHandles;

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

    static StringComparison FolderComparison()
    {
        if (OperatingSystem.IsLinux()) return StringComparison.Ordinal;
        return StringComparison.OrdinalIgnoreCase;
    }

    public static bool InFolder(string folder, string path)
    {
        string fullFolder = Path.GetFullPath(folder);
        string fullPath = Path.GetFullPath(path);
        string prefix = fullFolder.TrimEnd(Path.DirectorySeparatorChar, Path.AltDirectorySeparatorChar)
            + Path.DirectorySeparatorChar;
        StringComparison cmp = FolderComparison();
        return string.Equals(fullPath, fullFolder, cmp) ||
            fullPath.StartsWith(prefix, cmp);
    }

    public static bool UnderWritableZone(string root, string path)
    {
        string data = Path.GetFullPath(Path.Combine(root, "data"));
        string site = Path.GetFullPath(Path.Combine(root, "site"));
        return InFolder(data, path) || InFolder(site, path);
    }

    // .vc files must live in data/ or site/. Using that directory as the
    // sandbox would require reads under data/data or data/site. One hop up
    // when the file sits directly in data/ or site/ matches interpreter
    // compiler.vire (repo root) so selfhost can pass data/compiler.vire.
    // Nested paths such as data/conformance/<id>/prog.vc stay nested.
    public static string FolderForCompiled(string compiled)
    {
        string folder = Path.GetDirectoryName(compiled);
        if (string.IsNullOrEmpty(folder)) folder = Directory.GetCurrentDirectory();
        string leaf = Path.GetFileName(folder);
        if (leaf != null &&
            (string.Equals(leaf, "data", FolderComparison()) ||
             string.Equals(leaf, "site", FolderComparison())))
        {
            string parent = Path.GetDirectoryName(folder);
            if (!string.IsNullOrEmpty(parent)) folder = parent;
        }
        return folder;
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

    public static string ReadAllTextInside(string path, string root, int line, int column)
    {
        using FileStream fs = OpenFile(path, FileMode.Open, FileAccess.Read);
        ConfirmOpenedWritable(fs.SafeFileHandle, root, line, column);
        using StreamReader reader = new StreamReader(fs, detectEncodingFromByteOrderMarks: true, leaveOpen: false);
        return reader.ReadToEnd();
    }

    public static void AppendAllTextInside(string path, string text, string root, int line, int column)
    {
        string parent = Path.GetDirectoryName(path);
        if (!string.IsNullOrEmpty(parent)) Directory.CreateDirectory(parent);
        using FileStream fs = OpenFile(path, FileMode.Append, FileAccess.Write);
        ConfirmOpenedWritable(fs.SafeFileHandle, root, line, column);
        using StreamWriter writer = new StreamWriter(fs, leaveOpen: false);
        writer.Write(text);
        writer.Flush();
    }

    public static string ReadProgramText(string path, string folder, int line, int column)
    {
        using FileStream fs = OpenFile(path, FileMode.Open, FileAccess.Read);
        ConfirmOpenedUnder(fs.SafeFileHandle, folder, line, column);
        using StreamReader reader = new StreamReader(fs, detectEncodingFromByteOrderMarks: true, leaveOpen: false);
        return reader.ReadToEnd();
    }

    static FileStream OpenFile(string path, FileMode mode, FileAccess access)
    {
        return new FileStream(path, mode, access, FileShare.ReadWrite | FileShare.Delete);
    }

    static void ConfirmOpenedWritable(SafeFileHandle handle, string root, int line, int column)
    {
        string final = FinalPathOf(handle, line, column);
        if (!UnderWritableZone(root, final))
            throw new VireError("files stay inside the program folder", line, column);
    }

    static void ConfirmOpenedUnder(SafeFileHandle handle, string root, int line, int column)
    {
        string final = FinalPathOf(handle, line, column);
        if (!InFolder(root, final))
            throw new VireError("files stay inside the program folder", line, column);
    }

    static string FinalPathOf(SafeFileHandle handle, int line, int column)
    {
        if (handle == null || handle.IsInvalid)
            throw new VireError("files stay inside the program folder", line, column);
        if (OperatingSystem.IsWindows())
        {
            StringBuilder buf = new StringBuilder(1024);
            uint n = GetFinalPathNameByHandleW(handle, buf, (uint)buf.Capacity, 0);
            if (n == 0 || n >= buf.Capacity)
                throw new VireError("files stay inside the program folder", line, column);
            string raw = buf.ToString();
            if (raw.StartsWith(@"\\?\", StringComparison.Ordinal)) raw = raw.Substring(4);
            return Path.GetFullPath(raw);
        }
        if (OperatingSystem.IsLinux())
        {
            int fd = handle.DangerousGetHandle().ToInt32();
            FileSystemInfo target = File.ResolveLinkTarget("/proc/self/fd/" + fd, true);
            if (target == null)
                throw new VireError("files stay inside the program folder", line, column);
            return Path.GetFullPath(target.FullName);
        }
        return Path.GetFullPath(".");
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
        if (OperatingSystem.IsLinux()) return LinuxLinkCount(path);
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

    [DllImport("kernel32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
    static extern uint GetFinalPathNameByHandleW(SafeFileHandle handle, StringBuilder filePath, uint cchFilePath, uint flags);

    [System.Runtime.Versioning.SupportedOSPlatform("linux")]
    static int LinuxLinkCount(string path)
    {
        ulong nlink;
        if (RuntimeInformation.ProcessArchitecture == Architecture.Arm64)
        {
            LinuxStatArm64 stat;
            if (LinuxLStatArm64(path, out stat) != 0) return 1;
            nlink = stat.Nlink;
        }
        else
        {
            LinuxStatX64 stat;
            if (LinuxLStatX64(path, out stat) != 0) return 1;
            nlink = stat.Nlink;
        }
        if (nlink > (ulong)int.MaxValue) return int.MaxValue;
        return (int)nlink;
    }

    [StructLayout(LayoutKind.Sequential)]
    struct LinuxStatX64
    {
        public ulong Dev;
        public ulong Ino;
        public ulong Nlink;
        public uint Mode;
        public uint Uid;
        public uint Gid;
        public int Pad;
        public ulong Rdev;
        public long Size;
        public long Blksize;
        public long Blocks;
        public long AtimSec;
        public long AtimNsec;
        public long MtimSec;
        public long MtimNsec;
        public long CtimSec;
        public long CtimNsec;
        public long Unused1;
        public long Unused2;
        public long Unused3;
    }

    [StructLayout(LayoutKind.Sequential)]
    struct LinuxStatArm64
    {
        public ulong Dev;
        public ulong Ino;
        public uint Mode;
        public uint Nlink;
        public uint Uid;
        public uint Gid;
        public ulong Rdev;
        public long Pad1;
        public long Size;
        public int Blksize;
        public int Pad2;
        public long Blocks;
        public long AtimSec;
        public long AtimNsec;
        public long MtimSec;
        public long MtimNsec;
        public long CtimSec;
        public long CtimNsec;
        public uint Unused1;
        public uint Unused2;
    }

    [System.Runtime.Versioning.SupportedOSPlatform("linux")]
    [DllImport("libc", EntryPoint = "lstat", SetLastError = true)]
    static extern int LinuxLStatX64(string path, out LinuxStatX64 stat);

    [System.Runtime.Versioning.SupportedOSPlatform("linux")]
    [DllImport("libc", EntryPoint = "lstat", SetLastError = true)]
    static extern int LinuxLStatArm64(string path, out LinuxStatArm64 stat);
}
