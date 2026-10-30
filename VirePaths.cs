using System;
using System.IO;

static class VirePaths
{
    static readonly string[] Devices =
    {
        "CON", "PRN", "AUX", "NUL",
        "COM1", "COM2", "COM3", "COM4", "COM5", "COM6", "COM7", "COM8", "COM9",
        "LPT1", "LPT2", "LPT3", "LPT4", "LPT5", "LPT6", "LPT7", "LPT8", "LPT9"
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
        int dot = name.IndexOf('.');
        if (dot >= 0) name = name.Substring(0, dot);
        name = name.TrimEnd('.', ' ').ToUpperInvariant();
        for (int i = 0; i < Devices.Length; i++)
            if (name == Devices[i]) return true;
        return false;
    }

    public static string NormalizedExtension(string path)
    {
        string leaf = Path.GetFileName(path ?? "");
        leaf = leaf.TrimEnd('.', ' ').ToLowerInvariant();
        return Path.GetExtension(leaf);
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
        RefuseProgram(null, path, line, 1);
    }

    public static void RefuseProgram(string path, int line, int column)
    {
        RefuseProgram(null, path, line, column);
    }

    public static void RefuseProgram(string root, string path, int line, int column)
    {
        string ext = NormalizedExtension(path);
        if (ext == ".js")
        {
            if (JsWriteAllowed(root, path)) return;
            throw new VireError("vire will not write a program file", line, column);
        }
        for (int i = 0; i < BlockedWriteExt.Length; i++)
        {
            if (ext == BlockedWriteExt[i])
                throw new VireError("vire will not write a program file", line, column);
        }
    }

    static bool JsWriteAllowed(string root, string path)
    {
        if (!string.IsNullOrEmpty(root) && !string.IsNullOrEmpty(path))
        {
            string site = Path.GetFullPath(Path.Combine(root, "site"));
            return InFolder(site, path);
        }
        string slash = (path ?? "").Replace('\\', '/');
        return slash.StartsWith("site/", StringComparison.OrdinalIgnoreCase);
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
                if ((File.Exists(cursor) || Directory.Exists(cursor)) &&
                    (File.GetAttributes(cursor) & FileAttributes.ReparsePoint) != 0)
                    throw new VireError("files stay inside the program folder", line, column);
            }
            catch (VireError) { throw; }
            catch (IOException) { throw new VireError("files stay inside the program folder", line, column); }
            catch (UnauthorizedAccessException) { throw new VireError("files stay inside the program folder", line, column); }
            string parent = Path.GetDirectoryName(cursor);
            if (string.IsNullOrEmpty(parent) || string.Equals(parent, cursor, StringComparison.OrdinalIgnoreCase)) break;
            cursor = parent;
        }
    }
}
