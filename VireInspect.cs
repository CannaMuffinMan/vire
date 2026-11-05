using System;
using System.IO;

static class VireInspect
{
    const int MaxLines = 200;
    const int MaxChars = 200;
    static readonly object Gate = new object();

    public static void Record(string root, string name, int line, string argsText)
    {
        if (Environment.GetEnvironmentVariable("VIRE_INSPECT") != "1") return;
        if (string.IsNullOrEmpty(root)) return;
        if (HasNewline(name) || HasNewline(argsText)) return;
        string text = (name ?? "") + " line " + line + " " + (argsText ?? "");
        if (text.Length > MaxChars) text = text.Substring(0, MaxChars);
        lock (Gate)
        {
            try
            {
                string path = InspectPath(root);
                if (path == null) return;
                string dir = Path.GetDirectoryName(path);
                if (string.IsNullOrEmpty(dir)) return;
                Directory.CreateDirectory(dir);
                path = InspectPath(root);
                if (path == null) return;
                if (CountLines(path) >= MaxLines) return;
                File.AppendAllText(path, text + "\n");
            }
            catch (VireError) { }
            catch (IOException) { }
            catch (UnauthorizedAccessException) { }
            catch (ArgumentException) { }
        }
    }

    static bool HasNewline(string text)
    {
        if (text == null) return false;
        return text.IndexOf('\n') >= 0 || text.IndexOf('\r') >= 0;
    }

    static string InspectPath(string root)
    {
        string path = VirePaths.DataOrSite(root, "data/inspect.txt", 1);
        string data = Path.GetFullPath(Path.Combine(root, "data"));
        string full = Path.GetFullPath(path);
        if (!VirePaths.InFolder(data, full)) return null;
        if (!string.Equals(Path.GetFileName(full), "inspect.txt", StringComparison.OrdinalIgnoreCase)) return null;
        VirePaths.RefuseFileReparse(full, root, 1, 1);
        if (!VirePaths.InFolder(data, Path.GetFullPath(full))) return null;
        return full;
    }

    static int CountLines(string path)
    {
        if (!File.Exists(path)) return 0;
        int count = 0;
        using (StreamReader reader = new StreamReader(path))
        {
            while (reader.ReadLine() != null) count++;
        }
        return count;
    }
}
