using System;
using System.Collections.Concurrent;
using System.IO;
using System.Threading;

static class VireFiles
{
    static readonly ConcurrentDictionary<string, object> PathGates = new ConcurrentDictionary<string, object>(StringComparer.OrdinalIgnoreCase);

    public static object Gate(string path)
    {
        string key = Path.GetFullPath(path ?? ".");
        return PathGates.GetOrAdd(key, _ => new object());
    }

    public static void WriteAllText(string path, string text)
    {
        object gate = Gate(path);
        lock (gate)
        {
            string parent = Path.GetDirectoryName(path);
            if (!string.IsNullOrEmpty(parent)) Directory.CreateDirectory(parent);
            string tmp = path + ".tmp." + Guid.NewGuid().ToString("N");
            try
            {
                File.WriteAllText(tmp, text);
                File.Move(tmp, path, true);
            }
            catch
            {
                try { if (File.Exists(tmp)) File.Delete(tmp); }
                catch (IOException) { }
                catch (UnauthorizedAccessException) { }
                throw;
            }
        }
    }

    public static void AppendAllText(string path, string text)
    {
        object gate = Gate(path);
        lock (gate)
        {
            string parent = Path.GetDirectoryName(path);
            if (!string.IsNullOrEmpty(parent)) Directory.CreateDirectory(parent);
            File.AppendAllText(path, text);
        }
    }

    public static void Copy(string from, string to)
    {
        object gate = Gate(to);
        lock (gate)
        {
            string parent = Path.GetDirectoryName(to);
            if (!string.IsNullOrEmpty(parent)) Directory.CreateDirectory(parent);
            File.Copy(from, to, true);
        }
    }

    public static void Erase(string path)
    {
        object gate = Gate(path);
        lock (gate)
        {
            if (File.Exists(path)) File.Delete(path);
        }
    }
}
