using System;
using System.Collections.Generic;
using System.IO;
using System.Security.Cryptography;
using System.Text;
using System.Threading;

static class VireDebug
{
    const int InspectCap = 100;
    const int WaitMs = 12000;
    static readonly object SessionsLock = new object();
    static readonly Dictionary<string, Session> Sessions = new Dictionary<string, Session>(StringComparer.OrdinalIgnoreCase);

    sealed class Session
    {
        public bool StepNext;
    }

    public static long ProbeCalls;

    public static bool Break(string root, string name, int line, string detail)
    {
        System.Threading.Interlocked.Increment(ref ProbeCalls);
        if (string.IsNullOrEmpty(root) || string.IsNullOrEmpty(name)) return false;
        try
        {
            string breakPath = VirePaths.DataOrSite(root, "data/break.txt", 1);
            string inspectPath = VirePaths.DataOrSite(root, "data/inspect.txt", 1);
            string breakFull = Path.GetFullPath(breakPath);
            string inspectFull = Path.GetFullPath(inspectPath);
            if (!VirePaths.UnderWritableZone(root, breakFull)) return false;
            if (!VirePaths.UnderWritableZone(root, inspectFull)) return false;
            string dir = Path.GetDirectoryName(inspectFull);
            if (string.IsNullOrEmpty(dir)) return false;
            Directory.CreateDirectory(dir);
            VirePaths.RefuseFileReparse(dir, root, 1, 1);
            VirePaths.RefuseFileReparse(breakFull, root, 1, 1);
            VirePaths.RefuseFileReparse(inspectFull, root, 1, 1);
            if (!File.Exists(breakFull)) return false;
            string[] marks = File.ReadAllLines(breakFull);
            bool hit = false;
            for (int i = 0; i < marks.Length; i++)
            {
                if (marks[i] == name)
                {
                    hit = true;
                    break;
                }
            }
            if (!hit) return false;
            int count = 0;
            if (File.Exists(inspectFull))
                count = File.ReadAllLines(inspectFull).Length;
            if (count >= InspectCap) return true;
            string safe = detail ?? "";
            safe = safe.Replace('\r', ' ').Replace('\n', ' ');
            File.AppendAllText(inspectFull, "stop " + name + " line " + line + " " + safe + "\n");
            if (!VirePaths.UnderWritableZone(root, Path.GetFullPath(inspectFull))) return false;
            return true;
        }
        catch (VireError) { return false; }
        catch (IOException) { return false; }
        catch (UnauthorizedAccessException) { return false; }
        catch (ArgumentException) { return false; }
        catch (NotSupportedException) { return false; }
    }

    public static void Reset(string root)
    {
        if (string.IsNullOrEmpty(root)) return;
        lock (SessionsLock)
        {
            Sessions.Remove(Path.GetFullPath(root));
        }
    }

    public static void Gate(string root, string file, int line, Env env)
    {
        if (Environment.GetEnvironmentVariable("VIRE_DEBUGGER") != "1") return;
        if (string.IsNullOrEmpty(root) || line < 1 || env == null) return;
        string key;
        try { key = Path.GetFullPath(root); }
        catch (ArgumentException) { return; }
        catch (NotSupportedException) { return; }
        Session session = Take(key);
        lock (session)
        {
            if (session.StepNext) session.StepNext = false;
            else if (!Marked(key, file, line)) return;
            string shown = file ?? "program.vire";
            try { shown = Path.GetFileName(shown); }
            catch (ArgumentException) { shown = "program.vire"; }
            if (string.IsNullOrEmpty(shown)) shown = "program.vire";
            Wait(key, shown, line, env, session);
        }
    }

    static Session Take(string key)
    {
        lock (SessionsLock)
        {
            Session session;
            if (!Sessions.TryGetValue(key, out session))
            {
                session = new Session();
                Sessions[key] = session;
            }
            return session;
        }
    }

    static void Wait(string root, string file, int line, Env env, Session session)
    {
        DateTime end = DateTime.UtcNow.AddMilliseconds(WaitMs);
        WriteStatus(root, file, line, env, null);
        while (DateTime.UtcNow < end)
        {
            string cmd = ReadCommand(root);
            if (cmd == null)
            {
                Thread.Sleep(20);
                continue;
            }
            if (cmd == "step")
            {
                session.StepNext = true;
                return;
            }
            if (cmd == "cont" || cmd == "continue") return;
            if (cmd.StartsWith("set ", StringComparison.Ordinal))
            {
                string error = ApplySet(env, cmd.Substring(4));
                WriteStatus(root, file, line, env, error);
                continue;
            }
            WriteStatus(root, file, line, env, "unknown command");
        }
        throw new VireError("debugger waited too long", line);
    }

    static string ApplySet(Env env, string rest)
    {
        if (rest == null) return "set needs a name";
        rest = rest.Trim();
        int space = rest.IndexOf(' ');
        if (space <= 0) return "set needs a name and a value";
        string name = rest.Substring(0, space);
        string raw = rest.Substring(space + 1).Trim();
        if (!IsName(name)) return "set needs a name";
        object value;
        string error = ParseValue(raw, out value);
        if (error != null) return error;
        env.Declare(name, value);
        return null;
    }

    static bool IsName(string name)
    {
        if (string.IsNullOrEmpty(name)) return false;
        char first = name[0];
        if (!(first >= 'A' && first <= 'Z') && !(first >= 'a' && first <= 'z') && first != '_') return false;
        for (int i = 1; i < name.Length; i++)
        {
            char ch = name[i];
            if ((ch >= 'A' && ch <= 'Z') || (ch >= 'a' && ch <= 'z') || (ch >= '0' && ch <= '9') || ch == '_') continue;
            return false;
        }
        return true;
    }

    static string ParseValue(string raw, out object value)
    {
        value = null;
        if (raw.Length >= 2 && raw[0] == '"' && raw[raw.Length - 1] == '"')
        {
            value = raw.Substring(1, raw.Length - 2).Replace("\\\"", "\"").Replace("\\\\", "\\");
            return null;
        }
        if (raw == "none") return null;
        if (raw == "true") { value = true; return null; }
        if (raw == "false") { value = false; return null; }
        int whole;
        if (int.TryParse(raw, out whole)) { value = whole; return null; }
        if (raw.IndexOf(' ') >= 0 || raw.IndexOf('\t') >= 0) return "set value needs quotes";
        value = raw;
        return null;
    }

    static string ReadCommand(string root)
    {
        string path = ZoneFile(root, "data/debug.cmd");
        if (path == null || !File.Exists(path)) return null;
        string text;
        try { text = File.ReadAllText(path); }
        catch (IOException) { return null; }
        catch (UnauthorizedAccessException) { return null; }
        if (text.IndexOf('\n') < 0 && text.IndexOf('\r') < 0) return null;
        try { File.Delete(path); }
        catch (IOException) { return null; }
        catch (UnauthorizedAccessException) { return null; }
        text = text.Replace('\r', ' ').Trim();
        int cut = text.IndexOf('\n');
        if (cut >= 0) text = text.Substring(0, cut).Trim();
        if (text.Length == 0) return null;
        return text;
    }

    static void WriteStatus(string root, string file, int line, Env env, string error)
    {
        StringBuilder body = new StringBuilder();
        body.Append("paused ").Append(file).Append(':').Append(line).Append('\n');
        if (error != null) body.Append("error ").Append(error.Replace('\r', ' ').Replace('\n', ' ')).Append('\n');
        List<string> names = new List<string>(env.Values.Keys);
        names.Sort(StringComparer.Ordinal);
        StringBuilder trace = new StringBuilder();
        trace.Append(file).Append(':').Append(line);
        for (int i = 0; i < names.Count; i++)
        {
            string rendered = Render(names[i], env.Values[names[i]]);
            body.Append(names[i]).Append('=').Append(rendered).Append('\n');
            trace.Append(' ').Append(names[i]).Append('=').Append(rendered);
        }
        trace.Append('\n');
        string status = body.ToString();
        string debugPath = ZoneFile(root, "data/debug.txt");
        if (debugPath != null) ReplaceText(debugPath, status);
        if (Environment.GetEnvironmentVariable("VIRE_TRACE") == "1")
        {
            string tracePath = ZoneFile(root, "data/trace.txt");
            if (tracePath != null) AppendText(tracePath, trace.ToString());
        }
    }

    static string Render(string name, object value)
    {
        if (value == null) return "none";
        if (value is bool) return (bool)value ? "true" : "false";
        if (value is int) return ((int)value).ToString();
        string text = value as string;
        if (text == null) return "value";
        if (LooksLikeSecret(name, text))
            return "len=" + text.Length + " sha256=" + Sha8(text);
        text = text.Replace('\r', ' ').Replace('\n', ' ');
        if (text.Length > 80) text = text.Substring(0, 80);
        return text;
    }

    static bool LooksLikeSecret(string name, string text)
    {
        if (text == null) return false;
        string lower = name == null ? "" : name.ToLowerInvariant();
        if (lower.Contains("key") || lower.Contains("token") || lower.Contains("secret") || lower.Contains("password") || lower.Contains("passwd"))
            return text.Length >= 8;
        if (text.Length >= 32 && AllHex(text)) return true;
        if (text.Length >= 40 && Base64ish(text)) return true;
        return false;
    }

    static bool AllHex(string text)
    {
        for (int i = 0; i < text.Length; i++)
        {
            char ch = text[i];
            if ((ch >= '0' && ch <= '9') || (ch >= 'a' && ch <= 'f') || (ch >= 'A' && ch <= 'F')) continue;
            return false;
        }
        return true;
    }

    static bool Base64ish(string text)
    {
        int pads = 0;
        for (int i = 0; i < text.Length; i++)
        {
            char ch = text[i];
            if (ch == '=') { pads++; continue; }
            if (pads > 0) return false;
            if ((ch >= 'A' && ch <= 'Z') || (ch >= 'a' && ch <= 'z') || (ch >= '0' && ch <= '9') || ch == '+' || ch == '/' || ch == '-' || ch == '_')
                continue;
            return false;
        }
        return pads <= 2;
    }

    static string Sha8(string text)
    {
        byte[] hash = SHA256.HashData(Encoding.UTF8.GetBytes(text));
        return hash[0].ToString("x2") + hash[1].ToString("x2") + hash[2].ToString("x2") + hash[3].ToString("x2");
    }

    static bool Marked(string root, string file, int line)
    {
        string path = ZoneFile(root, "data/break.txt");
        if (path == null || !File.Exists(path)) return false;
        string[] marks;
        try { marks = File.ReadAllLines(path); }
        catch (IOException) { return false; }
        catch (UnauthorizedAccessException) { return false; }
        string name = "program.vire";
        try
        {
            if (!string.IsNullOrEmpty(file)) name = Path.GetFileName(file);
        }
        catch (ArgumentException) { name = "program.vire"; }
        for (int i = 0; i < marks.Length; i++)
        {
            if (MarkHits(marks[i], name, line)) return true;
        }
        return false;
    }

    static bool MarkHits(string mark, string file, int line)
    {
        if (mark == null) return false;
        mark = mark.Trim();
        if (mark.Length == 0 || mark[0] == '#') return false;
        int colon = mark.LastIndexOf(':');
        if (colon > 0 && colon < mark.Length - 1)
        {
            int n;
            if (!int.TryParse(mark.Substring(colon + 1), out n) || n != line) return false;
            string left = mark.Substring(0, colon);
            if (left == "line") return true;
            return string.Equals(left, file, StringComparison.OrdinalIgnoreCase);
        }
        int bare;
        return int.TryParse(mark, out bare) && bare == line;
    }

    static string ZoneFile(string root, string rel)
    {
        try
        {
            string path = VirePaths.DataOrSite(root, rel, 1);
            string full = Path.GetFullPath(path);
            if (!VirePaths.UnderWritableZone(root, full)) return null;
            string dir = Path.GetDirectoryName(full);
            if (string.IsNullOrEmpty(dir)) return null;
            Directory.CreateDirectory(dir);
            VirePaths.RefuseFileReparse(dir, root, 1, 1);
            VirePaths.RefuseFileReparse(full, root, 1, 1);
            if (!VirePaths.UnderWritableZone(root, Path.GetFullPath(full))) return null;
            return full;
        }
        catch (VireError) { return null; }
        catch (IOException) { return null; }
        catch (UnauthorizedAccessException) { return null; }
        catch (ArgumentException) { return null; }
        catch (NotSupportedException) { return null; }
    }

    static void ReplaceText(string path, string text)
    {
        string tmp = path + ".tmp";
        try
        {
            File.WriteAllText(tmp, text);
            File.Move(tmp, path, true);
        }
        catch (IOException) { throw new VireError("debugger could not write status", 1); }
        catch (UnauthorizedAccessException) { throw new VireError("debugger could not write status", 1); }
    }

    static void AppendText(string path, string text)
    {
        try { File.AppendAllText(path, text); }
        catch (IOException) { throw new VireError("debugger could not write trace", 1); }
        catch (UnauthorizedAccessException) { throw new VireError("debugger could not write trace", 1); }
    }
}
