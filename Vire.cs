using System;
using System.Collections.Generic;
using System.Globalization;
using System.IO;
using System.Net;
using System.Net.Http;
using System.Net.Sockets;
using System.Security.Cryptography;
using System.Text;
using System.Threading;
#if WINDOWS
using System.Windows.Forms;
#endif

sealed class VireError : Exception
{
    public int Line;
    public int Column;
    public VireError(string message, int line) : this(message, line, 1) { }
    public VireError(string message, int line, int column) : base(message)
    {
        Line = line;
        Column = column;
    }
}

sealed class ReturnSignal : Exception
{
    public object Value;
    public ReturnSignal(object value) { Value = value; }
}

sealed class StopSignal : Exception { }
sealed class SkipSignal : Exception { }
sealed class HaltSignal : Exception
{
    public int Code;
    public HaltSignal(int code) { Code = code; }
}

sealed class Token
{
    public string Kind;
    public object Value;
    public int Line;
    public int Column;
    public Token(string kind, object value, int line, int column)
    {
        Kind = kind;
        Value = value;
        Line = line;
        Column = column;
    }
}

sealed class Func
{
    public List<string> Params = new List<string>();
    public List<object> Body = new List<object>();
    public int Line;
    public int Column;
}

sealed class Env
{
    public Dictionary<string, object> Values = new Dictionary<string, object>();
    public void Declare(string name, object value) { Values[name] = value; }
    public bool Has(string name)
    {
        return Values.ContainsKey(name);
    }

    public object Get(string name, int line)
    {
        return Get(name, line, 1);
    }

    public object Get(string name, int line, int column)
    {
        if (Values.ContainsKey(name)) return Values[name];
        throw new VireError(name + " has no value", line, column);
    }
}

sealed class Stroke
{
    public string Kind;
    public int A, B, C, D, R, G, Blue;
    public Stroke(string kind, int a, int b, int c, int d, int r, int g, int blue)
    {
        Kind = kind; A = a; B = b; C = c; D = d; R = r; G = g; Blue = blue;
    }
}

#if WINDOWS
sealed class SheetBox : Panel
{
    public List<Stroke> Ops = new List<Stroke>();
    public SheetBox()
    {
        SetStyle(ControlStyles.AllPaintingInWmPaint | ControlStyles.UserPaint | ControlStyles.OptimizedDoubleBuffer, true);
        BackColor = System.Drawing.Color.White;
    }
    protected override void OnPaint(PaintEventArgs e)
    {
        base.OnPaint(e);
        foreach (Stroke mark in Ops)
        {
            System.Drawing.Color color = System.Drawing.Color.FromArgb(mark.R, mark.G, mark.Blue);
            using (System.Drawing.Pen pen = new System.Drawing.Pen(color, 2))
            using (System.Drawing.SolidBrush brush = new System.Drawing.SolidBrush(color))
            {
                if (mark.Kind == "fill") e.Graphics.FillRectangle(brush, mark.A, mark.B, mark.C, mark.D);
                else if (mark.Kind == "stroke") e.Graphics.DrawLine(pen, mark.A, mark.B, mark.C, mark.D);
                else e.Graphics.FillEllipse(brush, mark.A - mark.C, mark.B - mark.C, mark.C * 2, mark.C * 2);
            }
        }
    }
}
#endif

sealed class Budget
{
    public int Steps;
    public int MaxSteps = 1000000;
    public int Calls;
    public int MaxCalls = 64;
    public int WhilePasses;
    public int MaxWhilePasses = 1000000;
    public int Runs;
    public int MaxRuns = 8;
    public int Output;
    public int MaxOutput = 1000000;
    public long DeadlineUtcTicks;

    public void ApplyStepLimit(int limit)
    {
        if (limit < 1 || limit > 50000000) throw new VireError("budget must be from 1 to 50000000", 1);
        MaxSteps = limit;
        MaxWhilePasses = limit;
    }

    public static Budget ForRequest(Budget parent)
    {
        Budget fresh = new Budget();
        if (parent != null)
        {
            fresh.MaxSteps = parent.MaxSteps;
            fresh.MaxCalls = parent.MaxCalls;
            fresh.MaxWhilePasses = parent.MaxWhilePasses;
            fresh.MaxRuns = parent.MaxRuns;
            fresh.MaxOutput = parent.MaxOutput;
        }
        fresh.DeadlineUtcTicks = DateTime.UtcNow.AddSeconds(5).Ticks;
        return fresh;
    }

    public bool DeadlinePassed()
    {
        return DeadlineUtcTicks != 0 && DateTime.UtcNow.Ticks > DeadlineUtcTicks;
    }
}

static class ListenHooks
{
    internal static Exception RouteException;
    internal static readonly object ChainRouteLock = new object();

    internal static void Reset()
    {
        RouteException = null;
    }
}

sealed class Machine
{
    const int MaxItems = 100000;
    const int MaxText = 1000000;
    internal Budget budget = new Budget();
    List<object> programArgs = new List<object>();
    Dictionary<string, Func> funcs;
    string root;
    int depth;
    int nextTop = 16;
    int nextLeft = 16;
#if WINDOWS
    Form form;
    Dictionary<string, TextBox> boxes = new Dictionary<string, TextBox>();
    SheetBox sheet;
#endif
#if WINDOWS
    bool desk;
#else
    bool desk = true;
#endif
    string title;
    List<string> termLines = new List<string>();
    List<string> termFields = new List<string>();
    Dictionary<string, string> termValues = new Dictionary<string, string>();
    List<string> termButtons = new List<string>();
    List<string> termActions = new List<string>();
    List<Stroke> termOps = new List<Stroke>();
    bool termSheet;
    int inkR, inkG, inkB;
    string watchName;
    int watchLine;
    internal int ListenPort;

    static readonly HashSet<string> Builtins = new HashSet<string>(new string[] {
        "length", "push", "text", "number", "ask", "read", "write", "slice", "keys", "has", "kind", "join",
        "abs", "min", "max", "lower", "upper", "split", "find", "span", "drop", "sort", "escape", "serve",
        "files", "json", "parse", "now", "fetch", "post", "open", "line", "field", "button", "value", "show", "place", "mark",
        "sheet", "ink", "stroke", "fill", "dot", "watch", "term", "screen", "marks",
        "replace", "begins", "ends", "exists", "folders", "erase", "copy", "append",
        "round", "pick", "clear", "hash", "seal", "run", "sources", "args", "listen", "halt"
    });

    public Machine(Dictionary<string, Func> funcs, string root)
    {
        this.funcs = funcs;
        this.root = Path.GetFullPath(root);
    }

    public void Run() { Call("main", new List<object>(), 1); }

    public void UseBudget(int limit)
    {
        budget.ApplyStepLimit(limit);
    }

    public void UseShared(Budget shared)
    {
        if (shared == null) throw new VireError("budget must be from 1 to 50000000", 1);
        budget = shared;
    }

    public void UseArgs(List<object> values) { programArgs = values; }

    internal static int RequirePort(object value, int line)
    {
        int whole;
        if (value is int) whole = (int)value;
        else if (value is double) whole = (int)(double)value;
        else if (value is string && int.TryParse((string)value, out whole)) { }
        else throw new VireError("port must be a whole number", line);
        if (whole != 0 && (whole < 1024 || whole > 65535)) throw new VireError("port must be from 1024 to 65535", line);
        if (IsReservedListenPort(whole)) throw new VireError("that port is reserved", line);
        return whole;
    }

    internal static bool IsReservedListenPort(int port)
    {
        return port == 7099 || port == 8778 || port == 7071 || port == 7072 || port == 7093 || port == 17841 || port == 17843;
    }

    void Step(int line)
    {
        if (budget.DeadlinePassed()) throw new VireError("request ran too long", line);
        budget.Steps = System.Threading.Interlocked.Increment(ref budget.Steps);
        if (budget.Steps > budget.MaxSteps) throw new VireError("program ran too long and was stopped", line);
    }

    string SafePath(object text, int line)
    {
        return SafePath(text, line, 1);
    }

    string SafePath(object text, int line, int col)
    {
        string rawText = text as string;
        if (rawText == null || rawText.Trim().Length == 0)
            throw new VireError("a file path must be text", line, col);
        return VirePaths.DataOrSite(root, rawText, line, col);
    }

    public object Call(string name, List<object> args, int line)
    {
        return Call(name, args, line, 1);
    }

    public object Call(string name, List<object> args, int line, int col)
    {
        if (Builtins.Contains(name)) return Builtin(name, args, line, col);
        if (!funcs.ContainsKey(name))
            throw new VireError("there is no definition named " + name, line, col);
        Func func = funcs[name];
        if (args.Count != func.Params.Count)
            throw new VireError(name + " takes " + func.Params.Count + " values, got " + args.Count, line, col);
        budget.Calls++;
        try
        {
            if (budget.Calls > budget.MaxCalls) throw new VireError("definitions called too deeply", line, col);
            Env env = new Env();
            for (int i = 0; i < func.Params.Count; i++) env.Declare(func.Params[i], args[i]);
            try { ExecBlock(func.Body, env); }
            catch (ReturnSignal signal) { return signal.Value; }
            return null;
        }
        finally { budget.Calls--; }
    }

    object Builtin(string name, List<object> args, int line)
    {
        return Builtin(name, args, line, 1);
    }

    object Builtin(string name, List<object> args, int line, int col)
    {
        Step(line);
        int need = 1;
        if (name == "now" || name == "show" || name == "term" || name == "screen" || name == "marks" || name == "clear" || name == "args") need = 0;
        if (name == "push" || name == "write" || name == "has" || name == "join" || name == "min" || name == "max" || name == "split" || name == "find" || name == "span" || name == "button" || name == "place" || name == "sheet" || name == "begins" || name == "ends" || name == "copy" || name == "append" || name == "post") need = 2;
        if (name == "ink" || name == "dot" || name == "replace") need = 3;
        if (name == "stroke" || name == "fill") need = 4;
        if (name == "mark") need = 5;
        if (name == "serve" || name == "escape") need = 1;
        if (name == "slice") need = 3;
        if (args.Count != need) throw new VireError(name + " takes " + need + " values, got " + args.Count, line, col);
        if (name == "length")
        {
            if (args[0] is string) return ((string)args[0]).Length;
            if (args[0] is List<object>) return ((List<object>)args[0]).Count;
            if (args[0] is Dictionary<string, object>) return ((Dictionary<string, object>)args[0]).Count;
            throw new VireError("length needs text, a list, or a map", line, col);
        }
        if (name == "push")
        {
            List<object> list = args[0] as List<object>;
            if (list == null) throw new VireError("push needs a list", line, col);
            if (list.Count >= MaxItems) throw new VireError("list is too large", line, col);
            list.Add(args[1]);
            return list;
        }
        if (name == "text") return Show(args[0]);
        if (name == "number")
        {
            if (IsNum(args[0])) return args[0];
            string raw = args[0] as string;
            if (raw == null) throw new VireError("number needs text or a number", line, col);
            int whole;
            double real;
            if (raw.IndexOf('.') < 0 && int.TryParse(raw, out whole)) return whole;
            if (double.TryParse(raw, NumberStyles.Float, CultureInfo.InvariantCulture, out real)) return real;
            throw new VireError("that text is not a number", line, col);
        }
        if (name == "ask")
        {
            if (!(args[0] is string)) throw new VireError("ask needs text", line, col);
            Console.Write((string)args[0]);
            return Console.ReadLine() ?? "";
        }
        if (name == "read")
        {
            string path = SafePath(args[0], line, col);
            string text;
            try { text = File.ReadAllText(path); }
            catch (IOException) { throw new VireError("could not read that file", line, col); }
            catch (UnauthorizedAccessException) { throw new VireError("could not read that file", line, col); }
            if (text.Length > MaxText) throw new VireError("file is too large", line, col);
            return text;
        }
        if (name == "write")
        {
            string path = SafePath(args[0], line, col);
            string text = Show(args[1]);
            if (text.Length > MaxText) throw new VireError("text is too large to write", line, col);
            VirePaths.RefuseProgram(path, line, col);
            try
            {
                string parent = Path.GetDirectoryName(path);
                if (parent != null && parent.Length > 0) Directory.CreateDirectory(parent);
                if (VirePaths.NormalizedExtension(path) == ".vc") VireSeal.WritePacked(path, text);
                else VireFiles.WriteAllText(path, text);
            }
            catch (IOException) { throw new VireError("could not write that file", line, col); }
            catch (UnauthorizedAccessException) { throw new VireError("could not write that file", line, col); }
            return args[1];
        }
        if (name == "slice")
        {
            int start = AsInt(args[1], line);
            int end = AsInt(args[2], line);
            if (args[0] is string)
            {
                string s = (string)args[0];
                return SliceText(s, start, end);
            }
            List<object> list = args[0] as List<object>;
            if (list == null) throw new VireError("slice needs text or a list", line, col);
            return SliceList(list, start, end);
        }
        if (name == "keys")
        {
            Dictionary<string, object> map = args[0] as Dictionary<string, object>;
            if (map == null) throw new VireError("keys needs a map", line, col);
            return new List<object>(map.Keys);
        }
        if (name == "has")
        {
            Dictionary<string, object> map = args[0] as Dictionary<string, object>;
            if (map == null) throw new VireError("has needs a map", line, col);
            return map.ContainsKey(KeyOf(args[1], line));
        }
        if (name == "args") return programArgs;
        if (name == "halt")
        {
            if (!(args[0] is int)) throw new VireError("halt needs a whole number", line, col);
            throw new HaltSignal((int)args[0]);
        }
        if (name == "listen") { Listen(RequirePort(args[0], line), line); return null; }
        if (name == "kind") return KindOf(args[0]);
        if (name == "hash")
        {
            string raw = args[0] as string;
            if (raw == null) raw = Show(args[0]);
            return VireSeal.HashText(raw);
        }
        if (name == "seal")
        {
            string raw = args[0] as string;
            if (raw == null) throw new VireError("seal needs text", line, col);
            return VireSeal.Seal(raw);
        }
        if (name == "run")
        {
            string rel = args[0] as string;
            string full = VirePaths.ProgramFile(root, rel, line, col);
            budget.Runs++;
            StringWriter sink = new StringWriter();
            TextWriter previous = Console.Out;
            try
            {
                if (budget.Runs > budget.MaxRuns) throw new VireError("run went too deep", line, col);
                Console.SetOut(sink);
                Program.RunFile(full, root, budget);
            }
            finally
            {
                Console.SetOut(previous);
                budget.Runs--;
            }
            string text = sink.ToString().Replace("\r", "");
            Console.Write(text);
            string last = "";
            foreach (string row in text.Split('\n'))
                if (row.Trim().Length > 0) last = row.Trim();
            return last;
        }
        if (name == "abs")
        {
            if (!IsNum(args[0])) throw new VireError("abs needs a number", line, col);
            if (args[0] is int)
            {
                int n = (int)args[0];
                if (n == int.MinValue) return -(double)n;
                return n < 0 ? -n : n;
            }
            double real = (double)args[0];
            return real < 0 ? -real : real;
        }
        if (name == "min" || name == "max")
        {
            if (!IsNum(args[0]) || !IsNum(args[1])) throw new VireError(name + " needs two numbers", line, col);
            bool left = ToDouble(args[0]) <= ToDouble(args[1]);
            return name == "min" ? (left ? args[0] : args[1]) : (left ? args[1] : args[0]);
        }
        if (name == "lower" || name == "upper")
        {
            string raw = args[0] as string;
            if (raw == null) throw new VireError(name + " needs text", line, col);
            return name == "lower" ? raw.ToLowerInvariant() : raw.ToUpperInvariant();
        }
        if (name == "split")
        {
            string raw = args[0] as string;
            string sep = args[1] as string;
            if (raw == null || sep == null || sep.Length == 0) throw new VireError("split needs text and a separator", line, col);
            string[] bits = raw.Split(new string[] { sep }, StringSplitOptions.None);
            List<object> items = new List<object>();
            foreach (string bit in bits) items.Add(bit);
            return items;
        }
        if (name == "find")
        {
            string raw = args[0] as string;
            string needle = args[1] as string;
            if (raw == null || needle == null) throw new VireError("find needs two texts", line, col);
            return raw.IndexOf(needle);
        }
        if (name == "span")
        {
            if (!(args[0] is int) || !(args[1] is int)) throw new VireError("span needs two whole numbers", line, col);
            int from = (int)args[0];
            int to = (int)args[1];
            long count = (long)to - (long)from;
            if (count < 0 || count > MaxItems) throw new VireError("span is too large", line, col);
            List<object> items = new List<object>();
            int n = from;
            while (true)
            {
                items.Add(n);
                if (n == to) break;
                n++;
            }
            return items;
        }
        if (name == "drop")
        {
            List<object> list = args[0] as List<object>;
            if (list == null || list.Count == 0) throw new VireError("drop needs a non-empty list", line, col);
            object last = list[list.Count - 1];
            list.RemoveAt(list.Count - 1);
            return last;
        }
        if (name == "sort")
        {
            List<object> list = args[0] as List<object>;
            if (list == null) throw new VireError("sort needs a list of numbers", line, col);
            foreach (object item in list)
                if (!IsNum(item)) throw new VireError("sort needs a list of numbers", line, col);
            List<object> copy = new List<object>(list);
            copy.Sort(delegate(object a, object b) { return ToDouble(a).CompareTo(ToDouble(b)); });
            return copy;
        }
        if (name == "escape")
        {
            string raw = args[0] as string;
            if (raw == null) raw = Show(args[0]);
            return raw.Replace("&", "&amp;").Replace("<", "&lt;").Replace(">", "&gt;").Replace("\"", "&quot;");
        }
        if (name == "serve")
            throw new VireError("serve was removed; use listen", line, col);
        if (name == "files")
        {
            string path = SafePath(args[0], line, col);
            if (!Directory.Exists(path)) throw new VireError("there is no folder by that name", line, col);
            List<object> names = new List<object>();
            foreach (string file in Directory.GetFiles(path)) names.Add(Path.GetFileName(file));
            return names;
        }
        if (name == "sources")
        {
            string rel = args[0] as string;
            if (rel == null || rel.Length == 0 || rel.IndexOf('/') >= 0 || rel.IndexOf('\\') >= 0)
                throw new VireError("sources needs one folder name inside this program", line, col);
            VirePaths.CheckName(rel, line, col);
            string dir = VirePaths.CombineUnder(root, rel, line, col);
            if (!Directory.Exists(dir))
                throw new VireError("sources needs one folder name inside this program", line, col);
            if (VirePaths.UnderWritableZone(root, dir))
                throw new VireError("sources stays out of data and site", line, col);
            List<object> found = new List<object>();
            foreach (string file in Directory.GetFiles(dir, "*.vire")) found.Add(Path.GetFileName(file));
            return found;
        }
        if (name == "json") return Json.Write(args[0]);
        if (name == "parse")
        {
            string raw = args[0] as string;
            if (raw == null) throw new VireError("parse needs text", line, col);
            return Json.Read(raw, line);
        }
        if (name == "now") return DateTime.Now.ToString("yyyy-MM-dd HH:mm:ss");
        if (name == "fetch")
        {
            string url = args[0] as string;
            if (url == null || !(url.StartsWith("https://") || url.StartsWith("http://")))
                throw new VireError("fetch needs an http or https address", line, col);
            try { return VireNet.SendWeb(HttpMethod.Get, url, null, line, col); }
            catch (VireError) { throw; }
            catch (Exception) { throw new VireError("could not fetch that address", line, col); }
        }
        if (name == "post")
        {
            string url = args[0] as string;
            if (url == null || !(url.StartsWith("https://") || url.StartsWith("http://")))
                throw new VireError("post needs an http or https address", line, col);
            try
            {
                string payload = Show(args[1]);
                if (payload.Length > 1000000) throw new VireError("text is too large to send", line, col);
                return VireNet.SendWeb(HttpMethod.Post, url, payload, line, col);
            }
            catch (VireError) { throw; }
            catch (Exception) { throw new VireError("could not post to that address", line, col); }
        }
        if (name == "open")
        {
            string title = args[0] as string;
            if (title == null) throw new VireError("open needs a window title", line, col);
            OpenWindow(title);
            return 0;
        }
        if (name == "line")
        {
            string text = args[0] as string;
            if (text == null) text = Show(args[0]);
            AddLine(text, line);
            return 0;
        }
        if (name == "field")
        {
            string fieldName = args[0] as string;
            if (fieldName == null) throw new VireError("field needs a name", line, col);
            AddField(fieldName, line);
            return 0;
        }
        if (name == "button")
        {
            string label = args[0] as string;
            string func = args[1] as string;
            if (label == null || func == null) throw new VireError("button needs a label and a definition name", line, col);
            AddButton(label, func, line);
            return 0;
        }
        if (name == "place")
        {
            if (!(args[0] is int) || !(args[1] is int)) throw new VireError("place needs two whole numbers", line, col);
            if (title == null) throw new VireError("open a window first", line, col);
            nextLeft = (int)args[0];
            nextTop = (int)args[1];
            return 0;
        }
        if (name == "mark")
        {
            if (!(args[0] is int) || !(args[1] is int) || !(args[2] is int) || !(args[3] is int))
                throw new VireError("mark needs four whole numbers and a definition name", line, col);
            string func = args[4] as string;
            if (func == null) throw new VireError("mark needs four whole numbers and a definition name", line, col);
            AddMark((int)args[0], (int)args[1], (int)args[2], (int)args[3], func, line);
            return 0;
        }
        if (name == "sheet")
        {
            if (!(args[0] is int) || !(args[1] is int)) throw new VireError("sheet needs a width and a height", line, col);
            AddSheet((int)args[0], (int)args[1], line);
            return 0;
        }
        if (name == "ink")
        {
            int rr, gg, bb;
            ColorOf(args[0], args[1], args[2], line, out rr, out gg, out bb);
            inkR = rr; inkG = gg; inkB = bb;
            return 0;
        }
        if (name == "stroke")
        {
            Draw("stroke", args, line);
            return 0;
        }
        if (name == "fill")
        {
            Draw("fill", args, line);
            return 0;
        }
        if (name == "dot")
        {
            if (!(args[0] is int) || !(args[1] is int) || !(args[2] is int)) throw new VireError("dot needs three whole numbers", line, col);
            RequireSheet(line);
            Stroke mark = new Stroke("dot", (int)args[0], (int)args[1], (int)args[2], 0, inkR, inkG, inkB);
            if (desk) { termOps.Add(mark); return 0; }
#if WINDOWS
            sheet.Ops.Add(mark);
            sheet.Invalidate();
#endif
            return 0;
        }
        if (name == "watch")
        {
            string func = args[0] as string;
            if (func == null || !funcs.ContainsKey(func)) throw new VireError("watch needs a definition name", line, col);
            RequireSheet(line);
            watchName = func;
            watchLine = line;
            return 0;
        }
        if (name == "value")
        {
            string fieldName = args[0] as string;
            if (fieldName == null) throw new VireError("there is no field by that name", line, col);
            if (desk)
            {
                if (!termValues.ContainsKey(fieldName)) throw new VireError("there is no field by that name", line, col);
                return termValues[fieldName];
            }
#if WINDOWS
            TextBox box;
            if (!boxes.TryGetValue(fieldName, out box)) throw new VireError("there is no field by that name", line, col);
            return box.Text;
#else
            throw new VireError("there is no field by that name", line, col);
#endif
        }
        if (name == "show")
        {
            if (title == null) throw new VireError("open a window before show", line, col);
            if (desk) TermShow();
#if WINDOWS
            else Application.Run(form);
#else
            else TermShow();
#endif
            return 0;
        }
        if (name == "term")
        {
            desk = true;
            return "term";
        }
        if (name == "screen") return string.Join("\n", termLines.ToArray());
        if (name == "marks") return MarkList();
        if (name == "replace")
        {
            string raw = args[0] as string;
            string oldText = args[1] as string;
            string newer = args[2] as string;
            if (raw == null || oldText == null || newer == null) throw new VireError("replace needs three texts", line, col);
            return raw.Replace(oldText, newer);
        }
        if (name == "begins" || name == "ends")
        {
            string raw = args[0] as string;
            string edge = args[1] as string;
            if (raw == null || edge == null) throw new VireError(name + " needs two texts", line, col);
            return name == "begins" ? raw.StartsWith(edge) : raw.EndsWith(edge);
        }
        if (name == "exists") return File.Exists(SafePath(args[0], line, col)) || Directory.Exists(SafePath(args[0], line, col));
        if (name == "folders")
        {
            string path = SafePath(args[0], line, col);
            if (!Directory.Exists(path)) throw new VireError("there is no folder by that name", line, col);
            List<object> names = new List<object>();
            foreach (string dir in Directory.GetDirectories(path)) names.Add(Path.GetFileName(dir));
            return names;
        }
        if (name == "erase")
        {
            string path = SafePath(args[0], line, col);
            VirePaths.RefuseProgram(path, line, col);
            VireFiles.Erase(path);
            return true;
        }
        if (name == "copy")
        {
            string from = SafePath(args[0], line, col);
            string to = SafePath(args[1], line, col);
            VirePaths.RefuseProgram(to, line, col);
            try { VireFiles.Copy(from, to); }
            catch (IOException) { throw new VireError("could not write that file", line, col); }
            catch (UnauthorizedAccessException) { throw new VireError("could not write that file", line, col); }
            return args[1];
        }
        if (name == "append")
        {
            string path = SafePath(args[0], line, col);
            VirePaths.RefuseProgram(path, line, col);
            string text = Show(args[1]);
            if (text.Length > MaxText) throw new VireError("text is too large to write", line, col);
            try { VireFiles.AppendAllText(path, text); }
            catch (IOException) { throw new VireError("could not write that file", line, col); }
            catch (UnauthorizedAccessException) { throw new VireError("could not write that file", line, col); }
            return text;
        }
        if (name == "round")
        {
            if (!IsNum(args[0])) throw new VireError("round needs a number", line, col);
            double real = ToDouble(args[0]);
            if (double.IsNaN(real) || double.IsInfinity(real)) throw new VireError("round needs a number", line, col);
            double rounded = Math.Round(real, MidpointRounding.AwayFromZero);
            if (rounded > int.MaxValue || rounded < int.MinValue) return rounded;
            return (int)rounded;
        }
        if (name == "pick")
        {
            if (!(args[0] is int) || (int)args[0] < 1) throw new VireError("pick needs a whole number above zero", line, col);
            return new Random().Next((int)args[0]);
        }
        if (name == "clear")
        {
            termOps.Clear();
#if WINDOWS
            if (sheet != null) { sheet.Ops.Clear(); sheet.Invalidate(); }
#endif
            return 0;
        }
        List<object> parts = args[0] as List<object>;
        string joiner = args[1] as string;
        if (parts == null || joiner == null) throw new VireError("join needs a list of text", line, col);
        string[] joined = new string[parts.Count];
        for (int i = 0; i < parts.Count; i++)
        {
            if (!(parts[i] is string)) throw new VireError("join needs a list of text", line, col);
            joined[i] = (string)parts[i];
        }
        return string.Join(joiner, joined);
    }

    void OpenWindow(string titleText)
    {
        title = titleText;
        nextTop = 16;
        nextLeft = 16;
        termLines = new List<string>();
        termFields = new List<string>();
        termValues = new Dictionary<string, string>();
        termButtons = new List<string>();
        termActions = new List<string>();
        termOps = new List<Stroke>();
        termSheet = false;
        if (desk) return;
#if WINDOWS
        form = new Form();
        form.Text = titleText;
        form.Width = 520;
        form.Height = 420;
        form.StartPosition = FormStartPosition.CenterScreen;
        boxes = new Dictionary<string, TextBox>();
        sheet = null;
#else
        desk = true;
#endif
    }

    void AddLine(string text, int line)
    {
        if (title == null) throw new VireError("open a window first", line);
        if (desk) { termLines.Add(text); return; }
#if WINDOWS
        Label label = new Label();
        label.Text = text;
        label.Left = nextLeft;
        label.Top = nextTop;
        label.Width = 470;
        label.Height = 24;
        form.Controls.Add(label);
        nextTop += 28;
#endif
    }

    void AddField(string name, int line)
    {
        if (title == null) throw new VireError("open a window first", line);
        if (desk) { termFields.Add(name); termValues[name] = ""; return; }
#if WINDOWS
        TextBox box = new TextBox();
        box.Left = nextLeft;
        box.Top = nextTop;
        box.Width = 470;
        form.Controls.Add(box);
        boxes[name] = box;
        nextTop += 32;
#endif
    }

    void AddButton(string label, string func, int line)
    {
        if (title == null) throw new VireError("open a window first", line);
        if (!funcs.ContainsKey(func)) throw new VireError("there is no definition named " + func, line);
        if (desk) { termButtons.Add(label); termActions.Add(func); return; }
#if WINDOWS
        Button button = new Button();
        button.Text = label;
        button.Left = nextLeft;
        button.Top = nextTop;
        button.Width = 120;
        button.Click += delegate
        {
            try { Call(func, new List<object>(), line); }
            catch (VireError exc) { MessageBox.Show(exc.Message, "Vire"); }
        };
        form.Controls.Add(button);
        nextTop += 40;
#endif
    }

    void AddMark(int x, int y, int w, int h, string func, int line)
    {
        if (title == null) throw new VireError("open a window first", line);
        if (!funcs.ContainsKey(func)) throw new VireError("there is no definition named " + func, line);
        if (desk) { termButtons.Add("mark"); termActions.Add(func); return; }
#if WINDOWS
        Panel panel = new Panel();
        panel.Left = x;
        panel.Top = y;
        panel.Width = w;
        panel.Height = h;
        panel.BackColor = System.Drawing.Color.FromArgb(inkR, inkG, inkB);
        panel.Click += delegate
        {
            try { Call(func, new List<object>(), line); }
            catch (VireError exc) { MessageBox.Show(exc.Message, "Vire"); }
        };
        form.Controls.Add(panel);
#endif
    }

    void AddSheet(int width, int height, int line)
    {
        if (title == null) throw new VireError("open a window first", line);
        if (width < 1 || height < 1 || width > 2000 || height > 2000) throw new VireError("sheet size is out of range", line);
        if (desk) { termSheet = true; return; }
#if WINDOWS
        if (sheet != null) form.Controls.Remove(sheet);
        sheet = new SheetBox();
        sheet.Left = nextLeft;
        sheet.Top = nextTop;
        sheet.Width = width;
        sheet.Height = height;
        sheet.MouseClick += delegate(object sender, MouseEventArgs ev) { HitSheet(ev.X, ev.Y); };
        form.Controls.Add(sheet);
        nextTop += height + 12;
#endif
    }

    void HitSheet(int x, int y)
    {
        if (watchName == null) return;
        Func func = funcs[watchName];
        List<object> args = new List<object>();
        if (func.Params.Count >= 1) args.Add(x);
        if (func.Params.Count >= 2) args.Add(y);
        try { Call(watchName, args, watchLine); }
        catch (VireError exc)
        {
#if WINDOWS
            if (!desk) MessageBox.Show(exc.Message, "Vire");
            else Console.WriteLine(exc.Message);
#else
            Console.WriteLine(exc.Message);
#endif
        }
#if WINDOWS
        if (sheet != null) sheet.Invalidate();
#endif
    }

    void RequireSheet(int line)
    {
#if WINDOWS
        if (!desk && sheet == null) throw new VireError("open a sheet first", line);
#endif
        if (desk && !termSheet) throw new VireError("open a sheet first", line);
    }

    static void ColorOf(object r, object g, object b, int line, out int rr, out int gg, out int bb)
    {
        if (!(r is int) || !(g is int) || !(b is int)) throw new VireError("ink needs three whole numbers", line);
        rr = (int)r; gg = (int)g; bb = (int)b;
        if (rr < 0 || rr > 255 || gg < 0 || gg > 255 || bb < 0 || bb > 255) throw new VireError("ink numbers run from 0 to 255", line);
    }

    void Draw(string kind, List<object> args, int line)
    {
        if (!(args[0] is int) || !(args[1] is int) || !(args[2] is int) || !(args[3] is int))
            throw new VireError(kind + " needs four whole numbers", line);
        RequireSheet(line);
        Stroke mark = new Stroke(kind, (int)args[0], (int)args[1], (int)args[2], (int)args[3], inkR, inkG, inkB);
        if (desk)
        {
            if (termOps.Count > 10000) throw new VireError("the sheet has too many marks", line);
            termOps.Add(mark);
            return;
        }
#if WINDOWS
        if (sheet.Ops.Count > 10000) throw new VireError("the sheet has too many marks", line);
        sheet.Ops.Add(mark);
        sheet.Invalidate();
#endif
    }

    List<Stroke> ActiveOps()
    {
#if WINDOWS
        if (!desk && sheet != null) return sheet.Ops;
#endif
        return termOps;
    }

    object MarkList()
    {
        List<object> list = new List<object>();
        foreach (Stroke mark in ActiveOps())
        {
            Dictionary<string, object> row = new Dictionary<string, object>();
            row["kind"] = mark.Kind;
            row["a"] = mark.A;
            row["b"] = mark.B;
            row["c"] = mark.C;
            row["d"] = mark.D;
            row["r"] = mark.R;
            row["g"] = mark.G;
            row["blue"] = mark.Blue;
            list.Add(row);
        }
        return list;
    }

    void TermShow()
    {
        while (true)
        {
            Console.WriteLine(title);
            foreach (string row in termLines) Console.WriteLine(row);
            foreach (string name in termFields)
            {
                Console.Write(name + ": ");
                string typed = Console.ReadLine();
                termValues[name] = typed == null ? "" : typed;
            }
            if (termSheet) Console.WriteLine("sheet " + termOps.Count);
            for (int i = 0; i < termButtons.Count; i++) Console.WriteLine((i + 1) + " " + termButtons[i]);
            Console.WriteLine("0 close");
            string choice = Console.ReadLine();
            if (choice == null || choice == "0" || choice == "") return;
            int pick;
            if (int.TryParse(choice, out pick) && pick >= 1 && pick <= termActions.Count)
            {
                try { Call(termActions[pick - 1], new List<object>(), watchLine); }
                catch (VireError exc) { Console.WriteLine(exc.Message); }
                continue;
            }
            string[] bits = choice.Split(' ');
            int x, y;
            if (termSheet && bits.Length == 2 && int.TryParse(bits[0], out x) && int.TryParse(bits[1], out y))
                HitSheet(x, y);
        }
    }



    void Listen(int port, int line)
    {
        if (!funcs.ContainsKey("route")) throw new VireError("listen needs define route with method, path, body", line);
        VireListen.WithCancel(port, line, root, DispatchRoute, Show, p => ListenPort = p);
    }

    internal void ListenCore(int port, int line, CancellationToken stop)
    {
        if (!funcs.ContainsKey("route")) throw new VireError("listen needs define route with method, path, body", line);
        VireListen.Run(port, line, stop, root, DispatchRoute, Show, p => ListenPort = p);
    }

    object DispatchRoute(string method, string path, string body, int line, out int maxOutput)
    {
        Machine worker = ForkRequest();
        maxOutput = worker.budget.MaxOutput;
        List<object> call = new List<object>();
        call.Add(method);
        call.Add(path);
        call.Add(body);
        object result = worker.Call("route", call, line);
        string text = result as string;
        if (text == null) text = Show(result);
        if (text == null) text = "null";
        worker.budget.Output = text.Length;
        return result;
    }

    Machine ForkRequest()
    {
        Machine child = new Machine(funcs, root);
        child.UseShared(Budget.ForRequest(budget));
        child.UseArgs(programArgs);
        return child;
    }

    static string SliceText(string value, int start, int end)
    {
        if (start < 0) start = 0;
        if (end < start) end = start;
        if (start > value.Length) start = value.Length;
        if (end > value.Length) end = value.Length;
        return value.Substring(start, end - start);
    }

    static List<object> SliceList(List<object> value, int start, int end)
    {
        if (start < 0) start = 0;
        if (end < start) end = start;
        if (start > value.Count) start = value.Count;
        if (end > value.Count) end = value.Count;
        return value.GetRange(start, end - start);
    }

    static bool IsWholeNum(object value)
    {
        return value is int;
    }

    static int NodeLine(object[] node)
    {
        if (node == null || node.Length < 2) return 1;
        object last = node[node.Length - 1];
        object prev = node[node.Length - 2];
        if (IsWholeNum(prev) && IsWholeNum(last)) return (int)prev;
        if (IsWholeNum(last)) return (int)last;
        return 1;
    }

    static int NodeCol(object[] node)
    {
        if (node == null || node.Length < 2) return 1;
        object last = node[node.Length - 1];
        object prev = node[node.Length - 2];
        if (IsWholeNum(prev) && IsWholeNum(last)) return (int)last;
        return 1;
    }

    void ExecBlock(List<object> stmts, Env env)
    {
        foreach (object stmt in stmts) ExecStmt((object[])stmt, env);
    }

    void ExecStmt(object[] stmt, Env env)
    {
        Step(0);
        string kind = (string)stmt[0];
        if (kind == "let")
        {
            env.Declare((string)stmt[1], Eval(stmt[2], env));
            return;
        }
        if (kind == "put")
        {
            object target = env.Get((string)stmt[2], NodeLine(stmt), NodeCol(stmt));
            Store(target, Eval(stmt[3], env), Eval(stmt[1], env), NodeLine(stmt), NodeCol(stmt));
            return;
        }
        if (kind == "say")
        {
            Console.WriteLine(Show(Eval(stmt[1], env)));
            return;
        }
        if (kind == "return") throw new ReturnSignal(Eval(stmt[1], env));
        if (kind == "stop")
        {
            if (depth < 1) throw new VireError("stop is only valid inside while or for", NodeLine(stmt), NodeCol(stmt));
            throw new StopSignal();
        }
        if (kind == "skip")
        {
            if (depth < 1) throw new VireError("skip is only valid inside while or for", NodeLine(stmt), NodeCol(stmt));
            throw new SkipSignal();
        }
        if (kind == "while")
        {
            depth++;
            try
            {
                while (Truth(Eval(stmt[1], env)))
                {
                    if (budget.DeadlinePassed()) throw new VireError("request ran too long", NodeLine(stmt), NodeCol(stmt));
                    budget.WhilePasses++;
                    if (budget.WhilePasses > budget.MaxWhilePasses) throw new VireError("while ran too long", NodeLine(stmt), NodeCol(stmt));
                    try { ExecBlock((List<object>)stmt[2], env); }
                    catch (SkipSignal) { }
                    catch (StopSignal) { break; }
                }
            }
            finally { depth--; }
            return;
        }
        if (kind == "for")
        {
            object values = Eval(stmt[2], env);
            List<object> items;
            if (values is Dictionary<string, object>) items = new List<object>(((Dictionary<string, object>)values).Keys);
            else if (values is string)
            {
                items = new List<object>();
                foreach (char ch in (string)values) items.Add(ch.ToString());
            }
            else if (values is List<object>) items = (List<object>)values;
            else throw new VireError("for walks a list, map, or text", NodeLine(stmt), NodeCol(stmt));
            depth++;
            try
            {
                foreach (object item in items)
                {
                    env.Declare((string)stmt[1], item);
                    try { ExecBlock((List<object>)stmt[3], env); }
                    catch (SkipSignal) { }
                    catch (StopSignal) { break; }
                }
            }
            finally { depth--; }
            return;
        }
        if (kind == "if")
        {
            if (Truth(Eval(stmt[1], env))) ExecBlock((List<object>)stmt[2], env);
            else if (stmt[3] != null) ExecBlock((List<object>)stmt[3], env);
            return;
        }
        if (kind == "try")
        {
            try { ExecBlock((List<object>)stmt[1], env); }
            catch (VireError exc)
            {
                if (stmt[3] == null) throw;
                if (stmt[2] != null) env.Declare((string)stmt[2], exc.Message);
                ExecBlock((List<object>)stmt[3], env);
            }
            return;
        }
        if (kind == "call")
        {
            List<object> args = new List<object>();
            foreach (object arg in (List<object>)stmt[2]) args.Add(Eval(arg, env));
            Call((string)stmt[1], args, NodeLine(stmt), NodeCol(stmt));
            return;
        }
        throw new VireError("unknown statement", 0);
    }

    void Store(object target, object index, object value, int line)
    {
        Store(target, index, value, line, 1);
    }

    void Store(object target, object index, object value, int line, int col)
    {
        List<object> list = target as List<object>;
        if (list != null)
        {
            list[IndexOf(index, line, list.Count, col)] = value;
            return;
        }
        Dictionary<string, object> map = target as Dictionary<string, object>;
        if (map != null)
        {
            map[KeyOf(index, line)] = value;
            return;
        }
        if (target is string) throw new VireError("text cannot be changed in place", line, col);
        throw new VireError("put needs a list or a map", line, col);
    }

    object Eval(object node, Env env)
    {
        object[] tree = (object[])node;
        string kind = (string)tree[0];
        int line = NodeLine(tree);
        int col = NodeCol(tree);
        if (kind == "num" || kind == "str" || kind == "bool") return tree[1];
        if (kind == "none") return null;
        if (kind == "now") return Builtin("now", new List<object>(), line, col);
        if (kind == "var")
        {
            string name = (string)tree[1];
            if (!env.Has(name) && (name == "term" || name == "screen" || name == "show" || name == "marks" || name == "clear" || name == "args"))
                return Builtin(name, new List<object>(), line, col);
            if (!env.Has(name) && funcs.ContainsKey(name) && funcs[name].Params.Count == 0)
                return Call(name, new List<object>(), line, col);
            return env.Get(name, line, col);
        }
        if (kind == "call")
        {
            List<object> args = new List<object>();
            foreach (object arg in (List<object>)tree[2]) args.Add(Eval(arg, env));
            return Call((string)tree[1], args, line, col);
        }
        if (kind == "list")
        {
            List<object> items = new List<object>();
            foreach (object item in (List<object>)tree[1])
            {
                if (items.Count >= MaxItems) throw new VireError("list is too large", line, col);
                items.Add(Eval(item, env));
            }
            return items;
        }
        if (kind == "map")
        {
            Dictionary<string, object> made = new Dictionary<string, object>();
            foreach (object[] pair in (List<object[]>)tree[1])
            {
                if (made.Count >= MaxItems) throw new VireError("map is too large", line, col);
                made[KeyOf(Eval(pair[0], env), line)] = Eval(pair[1], env);
            }
            return made;
        }
        if (kind == "at") return Lookup(Eval(tree[1], env), Eval(tree[2], env), line, col);
        if (kind == "not") return !Truth(Eval(tree[1], env));
        if (kind == "neg")
        {
            object value = Eval(tree[1], env);
            if (!IsNum(value)) throw new VireError("minus applies to numbers", line, col);
            if (value is int)
            {
                int whole = (int)value;
                if (whole == int.MinValue) return -(double)whole;
                return -whole;
            }
            return -((double)value);
        }
        if (kind == "bin") return Binary(tree, env);
        throw new VireError("unknown expression", 0);
    }

    object Lookup(object target, object index, int line)
    {
        return Lookup(target, index, line, 1);
    }

    object Lookup(object target, object index, int line, int col)
    {
        if (target is List<object>)
        {
            List<object> list = (List<object>)target;
            return list[IndexOf(index, line, list.Count, col)];
        }
        if (target is string)
        {
            string text = (string)target;
            return text.Substring(IndexOf(index, line, text.Length, col), 1);
        }
        Dictionary<string, object> map = target as Dictionary<string, object>;
        if (map != null)
        {
            string key = KeyOf(index, line);
            if (!map.ContainsKey(key)) throw new VireError("map has no key " + key, line, col);
            return map[key];
        }
        throw new VireError("at needs a list, text, or map", line, col);
    }

    object Binary(object[] node, Env env)
    {
        string op = (string)node[1];
        int line = NodeLine(node);
        int col = NodeCol(node);
        if (op == "and") return Truth(Eval(node[2], env)) && Truth(Eval(node[3], env));
        if (op == "or") return Truth(Eval(node[2], env)) || Truth(Eval(node[3], env));
        object left = Eval(node[2], env);
        object right = Eval(node[3], env);
        if (op == "==") return ValuesMatch(left, right);
        if (op == "!=") return !ValuesMatch(left, right);
        if (op == "+")
        {
            if (left is string || right is string) return Show(left) + Show(right);
            if (left is List<object> && right is List<object>)
            {
                List<object> joined = new List<object>((List<object>)left);
                joined.AddRange((List<object>)right);
                return joined;
            }
            if (IsNum(left) && IsNum(right)) return Add(left, right);
            throw new VireError("plus needs numbers, text, or lists", line, col);
        }
        if (!IsNum(left) || !IsNum(right)) throw new VireError(op + " needs two numbers", line, col);
        if (op == "-") return Sub(left, right);
        if (op == "*") return Mul(left, right);
        if (op == "/")
        {
            if (ToDouble(right) == 0) throw new VireError("division by zero", line, col);
            return ToDouble(left) / ToDouble(right);
        }
        if (op == "%")
        {
            if (ToDouble(right) == 0) throw new VireError("division by zero", line, col);
            if (left is int && right is int)
            {
                if ((int)right == -1) return 0;
                return ((int)left) % ((int)right);
            }
            return ToDouble(left) % ToDouble(right);
        }
        double a = ToDouble(left);
        double b = ToDouble(right);
        if (op == "<") return a < b;
        if (op == ">") return a > b;
        if (op == "<=") return a <= b;
        if (op == ">=") return a >= b;
        throw new VireError("unknown operator " + op, line, col);
    }

    static bool ValuesMatch(object left, object right)
    {
        if (left == null || right == null) return left == null && right == null;
        if (IsNum(left) && IsNum(right)) return ToDouble(left) == ToDouble(right);
        return left.Equals(right);
    }

    static object Widen(long value)
    {
        if (value > int.MaxValue || value < int.MinValue) return (double)value;
        return (int)value;
    }
    static object Add(object left, object right)
    {
        if (left is int && right is int) return Widen((long)(int)left + (int)right);
        return ToDouble(left) + ToDouble(right);
    }
    static object Sub(object left, object right)
    {
        if (left is int && right is int) return Widen((long)(int)left - (int)right);
        return ToDouble(left) - ToDouble(right);
    }
    static object Mul(object left, object right)
    {
        if (left is int && right is int) return Widen((long)(int)left * (int)right);
        return ToDouble(left) * ToDouble(right);
    }
    static double ToDouble(object value)
    {
        if (value is int) return (int)value;
        return (double)value;
    }
    static int AsInt(object value, int line)
    {
        if (value is bool || !(value is int)) throw new VireError("slice bounds must be whole numbers", line);
        return (int)value;
    }
    static int IndexOf(object value, int line, int size)
    {
        return IndexOf(value, line, size, 1);
    }

    static int IndexOf(object value, int line, int size, int col)
    {
        if (value is bool || !(value is int)) throw new VireError("an index must be a whole number", line, col);
        int index = (int)value;
        if (index < 0) index += size;
        if (index < 0 || index >= size) throw new VireError("index is outside the value", line, col);
        return index;
    }
    static string KeyOf(object value, int line)
    {
        if (value is bool || value == null || !(value is string || value is int || value is double))
            throw new VireError("map keys must be text or numbers", line);
        if (value is int) return value.ToString();
        if (value is double)
        {
            double real = (double)value;
            if (real == Math.Floor(real)) return ((long)real).ToString();
            return real.ToString(CultureInfo.InvariantCulture);
        }
        return (string)value;
    }
    static bool IsNum(object value) { return value is int || value is double; }
    static bool Truth(object value)
    {
        if (value == null || value is bool && (bool)value == false) return false;
        if (value is bool) return (bool)value;
        if (value is int) return (int)value != 0;
        if (value is double) return (double)value != 0;
        if (value is string) return ((string)value).Length != 0;
        if (value is List<object>) return ((List<object>)value).Count != 0;
        if (value is Dictionary<string, object>) return ((Dictionary<string, object>)value).Count != 0;
        return true;
    }
    public static string Show(object value)
    {
        return ShowValue(value, new HashSet<object>(ReferenceEqualityComparer.Instance), 0, new int[1]);
    }

    static string ShowValue(object value, HashSet<object> path, int nest, int[] used)
    {
        if (nest > 256) return FinishShow("...", used);
        if (value is bool) return FinishShow((bool)value ? "true" : "false", used);
        if (value == null) return FinishShow("none", used);
        if (value is double)
        {
            double real = (double)value;
            if (real == Math.Floor(real) && !double.IsInfinity(real) && !double.IsNaN(real) && real >= -9223372036854775808d && real < 9223372036854775808d)
                return FinishShow(((long)real).ToString(CultureInfo.InvariantCulture), used);
            return FinishShow(real.ToString(CultureInfo.InvariantCulture), used);
        }
        if (value is List<object>)
        {
            List<object> list = (List<object>)value;
            if (!path.Add(list)) return FinishShow("[...]", used);
            try
            {
                StringBuilder text = new StringBuilder();
                text.Append('[');
                for (int i = 0; i < list.Count; i++)
                {
                    if (i > 0) text.Append(", ");
                    text.Append(ShowValue(list[i], path, nest + 1, used));
                }
                text.Append(']');
                return FinishShow(text.ToString(), used);
            }
            finally { path.Remove(list); }
        }
        if (value is Dictionary<string, object>)
        {
            Dictionary<string, object> map = (Dictionary<string, object>)value;
            if (!path.Add(map)) return FinishShow("{...}", used);
            try
            {
                StringBuilder text = new StringBuilder();
                text.Append('{');
                bool first = true;
                foreach (KeyValuePair<string, object> pair in map)
                {
                    if (!first) text.Append(", ");
                    first = false;
                    text.Append(ShowValue(pair.Key, path, nest + 1, used));
                    text.Append(": ");
                    text.Append(ShowValue(pair.Value, path, nest + 1, used));
                }
                text.Append('}');
                return FinishShow(text.ToString(), used);
            }
            finally { path.Remove(map); }
        }
        return FinishShow(Convert.ToString(value, CultureInfo.InvariantCulture), used);
    }

    static string FinishShow(string text, int[] used)
    {
        used[0] += text.Length;
        if (used[0] > 1000000) throw new VireError("text is too large to write", 1);
        return text;
    }
    static string KindOf(object value)
    {
        if (value is bool) return "bool";
        if (value == null) return "none";
        if (value is int || value is double) return "number";
        if (value is string) return "text";
        if (value is List<object>) return "list";
        if (value is Dictionary<string, object>) return "map";
        return "value";
    }
}

sealed class Unit
{
    public Dictionary<string, Func> Funcs = new Dictionary<string, Func>();
    public List<string> Uses = new List<string>();
    public List<string> Needs = new List<string>();
}

sealed class Parser
{
    List<Token> tokens;
    int i;
    int nest;
    int blockNest;
    static readonly HashSet<string> Stoppers = new HashSet<string>(new string[] { "end", "else", "miss", "eof" });

    public Parser(List<Token> tokens) { this.tokens = tokens; }

    Token Peek() { return tokens[i]; }
    bool At(params string[] kinds)
    {
        foreach (string kind in kinds) if (Peek().Kind == kind) return true;
        return false;
    }
    Token Eat(string kind)
    {
        Token tok = Peek();
        if (tok.Kind != kind) throw new VireError("expected " + kind + ", found " + tok.Kind, tok.Line, tok.Column);
        i++;
        return tok;
    }

    public Unit Parse()
    {
        Unit unit = new Unit();
        while (!At("eof"))
        {
            if (At("use"))
            {
                Token use = Eat("use");
                if (Peek().Kind != "string") throw new VireError("use needs a file name in quotes", use.Line, use.Column);
                unit.Uses.Add((string)Eat("string").Value);
                continue;
            }
            if (At("need"))
            {
                Token need = Eat("need");
                if (Peek().Kind != "string") throw new VireError("need takes a package name in quotes", need.Line, need.Column);
                unit.Needs.Add((string)Eat("string").Value);
                continue;
            }
            Func func = Definition();
            string name = (string)func.Body[0];
            func.Body.RemoveAt(0);
            if (unit.Funcs.ContainsKey(name)) throw new VireError(name + " is already defined", func.Line, func.Column);
            unit.Funcs[name] = func;
        }
        return unit;
    }

    Func Definition()
    {
        Token start = Eat("define");
        Func func = new Func();
        func.Line = start.Line;
        func.Column = start.Column;
        string name = (string)Eat("name").Value;
        if (At("with"))
        {
            Eat("with");
            func.Params.Add((string)Eat("name").Value);
            while (At(","))
            {
                Eat(",");
                func.Params.Add((string)Eat("name").Value);
            }
        }
        func.Body = Block();
        func.Body.Insert(0, name);
        Eat("end");
        return func;
    }

    List<object> Block()
    {
        return Collect(true, true);
    }

    List<object> LoopBody()
    {
        return Collect(false, false);
    }

    List<object> Collect(bool stopOnElse, bool stopOnMiss)
    {
        blockNest++;
        if (blockNest > 256) throw new VireError("block is nested too deeply", Peek().Line, Peek().Column);
        try
        {
            List<object> stmts = new List<object>();
            while (!At("end") && !At("eof") && !(stopOnElse && At("else")) && !(stopOnMiss && At("miss")))
                stmts.Add(Statement());
            if (At("eof")) throw new VireError("block is missing end", Peek().Line, Peek().Column);
            return stmts;
        }
        finally { blockNest--; }
    }

    object Statement()
    {
        Token tok = Peek();
        if (tok.Kind == "let")
        {
            Eat("let");
            string name = (string)Eat("name").Value;
            Eat("be");
            return new object[] { "let", name, Expression(), tok.Line, tok.Column };
        }
        if (tok.Kind == "put")
        {
            Eat("put");
            object value = Expression();
            Eat("into");
            string name = (string)Eat("name").Value;
            Eat("at");
            return new object[] { "put", value, name, Expression(), tok.Line, tok.Column };
        }
        if (tok.Kind == "say") { Eat("say"); return new object[] { "say", Expression(), tok.Line, tok.Column }; }
        if (tok.Kind == "return") { Eat("return"); return new object[] { "return", Expression(), tok.Line, tok.Column }; }
        if (tok.Kind == "stop") { Eat("stop"); return new object[] { "stop", tok.Line, tok.Column }; }
        if (tok.Kind == "skip") { Eat("skip"); return new object[] { "skip", tok.Line, tok.Column }; }
        if (tok.Kind == "while")
        {
            Eat("while");
            object test = Expression();
            List<object> body = LoopBody();
            Eat("end");
            return new object[] { "while", test, body, tok.Line, tok.Column };
        }
        if (tok.Kind == "for")
        {
            Eat("for");
            string name = (string)Eat("name").Value;
            Eat("in");
            object seq = Expression();
            List<object> body = LoopBody();
            Eat("end");
            return new object[] { "for", name, seq, body, tok.Line, tok.Column };
        }
        if (tok.Kind == "if") return IfStmt(tok.Line, tok.Column, true);
        if (tok.Kind == "try")
        {
            Eat("try");
            List<object> body = Block();
            object caught = null;
            object handler = null;
            if (At("miss"))
            {
                Eat("miss");
                if (At("name")) caught = Eat("name").Value;
                handler = Block();
            }
            Eat("end");
            return new object[] { "try", body, caught, handler, tok.Line, tok.Column };
        }
        if (tok.Kind == "name")
        {
            string name = (string)Eat("name").Value;
            return new object[] { "call", name, Arguments(), tok.Line, tok.Column };
        }
        throw new VireError("line does not start a statement", tok.Line, tok.Column);
    }

    object IfStmt(int line, int col, bool close)
    {
        Eat("if");
        object test = Expression();
        List<object> body = Block();
        object other = null;
        if (At("else"))
        {
            Eat("else");
            if (At("if"))
            {
                List<object> wrapped = new List<object>();
                wrapped.Add(IfStmt(Peek().Line, Peek().Column, false));
                other = wrapped;
            }
            else other = Block();
        }
        if (close) Eat("end");
        return new object[] { "if", test, body, other, line, col };
    }

    List<object> Arguments()
    {
        List<object> args = new List<object>();
        if (!At("with")) return args;
        Eat("with");
        args.Add(ParseProduct());
        while (At(","))
        {
            Eat(",");
            args.Add(ParseProduct());
        }
        return args;
    }

    object Expression()
    {
        nest++;
        if (nest > 256) throw new VireError("expression is too deep", Peek().Line, Peek().Column);
        try { return ParseOr(); }
        finally { nest--; }
    }
    object ParseOr()
    {
        object node = ParseAnd();
        while (At("or"))
        {
            Token op = Eat("or");
            node = new object[] { "bin", "or", node, ParseAnd(), op.Line, op.Column };
        }
        return node;
    }
    object ParseAnd()
    {
        object node = ParseCmp();
        while (At("and"))
        {
            Token op = Eat("and");
            node = new object[] { "bin", "and", node, ParseCmp(), op.Line, op.Column };
        }
        return node;
    }
    object ParseCmp()
    {
        object node = ParseSum();
        while (At("==", "!=", "<", ">", "<=", ">="))
        {
            Token op = Eat(Peek().Kind);
            node = new object[] { "bin", op.Kind, node, ParseSum(), op.Line, op.Column };
        }
        return node;
    }
    object ParseSum()
    {
        object node = ParseProduct();
        while (At("+", "-"))
        {
            Token op = Eat(Peek().Kind);
            node = new object[] { "bin", op.Kind, node, ParseProduct(), op.Line, op.Column };
        }
        return node;
    }
    object ParseProduct()
    {
        object node = ParseUnary();
        while (At("*", "/", "%"))
        {
            Token op = Eat(Peek().Kind);
            node = new object[] { "bin", op.Kind, node, ParseUnary(), op.Line, op.Column };
        }
        return node;
    }
    object ParseUnary()
    {
        if (At("not"))
        {
            Token op = Eat("not");
            return new object[] { "not", ParseUnary(), op.Line, op.Column };
        }
        if (At("-"))
        {
            Token op = Eat("-");
            return new object[] { "neg", ParseUnary(), op.Line, op.Column };
        }
        return ParsePrimary();
    }
    object ParsePrimary()
    {
        object node = Atom();
        while (At("at"))
        {
            Token op = Eat("at");
            node = new object[] { "at", node, Atom(), op.Line, op.Column };
        }
        return node;
    }
    object Atom()
    {
        Token tok = Peek();
        if (tok.Kind == "number") { Eat("number"); return new object[] { "num", tok.Value, tok.Line, tok.Column }; }
        if (tok.Kind == "string") { Eat("string"); return new object[] { "str", tok.Value, tok.Line, tok.Column }; }
        if (tok.Kind == "true") { Eat("true"); return new object[] { "bool", true, tok.Line, tok.Column }; }
        if (tok.Kind == "false") { Eat("false"); return new object[] { "bool", false, tok.Line, tok.Column }; }
        if (tok.Kind == "none") { Eat("none"); return new object[] { "none", null, tok.Line, tok.Column }; }
        if (tok.Kind == "now") { Eat("now"); return new object[] { "now", tok.Line, tok.Column }; }
        if (tok.Kind == "name")
        {
            Eat("name");
            if (At("with")) return new object[] { "call", tok.Value, Arguments(), tok.Line, tok.Column };
            return new object[] { "var", tok.Value, tok.Line, tok.Column };
        }
        if (tok.Kind == "(")
        {
            Eat("(");
            object node = Expression();
            Eat(")");
            return node;
        }
        if (tok.Kind == "[") return ListLiteral(tok.Line, tok.Column);
        if (tok.Kind == "{") return MapLiteral(tok.Line, tok.Column);
        throw new VireError("expected a value", tok.Line, tok.Column);
    }
    object ListLiteral(int line, int col)
    {
        Eat("[");
        List<object> items = new List<object>();
        if (!At("]"))
        {
            items.Add(Expression());
            while (At(","))
            {
                Eat(",");
                if (At("]")) break;
                items.Add(Expression());
            }
        }
        Eat("]");
        return new object[] { "list", items, line, col };
    }
    object MapLiteral(int line, int col)
    {
        Eat("{");
        List<object[]> pairs = new List<object[]>();
        if (!At("}"))
        {
            object key = Expression();
            Eat(":");
            pairs.Add(new object[] { key, Expression() });
            while (At(","))
            {
                Eat(",");
                if (At("}")) break;
                key = Expression();
                Eat(":");
                pairs.Add(new object[] { key, Expression() });
            }
        }
        Eat("}");
        return new object[] { "map", pairs, line, col };
    }
}

static class Lexer
{
    static readonly HashSet<string> Keywords = new HashSet<string>(new string[] {
        "define", "with", "end", "let", "be", "say", "while", "if", "else", "return",
        "and", "or", "not", "true", "false", "for", "in", "at", "put", "into",
        "try", "miss", "stop", "skip", "none", "now", "use", "need"
    });

    public static List<Token> Tokenize(string source)
    {
        List<Token> tokens = new List<Token>();
        int i = 0;
        int line = 1;
        int col = 1;
        while (i < source.Length)
        {
            char ch = source[i];
            if (ch == ' ' || ch == '\t' || ch == '\r') { i++; col++; continue; }
            if (ch == '\n') { line++; i++; col = 1; continue; }
            if (ch == '~')
            {
                while (i < source.Length && source[i] != '\n') i++;
                continue;
            }
            int here = col;
            if (ch == '"')
            {
                int from = i;
                i++;
                StringBuilder chars = new StringBuilder();
                while (i < source.Length && source[i] != '"')
                {
                    if (source[i] == '\n') throw new VireError("string runs past the end of the line", line, here);
                    if (source[i] == '\\')
                    {
                        i++;
                        if (i >= source.Length) throw new VireError("broken escape in string", line, here);
                        char esc = source[i];
                        if (esc == 'n') chars.Append('\n');
                        else if (esc == 'r') chars.Append('\r');
                        else if (esc == 't') chars.Append('\t');
                        else if (esc == '"' || esc == '\\') chars.Append(esc);
                        else throw new VireError("unknown escape in string", line, here);
                    }
                    else chars.Append(source[i]);
                    i++;
                }
                if (i >= source.Length) throw new VireError("string is missing its closing quote", line, here);
                i++;
                tokens.Add(new Token("string", chars.ToString(), line, here));
                col = here + (i - from);
                continue;
            }
            if (char.IsDigit(ch))
            {
                int start = i;
                while (i < source.Length && char.IsDigit(source[i])) i++;
                if (i + 1 < source.Length && source[i] == '.' && char.IsDigit(source[i + 1]))
                {
                    i++;
                    while (i < source.Length && char.IsDigit(source[i])) i++;
                    double real = double.Parse(source.Substring(start, i - start), CultureInfo.InvariantCulture);
                    tokens.Add(new Token("number", real, line, here));
                }
                else
                {
                    string raw = source.Substring(start, i - start);
                    int whole;
                    if (int.TryParse(raw, NumberStyles.None, CultureInfo.InvariantCulture, out whole))
                        tokens.Add(new Token("number", whole, line, here));
                    else
                    {
                        double real;
                        if (!double.TryParse(raw, NumberStyles.Float, CultureInfo.InvariantCulture, out real) || double.IsInfinity(real))
                            throw new VireError("that number is too large", line, here);
                        tokens.Add(new Token("number", real, line, here));
                    }
                }
                col = here + (i - start);
                continue;
            }
            if (char.IsLetter(ch) || ch == '_')
            {
                int start = i;
                while (i < source.Length && (char.IsLetterOrDigit(source[i]) || source[i] == '_')) i++;
                string word = source.Substring(start, i - start);
                tokens.Add(new Token(Keywords.Contains(word) ? word : "name", word, line, here));
                col = here + (i - start);
                continue;
            }
            if (i + 1 < source.Length)
            {
                string two = source.Substring(i, 2);
                if (two == "==" || two == "!=" || two == "<=" || two == ">=")
                {
                    tokens.Add(new Token(two, two, line, here));
                    i += 2;
                    col = here + 2;
                    continue;
                }
            }
            string one = ch.ToString();
            if ("+-*/%<>=(),[]{}:".IndexOf(ch) >= 0)
            {
                tokens.Add(new Token(one, one, line, here));
                i++;
                col = here + 1;
                continue;
            }
            throw new VireError("unexpected character '" + one + "'", line, here);
        }
        tokens.Add(new Token("eof", null, line, col));
        return tokens;
    }
}

sealed class Json
{
    public static string Write(object value)
    {
        return WriteValue(value, new HashSet<object>(ReferenceEqualityComparer.Instance), 0);
    }

    static string WriteValue(object value, HashSet<object> path, int nest)
    {
        if (nest > 256) throw new VireError("json is nested too deeply", 1);
        string text;
        if (value == null) text = "null";
        else if (value is bool) text = (bool)value ? "true" : "false";
        else if (value is int) text = value.ToString();
        else if (value is double)
        {
            double real = (double)value;
            if (double.IsNaN(real) || double.IsInfinity(real)) throw new VireError("json can't write that number", 1);
            text = real.ToString("R", CultureInfo.InvariantCulture);
        }
        else if (value is string) text = WriteString((string)value);
        else if (value is List<object>)
        {
            List<object> list = (List<object>)value;
            if (!path.Add(list)) throw new VireError("json can't write a list or map that contains itself", 1);
            try
            {
                StringBuilder body = new StringBuilder();
                body.Append('[');
                for (int i = 0; i < list.Count; i++)
                {
                    if (i > 0) body.Append(',');
                    body.Append(WriteValue(list[i], path, nest + 1));
                }
                body.Append(']');
                text = body.ToString();
            }
            finally { path.Remove(list); }
        }
        else if (value is Dictionary<string, object>)
        {
            Dictionary<string, object> map = (Dictionary<string, object>)value;
            if (!path.Add(map)) throw new VireError("json can't write a list or map that contains itself", 1);
            try
            {
                StringBuilder body = new StringBuilder();
                body.Append('{');
                bool first = true;
                foreach (KeyValuePair<string, object> pair in map)
                {
                    if (!first) body.Append(',');
                    first = false;
                    body.Append(WriteValue(pair.Key, path, nest + 1));
                    body.Append(':');
                    body.Append(WriteValue(pair.Value, path, nest + 1));
                }
                body.Append('}');
                text = body.ToString();
            }
            finally { path.Remove(map); }
        }
        else text = WriteString(Machine.Show(value));
        if (text.Length > 1000000) throw new VireError("text is too large to write", 1);
        return text;
    }

    static string WriteString(string text)
    {
        StringBuilder chars = new StringBuilder(text.Length + 2);
        chars.Append('"');
        for (int i = 0; i < text.Length; i++)
        {
            char ch = text[i];
            if (ch == '\\' || ch == '"') { chars.Append('\\'); chars.Append(ch); }
            else if (ch == '\b') chars.Append("\\b");
            else if (ch == '\f') chars.Append("\\f");
            else if (ch == '\n') chars.Append("\\n");
            else if (ch == '\r') chars.Append("\\r");
            else if (ch == '\t') chars.Append("\\t");
            else if (ch < 0x20 || char.IsSurrogate(ch))
            {
                chars.Append("\\u");
                chars.Append(((int)ch).ToString("x4"));
            }
            else chars.Append(ch);
        }
        chars.Append('"');
        return chars.ToString();
    }

    public static object Read(string text, int line)
    {
        if (text == null) throw new VireError("json ended early", line);
        if (text.Length > 1000000) throw new VireError("json is too large", line);
        int i = 0;
        object value = ReadValue(text, ref i, line);
        Skip(text, ref i);
        if (i != text.Length) throw new VireError("json has extra text", line);
        return value;
    }

    static object ReadValue(string text, ref int i, int line, int depth = 0)
    {
        if (depth > 256) throw new VireError("json is nested too deeply", line);
        Skip(text, ref i);
        if (i >= text.Length) throw new VireError("json ended early", line);
        char ch = text[i];
        if (ch == '"') return ReadString(text, ref i, line);
        if (ch == '{') return ReadMap(text, ref i, line, depth + 1);
        if (ch == '[') return ReadList(text, ref i, line, depth + 1);
        if (ch == 't' || ch == 'f' || ch == 'n') return ReadWord(text, ref i, line);
        return ReadNumber(text, ref i, line);
    }

    static Dictionary<string, object> ReadMap(string text, ref int i, int line, int depth)
    {
        i++;
        Dictionary<string, object> map = new Dictionary<string, object>();
        Skip(text, ref i);
        if (i < text.Length && text[i] == '}') { i++; return map; }
        while (i < text.Length)
        {
            if (map.Count > 100000) throw new VireError("json is too large", line);
            string key = ReadString(text, ref i, line);
            Skip(text, ref i);
            if (i >= text.Length || text[i] != ':') throw new VireError("json needs a colon", line);
            i++;
            map[key] = ReadValue(text, ref i, line, depth);
            Skip(text, ref i);
            if (i < text.Length && text[i] == ',') { i++; continue; }
            if (i < text.Length && text[i] == '}') { i++; return map; }
            break;
        }
        throw new VireError("json map is unfinished", line);
    }

    static List<object> ReadList(string text, ref int i, int line, int depth)
    {
        i++;
        List<object> list = new List<object>();
        Skip(text, ref i);
        if (i < text.Length && text[i] == ']') { i++; return list; }
        while (i < text.Length)
        {
            if (list.Count > 100000) throw new VireError("json is too large", line);
            list.Add(ReadValue(text, ref i, line, depth));
            Skip(text, ref i);
            if (i < text.Length && text[i] == ',') { i++; continue; }
            if (i < text.Length && text[i] == ']') { i++; return list; }
            break;
        }
        throw new VireError("json list is unfinished", line);
    }

    static string ReadString(string text, ref int i, int line)
    {
        if (i >= text.Length || text[i] != '"') throw new VireError("json needs text", line);
        i++;
        StringBuilder chars = new StringBuilder();
        while (i < text.Length)
        {
            char ch = text[i++];
            if (ch == '"') return chars.ToString();
            if (ch == '\\')
            {
                if (i >= text.Length) break;
                char esc = text[i++];
                if (esc == '"' || esc == '\\' || esc == '/') chars.Append(esc);
                else if (esc == 'b') chars.Append('\b');
                else if (esc == 'f') chars.Append('\f');
                else if (esc == 'n') chars.Append('\n');
                else if (esc == 'r') chars.Append('\r');
                else if (esc == 't') chars.Append('\t');
                else if (esc == 'u')
                {
                    if (i + 4 > text.Length) throw new VireError("json has a bad escape", line);
                    int code = 0;
                    for (int k = 0; k < 4; k++)
                    {
                        char hex = text[i++];
                        code <<= 4;
                        if (hex >= '0' && hex <= '9') code += hex - '0';
                        else if (hex >= 'a' && hex <= 'f') code += hex - 'a' + 10;
                        else if (hex >= 'A' && hex <= 'F') code += hex - 'A' + 10;
                        else throw new VireError("json has a bad escape", line);
                    }
                    chars.Append((char)code);
                }
                else throw new VireError("json has a bad escape", line);
            }
            else chars.Append(ch);
        }
        throw new VireError("json text is unfinished", line);
    }

    static object ReadWord(string text, ref int i, int line)
    {
        if (text.IndexOf("true", i) == i) { i += 4; return true; }
        if (text.IndexOf("false", i) == i) { i += 5; return false; }
        if (text.IndexOf("null", i) == i) { i += 4; return null; }
        throw new VireError("json has a bad value", line);
    }

    static object ReadNumber(string text, ref int i, int line)
    {
        int start = i;
        if (text[i] == '-') i++;
        while (i < text.Length && char.IsDigit(text[i])) i++;
        bool frac = false;
        if (i < text.Length && text[i] == '.')
        {
            frac = true;
            i++;
            while (i < text.Length && char.IsDigit(text[i])) i++;
        }
        if (i < text.Length && (text[i] == 'e' || text[i] == 'E'))
        {
            frac = true;
            i++;
            if (i < text.Length && (text[i] == '+' || text[i] == '-')) i++;
            int expAt = i;
            while (i < text.Length && char.IsDigit(text[i])) i++;
            if (i == expAt) throw new VireError("json has a bad number", line);
        }
        string raw = text.Substring(start, i - start);
        if (raw.Length == 0 || raw == "-") throw new VireError("json has a bad number", line);
        if (!frac)
        {
            int whole;
            if (int.TryParse(raw, out whole)) return whole;
        }
        double real;
        if (double.TryParse(raw, System.Globalization.NumberStyles.Float, System.Globalization.CultureInfo.InvariantCulture, out real) && !double.IsInfinity(real) && !double.IsNaN(real))
            return real;
        throw new VireError("json has a bad number", line);
    }

    static void Skip(string text, ref int i)
    {
        while (i < text.Length && (text[i] == ' ' || text[i] == '\n' || text[i] == '\r' || text[i] == '\t')) i++;
    }
}

internal static class HttpWire
{
    public const int MaxHeaderBlock = 16384;
    public const int MaxRequestLine = 8192;
    public const int MaxRequestBody = 1000000;

    public sealed class Result
    {
        public int Status;
        public string ErrorJson;
        public string Method;
        public string Path;
        public string Head;
        public string Body;
        public int BodyAt;
        public int ContentLength;
    }

    public static int HeaderEnd(byte[] buffer, int got)
    {
        if (buffer == null || got < 4) return -1;
        if (got > buffer.Length) got = buffer.Length;
        for (int i = 0; i + 3 < got; i++)
            if (buffer[i] == 13 && buffer[i + 1] == 10 && buffer[i + 2] == 13 && buffer[i + 3] == 10) return i;
        return -1;
    }

    public static int ContentLengthOf(string head)
    {
        string[] lines = head.Split(new string[] { "\r\n" }, StringSplitOptions.None);
        for (int i = 1; i < lines.Length; i++)
        {
            if (lines[i].StartsWith("Content-Length:", StringComparison.OrdinalIgnoreCase))
            {
                int value;
                if (!int.TryParse(lines[i].Substring(15).Trim(), NumberStyles.Integer, CultureInfo.InvariantCulture, out value) || value < 0) return -2;
                return value;
            }
        }
        return -1;
    }

    public static bool HasChunked(string head)
    {
        string[] lines = head.Split(new string[] { "\r\n" }, StringSplitOptions.None);
        for (int i = 1; i < lines.Length; i++)
        {
            if (lines[i].StartsWith("Transfer-Encoding:", StringComparison.OrdinalIgnoreCase) &&
                lines[i].IndexOf("chunked", StringComparison.OrdinalIgnoreCase) >= 0)
                return true;
        }
        return false;
    }

    public static Result ParseHeaders(byte[] buffer, int got)
    {
        Result result = new Result();
        if (buffer == null)
        {
            Fail(result, 400, "bad request");
            return result;
        }
        if (got < 0) got = 0;
        if (got > buffer.Length) got = buffer.Length;
        int headerEnd = HeaderEnd(buffer, got);
        if (headerEnd < 0)
        {
            Fail(result, got >= MaxHeaderBlock ? 431 : 408, got >= MaxHeaderBlock ? "headers too large" : "timeout");
            return result;
        }
        int lineEnd = -1;
        for (int i = 0; i + 1 < headerEnd; i++)
        {
            if (buffer[i] == 13 && buffer[i + 1] == 10) { lineEnd = i; break; }
        }
        if (lineEnd < 0 || lineEnd > MaxRequestLine)
        {
            Fail(result, 431, "request line too large");
            return result;
        }
        string head;
        string requestLine;
        try
        {
            head = Encoding.ASCII.GetString(buffer, 0, headerEnd);
            requestLine = Encoding.ASCII.GetString(buffer, 0, lineEnd);
        }
        catch (DecoderFallbackException)
        {
            Fail(result, 400, "bad request");
            return result;
        }
        string[] bits = requestLine.Split(' ');
        if (bits.Length < 2 || bits[0].Length == 0 || bits[1].Length == 0)
        {
            Fail(result, 400, "bad request");
            return result;
        }
        if (bits[1].IndexOf("..", StringComparison.Ordinal) >= 0)
        {
            if (bits[0] == "GET" || bits[0] == "HEAD")
            {
                result.Status = 404;
                result.ErrorJson = "{\"error\":\"not found\"}";
                return result;
            }
            Fail(result, 400, "bad request");
            return result;
        }
        if (HasChunked(head))
        {
            Fail(result, 501, "chunked encoding is not supported");
            return result;
        }
        int contentLength = ContentLengthOf(head);
        if (contentLength == -2)
        {
            Fail(result, 400, "bad request");
            return result;
        }
        string method = bits[0];
        bool expectsBody = method == "POST" || method == "PUT" || method == "PATCH";
        if (expectsBody && contentLength < 0)
        {
            Fail(result, 411, "content length required");
            return result;
        }
        if (contentLength > MaxRequestBody)
        {
            Fail(result, 413, "body too large");
            return result;
        }
        if (contentLength < 0) contentLength = 0;
        result.Status = 0;
        result.Method = method;
        string path = bits[1];
        int queryAt = path.IndexOf('?');
        if (queryAt >= 0) path = path.Substring(0, queryAt);
        result.Path = path;
        result.Head = head;
        result.BodyAt = headerEnd + 4;
        result.ContentLength = contentLength;
        return result;
    }

    public static Result FinishBody(Result headers, byte[] buffer, int got)
    {
        if (headers == null || headers.Status != 0) return headers;
        Result result = headers;
        int need = result.BodyAt + result.ContentLength;
        if (need < result.BodyAt || need > buffer.Length)
        {
            Fail(result, 413, "body too large");
            return result;
        }
        if (got < need)
        {
            Fail(result, 408, "timeout");
            return result;
        }
        try { result.Body = Encoding.UTF8.GetString(buffer, result.BodyAt, result.ContentLength); }
        catch (DecoderFallbackException)
        {
            Fail(result, 400, "bad request");
        }
        return result;
    }

    public static Result ParseComplete(byte[] buffer, int got)
    {
        Result headers = ParseHeaders(buffer, got);
        if (headers.Status != 0) return headers;
        return FinishBody(headers, buffer, got);
    }

    static void Fail(Result result, int status, string error)
    {
        result.Status = status;
        result.ErrorJson = "{\"error\":\"" + error + "\"}";
        result.Method = null;
        result.Path = null;
        result.Body = null;
    }
}

sealed class Program
{
    public static void RunFile(string program, string folder)
    {
        RunFile(program, folder, null);
    }

    public static void RunFile(string program, string folder, Budget budget)
    {
        Dictionary<string, Func> funcs = Load(program, folder, new HashSet<string>());
        if (!funcs.ContainsKey("main")) throw new VireError("a vire program needs define main", 1);
        Machine machine = new Machine(funcs, folder);
        if (budget != null) machine.UseShared(budget);
        machine.Run();
    }

    internal static Dictionary<string, Func> Load(string program, string folder, HashSet<string> seen)
    {
        string full = Path.GetFullPath(program);
        if (!full.EndsWith(".vire", StringComparison.OrdinalIgnoreCase))
            throw new VireError("vire only runs .vire files", 1);
        if (seen.Contains(full)) throw new VireError("use went in a circle at " + Path.GetFileName(full), 1);
        if (seen.Count > 32) throw new VireError("too many files were used", 1);
        seen.Add(full);
        try
        {
        string folderFull = folder.TrimEnd(Path.DirectorySeparatorChar) + Path.DirectorySeparatorChar;
        if (!full.StartsWith(folderFull, StringComparison.OrdinalIgnoreCase))
            throw new VireError("use stays inside the program folder", 1);
        VirePaths.RefuseReparse(full, folder, 1);
        FileInfo info = new FileInfo(full);
        if (!info.Exists) throw new VireError("could not read " + Path.GetFileName(full), 1);
        if (info.Length > 1000000) throw new VireError("that file is too large to run", 1);
        Unit unit = new Parser(Lexer.Tokenize(File.ReadAllText(full))).Parse();
        foreach (string used in unit.Uses)
        {
            string next = VirePaths.UseFile(folder, used, 1);
            Dictionary<string, Func> imported = Load(next, folder, seen);
            Merge(unit, imported);
        }
        foreach (string package in unit.Needs)
        {
            if (!IsPackage(package))
                throw new VireError("package names are plain words", 1);
            string next = VirePaths.UseFile(folder, "deps/" + package + "/lib.vire", 1);
            Merge(unit, Load(next, folder, seen));
        }
        return unit.Funcs;
        }
        finally { seen.Remove(full); }
    }

    public static int BudgetOf(string source)
    {
        int budget = 1000000;
        string chosen = Environment.GetEnvironmentVariable("VIRE_BUDGET");
        if (!string.IsNullOrWhiteSpace(chosen))
        {
            int value;
            if (!int.TryParse(chosen.Trim(), out value) || value < 1 || value > 5000000)
                throw new VireError("VIRE_BUDGET must be from 1 to 5000000", 1);
            budget = value;
        }
        return budget;
    }

    public static bool HeaderTokenMatches(string head, string expected)
    {
        if (string.IsNullOrEmpty(expected) || expected.Length < 16) return false;
        string provided = "";
        string[] lines = head.Split(new string[] { "\r\n" }, StringSplitOptions.None);
        for (int i = 1; i < lines.Length; i++)
        {
            if (lines[i].StartsWith("X-FCG-Token:", StringComparison.OrdinalIgnoreCase))
            {
                provided = lines[i].Substring(12).Trim();
                break;
            }
        }
        byte[] left;
        byte[] right;
        using (SHA256 sha = SHA256.Create())
        {
            left = sha.ComputeHash(Encoding.UTF8.GetBytes(provided));
            right = sha.ComputeHash(Encoding.UTF8.GetBytes(expected));
        }
        int diff = 0;
        for (int i = 0; i < left.Length; i++) diff |= left[i] ^ right[i];
        return diff == 0;
    }

    static bool IsPackage(string name)
    {
        if (name.Length == 0) return false;
        foreach (char ch in name)
            if (!char.IsLetterOrDigit(ch) && ch != '_') return false;
        return true;
    }

    static void Merge(Unit unit, Dictionary<string, Func> imported)
    {
        foreach (KeyValuePair<string, Func> pair in imported)
        {
            if (unit.Funcs.ContainsKey(pair.Key))
                throw new VireError(pair.Key + " is already defined", pair.Value.Line);
            unit.Funcs[pair.Key] = pair.Value;
        }
    }

    [STAThread]
    static int Main(string[] args)
    {
        return Execute(args);
    }

    internal static int Execute(string[] args)
    {
        int code = 0;
        Exception failure = null;
        Thread thread = new Thread(delegate ()
        {
            try { code = ExecuteBody(args); }
            catch (Exception ex) { failure = ex; }
        }, 64 * 1024 * 1024);
        thread.IsBackground = true;
        thread.Start();
        thread.Join();
        if (failure == null) return code;
        if (failure is HaltSignal halt) return halt.Code;
        if (failure is VireError exc)
            return WriteVireError(exc);
        if (Environment.GetEnvironmentVariable("VIRE_DEBUG") == "1")
            Console.Error.WriteLine(failure.ToString());
        else
            Console.Error.WriteLine("vire: internal error (" + failure.GetType().Name + ")");
        return 3;
    }

    static int WriteVireError(VireError exc)
    {
        if (VireSeal.MissingKeyExit(exc.Message))
        {
            Console.Error.WriteLine("vire: " + exc.Message);
            return 2;
        }
        string where = "";
        if (exc.Line > 0)
        {
            where = "line " + exc.Line;
            if (exc.Column > 0) where += " col " + exc.Column;
            where += ": ";
        }
        Console.Error.WriteLine("vire: " + where + exc.Message);
        return 1;
    }

    static int ExecuteBody(string[] args)
    {
        if (args.Length < 1)
        {
            Console.Error.WriteLine("usage: vire program.vire [args...]");
            Console.Error.WriteLine("       vire run file.vc [args...]");
            Console.Error.WriteLine("       vire keygen --out <path>");
            return 2;
        }
        try
        {
            string keyFile;
            string[] rest = StripKeyFile(args, out keyFile);
            if (rest.Length >= 1 && rest[0] == "keygen")
            {
                string outPath = null;
                for (int i = 1; i < rest.Length; i++)
                {
                    if (rest[i] == "--out" && i + 1 < rest.Length) { outPath = rest[i + 1]; i++; continue; }
                    if (outPath == null) outPath = rest[i];
                }
                return VireSeal.Keygen(outPath);
            }
            string programFolder = null;
            if (rest.Length >= 2 && rest[0] == "run")
                programFolder = Path.GetDirectoryName(Path.GetFullPath(rest[1]));
            else if (rest.Length >= 1)
                programFolder = Path.GetDirectoryName(Path.GetFullPath(rest[0]));
            VireSeal.ClearKey();
            if (!string.IsNullOrEmpty(keyFile)) VireSeal.LoadFromFile(keyFile, programFolder);
            else VireSeal.LoadFromEnvironment();
            if (rest.Length < 1)
            {
                Console.Error.WriteLine("usage: vire program.vire [args...]");
                return 2;
            }
            if (rest[0] == "payload-sha256")
            {
                if (rest.Length < 2) throw new VireError("usage: vire payload-sha256 file.vc", 1);
                byte[] packed = File.ReadAllBytes(Path.GetFullPath(rest[1]));
                Console.WriteLine(VireSeal.PayloadSha256(packed));
                return 0;
            }
            if (rest[0] == "payload-write")
            {
                if (rest.Length < 3) throw new VireError("usage: vire payload-write file.vc dest.bin", 1);
                byte[] packed = File.ReadAllBytes(Path.GetFullPath(rest[1]));
                byte[] plain = VireSeal.OpenBytes(packed);
                try { File.WriteAllBytes(Path.GetFullPath(rest[2]), plain); }
                finally { CryptographicOperations.ZeroMemory(plain); }
                return 0;
            }
            if (rest[0] == "run")
            {
                if (rest.Length < 2) throw new VireError("usage: vire run file.vc", 1);
                string compiled = Path.GetFullPath(rest[1]);
                string compiledFolder = Path.GetDirectoryName(compiled);
                List<object> compiledArgs = new List<object>();
                for (int i = 2; i < rest.Length; i++) compiledArgs.Add(rest[i]);
                CompiledProgram.Run(compiled, compiledFolder, compiledArgs);
                return 0;
            }
            string program = Path.GetFullPath(rest[0]);
            string folder = Path.GetDirectoryName(program);
            int budget = BudgetOf(File.ReadAllText(program));
            Dictionary<string, Func> funcs = Load(program, folder, new HashSet<string>());
            if (!funcs.ContainsKey("main")) throw new VireError("a vire program needs define main", 1);
            Machine machine = new Machine(funcs, folder);
            machine.UseBudget(budget);
            List<object> extra = new List<object>();
            for (int i = 1; i < rest.Length; i++) extra.Add(rest[i]);
            machine.UseArgs(extra);
            machine.Run();
            return 0;
        }
        catch (HaltSignal halt)
        {
            return halt.Code;
        }
        catch (VireError exc)
        {
            return WriteVireError(exc);
        }
        catch (OutOfMemoryException)
        {
            return WriteVireError(new VireError("ran out of memory", 1));
        }
        catch (Exception ex)
        {
            if (Environment.GetEnvironmentVariable("VIRE_DEBUG") == "1")
                Console.Error.WriteLine(ex.ToString());
            else
                Console.Error.WriteLine("vire: internal error (" + ex.GetType().Name + ")");
            return 3;
        }
    }

    static string[] StripKeyFile(string[] args, out string keyFile)
    {
        keyFile = null;
        List<string> rest = new List<string>();
        for (int i = 0; i < args.Length; i++)
        {
            if (args[i] == "--seal-key-file")
            {
                if (i + 1 >= args.Length) throw new VireError("usage: --seal-key-file <path>", 1);
                keyFile = args[i + 1];
                i++;
                continue;
            }
            rest.Add(args[i]);
        }
        return rest.ToArray();
    }
}
