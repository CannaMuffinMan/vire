using System;
using System.Collections.Generic;
using System.Globalization;
using System.IO;
using System.Net;
using System.Net.Sockets;
using System.Text;
using System.Windows.Forms;

sealed class VireError : Exception
{
    public int Line;
    public VireError(string message, int line) : base(message) { Line = line; }
}

sealed class ReturnSignal : Exception
{
    public object Value;
    public ReturnSignal(object value) { Value = value; }
}

sealed class StopSignal : Exception { }
sealed class SkipSignal : Exception { }

sealed class Token
{
    public string Kind;
    public object Value;
    public int Line;
    public Token(string kind, object value, int line)
    {
        Kind = kind;
        Value = value;
        Line = line;
    }
}

sealed class Func
{
    public List<string> Params = new List<string>();
    public List<object> Body = new List<object>();
    public int Line;
}

sealed class Env
{
    public Env Parent;
    public Dictionary<string, object> Values = new Dictionary<string, object>();
    public void Declare(string name, object value) { Values[name] = value; }
    public bool Has(string name)
    {
        if (Values.ContainsKey(name)) return true;
        return Parent != null && Parent.Has(name);
    }

    public object Get(string name, int line)
    {
        if (Values.ContainsKey(name)) return Values[name];
        if (Parent != null) return Parent.Get(name, line);
        throw new VireError(name + " has no value", line);
    }
}

sealed class Stroke
{
    public string Kind;
    public int A, B, C, D;
    public System.Drawing.Color Color;
    public Stroke(string kind, int a, int b, int c, int d, System.Drawing.Color color)
    {
        Kind = kind; A = a; B = b; C = c; D = d; Color = color;
    }
}

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
            using (System.Drawing.Pen pen = new System.Drawing.Pen(mark.Color, 2))
            using (System.Drawing.SolidBrush brush = new System.Drawing.SolidBrush(mark.Color))
            {
                if (mark.Kind == "fill") e.Graphics.FillRectangle(brush, mark.A, mark.B, mark.C, mark.D);
                else if (mark.Kind == "stroke") e.Graphics.DrawLine(pen, mark.A, mark.B, mark.C, mark.D);
                else e.Graphics.FillEllipse(brush, mark.A - mark.C, mark.B - mark.C, mark.C * 2, mark.C * 2);
            }
        }
    }
}

sealed class Machine
{
    const int MaxCalls = 64;
    const int MaxItems = 100000;
    const int MaxText = 1000000;
    const int MaxSteps = 1000000;
    int steps;
    Dictionary<string, Func> funcs;
    string root;
    int depth;
    int calls;
    Form form;
    int nextTop = 16;
    int nextLeft = 16;
    Dictionary<string, TextBox> fields = new Dictionary<string, TextBox>();
    SheetBox sheet;
    System.Drawing.Color inkColor = System.Drawing.Color.Black;
    string watchName;
    int watchLine;

    static readonly HashSet<string> Builtins = new HashSet<string>(new string[] {
        "length", "push", "text", "number", "ask", "read", "write", "slice", "keys", "has", "kind", "join",
        "abs", "min", "max", "lower", "upper", "split", "find", "span", "drop", "sort", "escape", "serve",
        "files", "json", "parse", "now", "fetch", "open", "line", "field", "button", "value", "show", "place", "mark",
        "sheet", "ink", "stroke", "fill", "dot", "watch"
    });

    public Machine(Dictionary<string, Func> funcs, string root)
    {
        this.funcs = funcs;
        this.root = Path.GetFullPath(root);
    }

    public void Run() { Call("main", new List<object>(), 1); }

    void Step(int line)
    {
        steps++;
        if (steps > MaxSteps) throw new VireError("program ran too long and was stopped", line);
    }

    string SafePath(object text, int line)
    {
        string rawText = text as string;
        if (rawText == null || rawText.Trim().Length == 0)
            throw new VireError("a file path must be text", line);
        if (Path.IsPathRooted(rawText) || rawText.Contains(".."))
            throw new VireError("files stay inside the program folder", line);
        string path = Path.GetFullPath(Path.Combine(root, rawText));
        string rootFull = root.TrimEnd(Path.DirectorySeparatorChar) + Path.DirectorySeparatorChar;
        if (!path.StartsWith(rootFull, StringComparison.OrdinalIgnoreCase) &&
            !string.Equals(path, root, StringComparison.OrdinalIgnoreCase))
            throw new VireError("files stay inside the program folder", line);
        return path;
    }

    public object Call(string name, List<object> args, int line)
    {
        if (Builtins.Contains(name)) return Builtin(name, args, line);
        if (!funcs.ContainsKey(name))
            throw new VireError("there is no definition named " + name, line);
        Func func = funcs[name];
        if (args.Count != func.Params.Count)
            throw new VireError(name + " takes " + func.Params.Count + " values, got " + args.Count, line);
        calls++;
        try
        {
            if (calls > MaxCalls) throw new VireError("definitions called too deeply", line);
            Env env = new Env();
            for (int i = 0; i < func.Params.Count; i++) env.Declare(func.Params[i], args[i]);
            try { ExecBlock(func.Body, env); }
            catch (ReturnSignal signal) { return signal.Value; }
            return null;
        }
        finally { calls--; }
    }

    object Builtin(string name, List<object> args, int line)
    {
        Step(line);
        int need = 1;
        if (name == "now" || name == "show") need = 0;
        if (name == "push" || name == "write" || name == "has" || name == "join" || name == "min" || name == "max" || name == "split" || name == "find" || name == "span" || name == "button" || name == "place" || name == "sheet") need = 2;
        if (name == "ink" || name == "dot") need = 3;
        if (name == "stroke" || name == "fill") need = 4;
        if (name == "mark") need = 5;
        if (name == "serve" || name == "escape") need = 1;
        if (name == "slice") need = 3;
        if (args.Count != need) throw new VireError(name + " takes " + need + " values, got " + args.Count, line);
        if (name == "length")
        {
            if (args[0] is string) return ((string)args[0]).Length;
            if (args[0] is List<object>) return ((List<object>)args[0]).Count;
            if (args[0] is Dictionary<string, object>) return ((Dictionary<string, object>)args[0]).Count;
            throw new VireError("length needs text, a list, or a map", line);
        }
        if (name == "push")
        {
            List<object> list = args[0] as List<object>;
            if (list == null) throw new VireError("push needs a list", line);
            if (list.Count >= MaxItems) throw new VireError("list is too large", line);
            list.Add(args[1]);
            return list;
        }
        if (name == "text") return Show(args[0]);
        if (name == "number")
        {
            if (IsNum(args[0])) return args[0];
            string raw = args[0] as string;
            if (raw == null) throw new VireError("number needs text or a number", line);
            int whole;
            double real;
            if (raw.IndexOf('.') < 0 && int.TryParse(raw, out whole)) return whole;
            if (double.TryParse(raw, NumberStyles.Float, CultureInfo.InvariantCulture, out real)) return real;
            throw new VireError("that text is not a number", line);
        }
        if (name == "ask")
        {
            if (!(args[0] is string)) throw new VireError("ask needs text", line);
            Console.Write((string)args[0]);
            return Console.ReadLine() ?? "";
        }
        if (name == "read")
        {
            string path = SafePath(args[0], line);
            string text;
            try { text = File.ReadAllText(path); }
            catch (IOException) { throw new VireError("could not read that file", line); }
            catch (UnauthorizedAccessException) { throw new VireError("could not read that file", line); }
            if (text.Length > MaxText) throw new VireError("file is too large", line);
            return text;
        }
        if (name == "write")
        {
            string path = SafePath(args[0], line);
            string text = Show(args[1]);
            if (text.Length > MaxText) throw new VireError("text is too large to write", line);
            string ext = Path.GetExtension(path).ToLowerInvariant();
            if (ext == ".exe" || ext == ".dll" || ext == ".bat" || ext == ".cmd" || ext == ".ps1" || ext == ".com" || ext == ".scr" || ext == ".vbs" || ext == ".msi")
                throw new VireError("vire will not write a program file", line);
            try
            {
                string parent = Path.GetDirectoryName(path);
                if (parent != null && parent.Length > 0) Directory.CreateDirectory(parent);
                File.WriteAllText(path, text);
            }
            catch (IOException) { throw new VireError("could not write that file", line); }
            catch (UnauthorizedAccessException) { throw new VireError("could not write that file", line); }
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
            if (list == null) throw new VireError("slice needs text or a list", line);
            return SliceList(list, start, end);
        }
        if (name == "keys")
        {
            Dictionary<string, object> map = args[0] as Dictionary<string, object>;
            if (map == null) throw new VireError("keys needs a map", line);
            return new List<object>(map.Keys);
        }
        if (name == "has")
        {
            Dictionary<string, object> map = args[0] as Dictionary<string, object>;
            if (map == null) throw new VireError("has needs a map", line);
            return map.ContainsKey(KeyOf(args[1], line));
        }
        if (name == "kind") return KindOf(args[0]);
        if (name == "abs")
        {
            if (!IsNum(args[0])) throw new VireError("abs needs a number", line);
            if (args[0] is int) { int n = (int)args[0]; return n < 0 ? -n : n; }
            double real = (double)args[0];
            return real < 0 ? -real : real;
        }
        if (name == "min" || name == "max")
        {
            if (!IsNum(args[0]) || !IsNum(args[1])) throw new VireError(name + " needs two numbers", line);
            bool left = ToDouble(args[0]) <= ToDouble(args[1]);
            return name == "min" ? (left ? args[0] : args[1]) : (left ? args[1] : args[0]);
        }
        if (name == "lower" || name == "upper")
        {
            string raw = args[0] as string;
            if (raw == null) throw new VireError(name + " needs text", line);
            return name == "lower" ? raw.ToLowerInvariant() : raw.ToUpperInvariant();
        }
        if (name == "split")
        {
            string raw = args[0] as string;
            string sep = args[1] as string;
            if (raw == null || sep == null || sep.Length == 0) throw new VireError("split needs text and a separator", line);
            string[] bits = raw.Split(new string[] { sep }, StringSplitOptions.None);
            List<object> items = new List<object>();
            foreach (string bit in bits) items.Add(bit);
            return items;
        }
        if (name == "find")
        {
            string raw = args[0] as string;
            string needle = args[1] as string;
            if (raw == null || needle == null) throw new VireError("find needs two texts", line);
            return raw.IndexOf(needle);
        }
        if (name == "span")
        {
            if (!(args[0] is int) || !(args[1] is int)) throw new VireError("span needs two whole numbers", line);
            int from = (int)args[0];
            int to = (int)args[1];
            if (to < from || to - from > MaxItems) throw new VireError("span is too large", line);
            List<object> items = new List<object>();
            for (int n = from; n <= to; n++) items.Add(n);
            return items;
        }
        if (name == "drop")
        {
            List<object> list = args[0] as List<object>;
            if (list == null || list.Count == 0) throw new VireError("drop needs a non-empty list", line);
            object last = list[list.Count - 1];
            list.RemoveAt(list.Count - 1);
            return last;
        }
        if (name == "sort")
        {
            List<object> list = args[0] as List<object>;
            if (list == null) throw new VireError("sort needs a list of numbers", line);
            List<object> copy = new List<object>(list);
            copy.Sort(delegate(object a, object b)
            {
                if (!IsNum(a) || !IsNum(b)) throw new VireError("sort needs a list of numbers", line);
                return ToDouble(a).CompareTo(ToDouble(b));
            });
            return copy;
        }
        if (name == "escape")
        {
            string raw = args[0] as string;
            if (raw == null) raw = Show(args[0]);
            return raw.Replace("&", "&amp;").Replace("<", "&lt;").Replace(">", "&gt;").Replace("\"", "&quot;");
        }
        if (name == "serve")
        {
            if (!(args[0] is int)) throw new VireError("serve needs a port number", line);
            Serve((int)args[0], line);
            return 0;
        }
        if (name == "files")
        {
            string path = SafePath(args[0], line);
            if (!Directory.Exists(path)) throw new VireError("there is no folder by that name", line);
            List<object> names = new List<object>();
            foreach (string file in Directory.GetFiles(path)) names.Add(Path.GetFileName(file));
            return names;
        }
        if (name == "json") return Json.Write(args[0]);
        if (name == "parse")
        {
            string raw = args[0] as string;
            if (raw == null) throw new VireError("parse needs text", line);
            return Json.Read(raw, line);
        }
        if (name == "now") return DateTime.Now.ToString("yyyy-MM-dd HH:mm:ss");
        if (name == "fetch")
        {
            string url = args[0] as string;
            if (url == null || !(url.StartsWith("https://") || url.StartsWith("http://")))
                throw new VireError("fetch needs an http or https address", line);
            try
            {
                HttpWebRequest request = (HttpWebRequest)WebRequest.Create(url);
                request.Method = "GET";
                request.Timeout = 5000;
                request.ReadWriteTimeout = 5000;
                request.UserAgent = "Vire";
                request.MaximumAutomaticRedirections = 2;
                using (HttpWebResponse response = (HttpWebResponse)request.GetResponse())
                using (Stream stream = response.GetResponseStream())
                {
                    byte[] data = new byte[1000001];
                    int used = 0;
                    int n;
                    while (used < data.Length && (n = stream.Read(data, used, data.Length - used)) > 0) used += n;
                    if (used > 1000000) throw new VireError("the response is too large", line);
                    return Encoding.UTF8.GetString(data, 0, used);
                }
            }
            catch (VireError) { throw; }
            catch (Exception) { throw new VireError("could not fetch that address", line); }
        }
        if (name == "open")
        {
            string title = args[0] as string;
            if (title == null) throw new VireError("open needs a window title", line);
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
            if (fieldName == null) throw new VireError("field needs a name", line);
            AddField(fieldName, line);
            return 0;
        }
        if (name == "button")
        {
            string label = args[0] as string;
            string func = args[1] as string;
            if (label == null || func == null) throw new VireError("button needs a label and a definition name", line);
            AddButton(label, func, line);
            return 0;
        }
        if (name == "place")
        {
            if (!(args[0] is int) || !(args[1] is int)) throw new VireError("place needs two whole numbers", line);
            if (form == null) throw new VireError("open a window first", line);
            nextLeft = (int)args[0];
            nextTop = (int)args[1];
            return 0;
        }
        if (name == "mark")
        {
            if (!(args[0] is int) || !(args[1] is int) || !(args[2] is int) || !(args[3] is int))
                throw new VireError("mark needs four whole numbers and a definition name", line);
            string func = args[4] as string;
            if (func == null) throw new VireError("mark needs four whole numbers and a definition name", line);
            AddMark((int)args[0], (int)args[1], (int)args[2], (int)args[3], func, line);
            return 0;
        }
        if (name == "sheet")
        {
            if (!(args[0] is int) || !(args[1] is int)) throw new VireError("sheet needs a width and a height", line);
            AddSheet((int)args[0], (int)args[1], line);
            return 0;
        }
        if (name == "ink")
        {
            inkColor = ColorOf(args[0], args[1], args[2], line);
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
            if (!(args[0] is int) || !(args[1] is int) || !(args[2] is int)) throw new VireError("dot needs three whole numbers", line);
            RequireSheet(line);
            sheet.Ops.Add(new Stroke("dot", (int)args[0], (int)args[1], (int)args[2], 0, inkColor));
            sheet.Invalidate();
            return 0;
        }
        if (name == "watch")
        {
            string func = args[0] as string;
            if (func == null || !funcs.ContainsKey(func)) throw new VireError("watch needs a definition name", line);
            RequireSheet(line);
            watchName = func;
            watchLine = line;
            return 0;
        }
        if (name == "value")
        {
            string fieldName = args[0] as string;
            TextBox box;
            if (fieldName == null || !fields.TryGetValue(fieldName, out box))
                throw new VireError("there is no field by that name", line);
            return box.Text;
        }
        if (name == "show")
        {
            if (form == null) throw new VireError("open a window before show", line);
            Application.Run(form);
            return 0;
        }
        List<object> parts = args[0] as List<object>;
        string joiner = args[1] as string;
        if (parts == null || joiner == null) throw new VireError("join needs a list of text", line);
        string[] joined = new string[parts.Count];
        for (int i = 0; i < parts.Count; i++)
        {
            if (!(parts[i] is string)) throw new VireError("join needs a list of text", line);
            joined[i] = (string)parts[i];
        }
        return string.Join(joiner, joined);
    }

    void OpenWindow(string title)
    {
        form = new Form();
        form.Text = title;
        form.Width = 520;
        form.Height = 420;
        form.StartPosition = FormStartPosition.CenterScreen;
        nextTop = 16;
        nextLeft = 16;
        fields = new Dictionary<string, TextBox>();
    }

    void AddLine(string text, int line)
    {
        if (form == null) throw new VireError("open a window first", line);
        Label label = new Label();
        label.Text = text;
        label.Left = nextLeft;
        label.Top = nextTop;
        label.Width = 470;
        label.Height = 24;
        form.Controls.Add(label);
        nextTop += 28;
    }

    void AddField(string name, int line)
    {
        if (form == null) throw new VireError("open a window first", line);
        TextBox box = new TextBox();
        box.Left = nextLeft;
        box.Top = nextTop;
        box.Width = 470;
        form.Controls.Add(box);
        fields[name] = box;
        nextTop += 32;
    }

    void AddButton(string label, string func, int line)
    {
        if (form == null) throw new VireError("open a window first", line);
        if (!funcs.ContainsKey(func)) throw new VireError("there is no definition named " + func, line);
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
    }

    void AddMark(int x, int y, int w, int h, string func, int line)
    {
        if (form == null) throw new VireError("open a window first", line);
        if (!funcs.ContainsKey(func)) throw new VireError("there is no definition named " + func, line);
        Panel panel = new Panel();
        panel.Left = x;
        panel.Top = y;
        panel.Width = w;
        panel.Height = h;
        panel.BackColor = System.Drawing.Color.FromArgb(176, 98, 58);
        panel.Click += delegate
        {
            try { Call(func, new List<object>(), line); }
            catch (VireError exc) { MessageBox.Show(exc.Message, "Vire"); }
        };
        form.Controls.Add(panel);
    }

    void AddSheet(int width, int height, int line)
    {
        if (form == null) throw new VireError("open a window first", line);
        if (width < 1 || height < 1 || width > 2000 || height > 2000) throw new VireError("sheet size is out of range", line);
        sheet = new SheetBox();
        sheet.Left = nextLeft;
        sheet.Top = nextTop;
        sheet.Width = width;
        sheet.Height = height;
        sheet.MouseClick += delegate(object sender, MouseEventArgs ev) { HitSheet(ev.X, ev.Y); };
        form.Controls.Add(sheet);
        nextTop += height + 12;
    }

    void HitSheet(int x, int y)
    {
        if (watchName == null || sheet == null) return;
        Func func = funcs[watchName];
        List<object> args = new List<object>();
        if (func.Params.Count >= 1) args.Add(x);
        if (func.Params.Count >= 2) args.Add(y);
        try { Call(watchName, args, watchLine); }
        catch (VireError exc) { MessageBox.Show(exc.Message, "Vire"); }
        sheet.Invalidate();
    }

    void RequireSheet(int line)
    {
        if (sheet == null) throw new VireError("open a sheet first", line);
    }

    static System.Drawing.Color ColorOf(object r, object g, object b, int line)
    {
        if (!(r is int) || !(g is int) || !(b is int)) throw new VireError("ink needs three whole numbers", line);
        int rr = (int)r, gg = (int)g, bb = (int)b;
        if (rr < 0 || rr > 255 || gg < 0 || gg > 255 || bb < 0 || bb > 255) throw new VireError("ink numbers run from 0 to 255", line);
        return System.Drawing.Color.FromArgb(rr, gg, bb);
    }

    void Draw(string kind, List<object> args, int line)
    {
        if (!(args[0] is int) || !(args[1] is int) || !(args[2] is int) || !(args[3] is int))
            throw new VireError(kind + " needs four whole numbers", line);
        RequireSheet(line);
        if (sheet.Ops.Count > 10000) throw new VireError("the sheet has too many marks", line);
        sheet.Ops.Add(new Stroke(kind, (int)args[0], (int)args[1], (int)args[2], (int)args[3], inkColor));
        sheet.Invalidate();
    }

    void Serve(int port, int line)
    {
        if (port < 1024 || port > 65535) throw new VireError("port must be from 1024 to 65535", line);
        string site = Path.Combine(root, "site");
        if (!Directory.Exists(site)) throw new VireError("there is no site folder to serve", line);
        System.Net.Sockets.TcpListener listener = new System.Net.Sockets.TcpListener(System.Net.IPAddress.Loopback, port);
        listener.Start();
        Console.WriteLine("open http://127.0.0.1:" + port + "/  (this machine only)");
        try
        {
            while (true)
            {
                System.Net.Sockets.TcpClient client = listener.AcceptTcpClient();
                client.ReceiveTimeout = 2000;
                client.SendTimeout = 2000;
                try { Answer(client, site); }
                catch (IOException) { }
                finally { client.Close(); }
            }
        }
        finally { listener.Stop(); }
    }

    static void Answer(System.Net.Sockets.TcpClient client, string site)
    {
        NetworkStream stream = client.GetStream();
        byte[] buffer = new byte[4096];
        int got = stream.Read(buffer, 0, buffer.Length);
        string request = Encoding.ASCII.GetString(buffer, 0, got);
        int lineEnd = request.IndexOf("\r\n");
        if (lineEnd < 0) { Send(stream, 400, "text/plain", "bad request"); return; }
        string[] bits = request.Substring(0, lineEnd).Split(' ');
        if (bits.Length < 2 || (bits[0] != "GET" && bits[0] != "HEAD")) { Send(stream, 405, "text/plain", "method not allowed"); return; }
        string url = bits[1];
        int query = url.IndexOf('?');
        if (query >= 0) url = url.Substring(0, query);
        if (url == "/") url = "/index.html";
        url = url.Replace('/', Path.DirectorySeparatorChar);
        if (url.Contains("..") || url.IndexOf(':') >= 0) { Send(stream, 403, "text/plain", "forbidden"); return; }
        string ext = Path.GetExtension(url).ToLowerInvariant();
        string type = ext == ".html" ? "text/html" : ext == ".css" ? "text/css" : ext == ".js" ? "text/javascript" : ext == ".svg" ? "image/svg+xml" : ext == ".json" ? "application/json" : ext == ".txt" ? "text/plain" : null;
        if (type == null) { Send(stream, 403, "text/plain", "forbidden"); return; }
        string path = Path.GetFullPath(Path.Combine(site, url.TrimStart(Path.DirectorySeparatorChar)));
        string siteFull = Path.GetFullPath(site).TrimEnd(Path.DirectorySeparatorChar) + Path.DirectorySeparatorChar;
        if (!path.StartsWith(siteFull, StringComparison.OrdinalIgnoreCase) || !File.Exists(path)) { Send(stream, 404, "text/plain", "not found"); return; }
        byte[] body = File.ReadAllBytes(path);
        if (body.Length > 1000000) { Send(stream, 413, "text/plain", "too large"); return; }
        Send(stream, 200, type, bits[0] == "HEAD" ? "" : Encoding.UTF8.GetString(body));
    }

    static void Send(NetworkStream stream, int code, string type, string body)
    {
        byte[] data = Encoding.UTF8.GetBytes(body);
        string head = "HTTP/1.0 " + code + " OK\r\nContent-Type: " + type + "\r\nContent-Length: " + data.Length + "\r\nConnection: close\r\n\r\n";
        byte[] prefix = Encoding.ASCII.GetBytes(head);
        stream.Write(prefix, 0, prefix.Length);
        if (data.Length > 0) stream.Write(data, 0, data.Length);
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
            object target = env.Get((string)stmt[2], (int)stmt[4]);
            Store(target, Eval(stmt[3], env), Eval(stmt[1], env), (int)stmt[4]);
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
            if (depth < 1) throw new VireError("stop is only valid inside while or for", (int)stmt[1]);
            throw new StopSignal();
        }
        if (kind == "skip")
        {
            if (depth < 1) throw new VireError("skip is only valid inside while or for", (int)stmt[1]);
            throw new SkipSignal();
        }
        if (kind == "while")
        {
            int guard = 0;
            depth++;
            try
            {
                while (Truth(Eval(stmt[1], env)))
                {
                    guard++;
                    if (guard > 100000) throw new VireError("while ran too long", (int)stmt[3]);
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
            else throw new VireError("for walks a list, map, or text", (int)stmt[4]);
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
            Call((string)stmt[1], args, (int)stmt[3]);
            return;
        }
        throw new VireError("unknown statement", 0);
    }

    void Store(object target, object index, object value, int line)
    {
        List<object> list = target as List<object>;
        if (list != null)
        {
            list[IndexOf(index, line, list.Count)] = value;
            return;
        }
        Dictionary<string, object> map = target as Dictionary<string, object>;
        if (map != null)
        {
            map[KeyOf(index, line)] = value;
            return;
        }
        if (target is string) throw new VireError("text cannot be changed in place", line);
        throw new VireError("put needs a list or a map", line);
    }

    object Eval(object node, Env env)
    {
        object[] tree = (object[])node;
        string kind = (string)tree[0];
        if (kind == "num" || kind == "str" || kind == "bool") return tree[1];
        if (kind == "none") return null;
        if (kind == "now") return Builtin("now", new List<object>(), (int)tree[1]);
        if (kind == "var")
        {
            string name = (string)tree[1];
            if (!env.Has(name) && funcs.ContainsKey(name) && funcs[name].Params.Count == 0)
                return Call(name, new List<object>(), (int)tree[2]);
            return env.Get(name, (int)tree[2]);
        }
        if (kind == "call")
        {
            List<object> args = new List<object>();
            foreach (object arg in (List<object>)tree[2]) args.Add(Eval(arg, env));
            return Call((string)tree[1], args, (int)tree[3]);
        }
        if (kind == "list")
        {
            List<object> items = new List<object>();
            foreach (object item in (List<object>)tree[1])
            {
                if (items.Count >= MaxItems) throw new VireError("list is too large", (int)tree[2]);
                items.Add(Eval(item, env));
            }
            return items;
        }
        if (kind == "map")
        {
            Dictionary<string, object> made = new Dictionary<string, object>();
            foreach (object[] pair in (List<object[]>)tree[1])
            {
                if (made.Count >= MaxItems) throw new VireError("map is too large", (int)tree[2]);
                made[KeyOf(Eval(pair[0], env), (int)tree[2])] = Eval(pair[1], env);
            }
            return made;
        }
        if (kind == "at") return Lookup(Eval(tree[1], env), Eval(tree[2], env), (int)tree[3]);
        if (kind == "not") return !Truth(Eval(tree[1], env));
        if (kind == "neg")
        {
            object value = Eval(tree[1], env);
            if (!IsNum(value)) throw new VireError("minus applies to numbers", (int)tree[2]);
            if (value is int) return -((int)value);
            return -((double)value);
        }
        if (kind == "bin") return Binary(tree, env);
        throw new VireError("unknown expression", 0);
    }

    object Lookup(object target, object index, int line)
    {
        if (target is List<object>)
        {
            List<object> list = (List<object>)target;
            return list[IndexOf(index, line, list.Count)];
        }
        if (target is string)
        {
            string text = (string)target;
            return text.Substring(IndexOf(index, line, text.Length), 1);
        }
        Dictionary<string, object> map = target as Dictionary<string, object>;
        if (map != null)
        {
            string key = KeyOf(index, line);
            if (!map.ContainsKey(key)) throw new VireError("map has no key " + key, line);
            return map[key];
        }
        throw new VireError("at needs a list, text, or map", line);
    }

    object Binary(object[] node, Env env)
    {
        string op = (string)node[1];
        int line = (int)node[4];
        if (op == "and") return Truth(Eval(node[2], env)) && Truth(Eval(node[3], env));
        if (op == "or") return Truth(Eval(node[2], env)) || Truth(Eval(node[3], env));
        object left = Eval(node[2], env);
        object right = Eval(node[3], env);
        if (op == "==") return Equals(left, right);
        if (op == "!=") return !Equals(left, right);
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
            throw new VireError("plus needs numbers, text, or lists", line);
        }
        if (!IsNum(left) || !IsNum(right)) throw new VireError(op + " needs two numbers", line);
        if (op == "-") return Sub(left, right);
        if (op == "*") return Mul(left, right);
        if (op == "/")
        {
            if (ToDouble(right) == 0) throw new VireError("division by zero", line);
            return ToDouble(left) / ToDouble(right);
        }
        if (op == "%")
        {
            if (ToDouble(right) == 0) throw new VireError("division by zero", line);
            if (left is int && right is int) return ((int)left) % ((int)right);
            return ToDouble(left) % ToDouble(right);
        }
        double a = ToDouble(left);
        double b = ToDouble(right);
        if (op == "<") return a < b;
        if (op == ">") return a > b;
        if (op == "<=") return a <= b;
        if (op == ">=") return a >= b;
        throw new VireError("unknown operator " + op, line);
    }

    static bool Equals(object left, object right)
    {
        if (left == null || right == null) return left == null && right == null;
        if (IsNum(left) && IsNum(right)) return ToDouble(left) == ToDouble(right);
        return left.Equals(right);
    }

    static object Add(object left, object right)
    {
        if (left is int && right is int) return (int)left + (int)right;
        return ToDouble(left) + ToDouble(right);
    }
    static object Sub(object left, object right)
    {
        if (left is int && right is int) return (int)left - (int)right;
        return ToDouble(left) - ToDouble(right);
    }
    static object Mul(object left, object right)
    {
        if (left is int && right is int) return (int)left * (int)right;
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
        if (value is bool || !(value is int)) throw new VireError("an index must be a whole number", line);
        int index = (int)value;
        if (index < 0) index += size;
        if (index < 0 || index >= size) throw new VireError("index is outside the value", line);
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
        if (value is bool) return (bool)value ? "true" : "false";
        if (value == null) return "none";
        if (value is double)
        {
            double real = (double)value;
            if (real == Math.Floor(real) && !double.IsInfinity(real)) return ((long)real).ToString();
            return real.ToString(CultureInfo.InvariantCulture);
        }
        if (value is List<object>)
        {
            List<object> list = (List<object>)value;
            string[] parts = new string[list.Count];
            for (int i = 0; i < list.Count; i++) parts[i] = Show(list[i]);
            return "[" + string.Join(", ", parts) + "]";
        }
        if (value is Dictionary<string, object>)
        {
            Dictionary<string, object> map = (Dictionary<string, object>)value;
            List<string> parts = new List<string>();
            foreach (KeyValuePair<string, object> pair in map) parts.Add(Show(pair.Key) + ": " + Show(pair.Value));
            return "{" + string.Join(", ", parts.ToArray()) + "}";
        }
        return Convert.ToString(value, CultureInfo.InvariantCulture);
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
        if (tok.Kind != kind) throw new VireError("expected " + kind + ", found " + tok.Kind, tok.Line);
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
                if (Peek().Kind != "string") throw new VireError("use needs a file name in quotes", use.Line);
                unit.Uses.Add((string)Eat("string").Value);
                continue;
            }
            if (At("need"))
            {
                Token need = Eat("need");
                if (Peek().Kind != "string") throw new VireError("need takes a package name in quotes", need.Line);
                unit.Needs.Add((string)Eat("string").Value);
                continue;
            }
            Func func = Definition();
            string name = (string)func.Body[0];
            func.Body.RemoveAt(0);
            if (unit.Funcs.ContainsKey(name)) throw new VireError(name + " is already defined", func.Line);
            unit.Funcs[name] = func;
        }
        return unit;
    }

    Func Definition()
    {
        Token start = Eat("define");
        Func func = new Func();
        func.Line = start.Line;
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
        List<object> stmts = new List<object>();
        while (!At("end", "else", "miss", "eof")) stmts.Add(Statement());
        if (At("eof")) throw new VireError("block is missing end", Peek().Line);
        return stmts;
    }

    object Statement()
    {
        Token tok = Peek();
        if (tok.Kind == "let")
        {
            Eat("let");
            string name = (string)Eat("name").Value;
            Eat("be");
            return new object[] { "let", name, Expression(), tok.Line };
        }
        if (tok.Kind == "put")
        {
            Eat("put");
            object value = Expression();
            Eat("into");
            string name = (string)Eat("name").Value;
            Eat("at");
            return new object[] { "put", value, name, Expression(), tok.Line };
        }
        if (tok.Kind == "say") { Eat("say"); return new object[] { "say", Expression(), tok.Line }; }
        if (tok.Kind == "return") { Eat("return"); return new object[] { "return", Expression(), tok.Line }; }
        if (tok.Kind == "stop") { Eat("stop"); return new object[] { "stop", tok.Line }; }
        if (tok.Kind == "skip") { Eat("skip"); return new object[] { "skip", tok.Line }; }
        if (tok.Kind == "while")
        {
            Eat("while");
            object test = Expression();
            List<object> body = Block();
            Eat("end");
            return new object[] { "while", test, body, tok.Line };
        }
        if (tok.Kind == "for")
        {
            Eat("for");
            string name = (string)Eat("name").Value;
            Eat("in");
            object seq = Expression();
            List<object> body = Block();
            Eat("end");
            return new object[] { "for", name, seq, body, tok.Line };
        }
        if (tok.Kind == "if") return IfStmt(tok.Line, true);
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
            return new object[] { "try", body, caught, handler, tok.Line };
        }
        if (tok.Kind == "name")
        {
            string name = (string)Eat("name").Value;
            return new object[] { "call", name, Arguments(), tok.Line };
        }
        throw new VireError("line does not start a statement", tok.Line);
    }

    object IfStmt(int line, bool close)
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
                wrapped.Add(IfStmt(Peek().Line, false));
                other = wrapped;
            }
            else other = Block();
        }
        if (close) Eat("end");
        return new object[] { "if", test, body, other, line };
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

    object Expression() { return ParseOr(); }
    object ParseOr()
    {
        object node = ParseAnd();
        while (At("or"))
        {
            Token op = Eat("or");
            node = new object[] { "bin", "or", node, ParseAnd(), op.Line };
        }
        return node;
    }
    object ParseAnd()
    {
        object node = ParseCmp();
        while (At("and"))
        {
            Token op = Eat("and");
            node = new object[] { "bin", "and", node, ParseCmp(), op.Line };
        }
        return node;
    }
    object ParseCmp()
    {
        object node = ParseSum();
        while (At("==", "!=", "<", ">", "<=", ">="))
        {
            Token op = Eat(Peek().Kind);
            node = new object[] { "bin", op.Kind, node, ParseSum(), op.Line };
        }
        return node;
    }
    object ParseSum()
    {
        object node = ParseProduct();
        while (At("+", "-"))
        {
            Token op = Eat(Peek().Kind);
            node = new object[] { "bin", op.Kind, node, ParseProduct(), op.Line };
        }
        return node;
    }
    object ParseProduct()
    {
        object node = ParseUnary();
        while (At("*", "/", "%"))
        {
            Token op = Eat(Peek().Kind);
            node = new object[] { "bin", op.Kind, node, ParseUnary(), op.Line };
        }
        return node;
    }
    object ParseUnary()
    {
        if (At("not"))
        {
            Token op = Eat("not");
            return new object[] { "not", ParseUnary(), op.Line };
        }
        if (At("-"))
        {
            Token op = Eat("-");
            return new object[] { "neg", ParseUnary(), op.Line };
        }
        return ParsePrimary();
    }
    object ParsePrimary()
    {
        object node = Atom();
        while (At("at"))
        {
            Token op = Eat("at");
            node = new object[] { "at", node, Atom(), op.Line };
        }
        return node;
    }
    object Atom()
    {
        Token tok = Peek();
        if (tok.Kind == "number") { Eat("number"); return new object[] { "num", tok.Value, tok.Line }; }
        if (tok.Kind == "string") { Eat("string"); return new object[] { "str", tok.Value, tok.Line }; }
        if (tok.Kind == "true") { Eat("true"); return new object[] { "bool", true, tok.Line }; }
        if (tok.Kind == "false") { Eat("false"); return new object[] { "bool", false, tok.Line }; }
        if (tok.Kind == "none") { Eat("none"); return new object[] { "none", null, tok.Line }; }
        if (tok.Kind == "now") { Eat("now"); return new object[] { "now", tok.Line }; }
        if (tok.Kind == "name")
        {
            Eat("name");
            if (At("with")) return new object[] { "call", tok.Value, Arguments(), tok.Line };
            return new object[] { "var", tok.Value, tok.Line };
        }
        if (tok.Kind == "(")
        {
            Eat("(");
            object node = Expression();
            Eat(")");
            return node;
        }
        if (tok.Kind == "[") return ListLiteral(tok.Line);
        if (tok.Kind == "{") return MapLiteral(tok.Line);
        throw new VireError("expected a value", tok.Line);
    }
    object ListLiteral(int line)
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
        return new object[] { "list", items, line };
    }
    object MapLiteral(int line)
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
        return new object[] { "map", pairs, line };
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
        while (i < source.Length)
        {
            char ch = source[i];
            if (ch == ' ' || ch == '\t' || ch == '\r') { i++; continue; }
            if (ch == '\n') { line++; i++; continue; }
            if (ch == '~')
            {
                while (i < source.Length && source[i] != '\n') i++;
                continue;
            }
            if (ch == '"')
            {
                i++;
                StringBuilder chars = new StringBuilder();
                while (i < source.Length && source[i] != '"')
                {
                    if (source[i] == '\n') throw new VireError("string runs past the end of the line", line);
                    if (source[i] == '\\')
                    {
                        i++;
                        if (i >= source.Length) throw new VireError("broken escape in string", line);
                        char esc = source[i];
                        if (esc == 'n') chars.Append('\n');
                        else if (esc == 't') chars.Append('\t');
                        else if (esc == '"' || esc == '\\') chars.Append(esc);
                        else throw new VireError("unknown escape in string", line);
                    }
                    else chars.Append(source[i]);
                    i++;
                }
                if (i >= source.Length) throw new VireError("string is missing its closing quote", line);
                i++;
                tokens.Add(new Token("string", chars.ToString(), line));
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
                    tokens.Add(new Token("number", real, line));
                }
                else tokens.Add(new Token("number", int.Parse(source.Substring(start, i - start)), line));
                continue;
            }
            if (char.IsLetter(ch) || ch == '_')
            {
                int start = i;
                while (i < source.Length && (char.IsLetterOrDigit(source[i]) || source[i] == '_')) i++;
                string word = source.Substring(start, i - start);
                tokens.Add(new Token(Keywords.Contains(word) ? word : "name", word, line));
                continue;
            }
            if (i + 1 < source.Length)
            {
                string two = source.Substring(i, 2);
                if (two == "==" || two == "!=" || two == "<=" || two == ">=")
                {
                    tokens.Add(new Token(two, two, line));
                    i += 2;
                    continue;
                }
            }
            string one = ch.ToString();
            if ("+-*/%<>=(),[]{}:".IndexOf(ch) >= 0)
            {
                tokens.Add(new Token(one, one, line));
                i++;
                continue;
            }
            throw new VireError("unexpected character '" + one + "'", line);
        }
        tokens.Add(new Token("eof", null, line));
        return tokens;
    }
}

sealed class Json
{
    public static string Write(object value)
    {
        if (value == null) return "null";
        if (value is bool) return (bool)value ? "true" : "false";
        if (value is int) return value.ToString();
        if (value is double) return ((double)value).ToString(System.Globalization.CultureInfo.InvariantCulture);
        if (value is string) return "\"" + ((string)value).Replace("\\", "\\\\").Replace("\"", "\\\"") + "\"";
        if (value is List<object>)
        {
            List<string> parts = new List<string>();
            foreach (object item in (List<object>)value) parts.Add(Write(item));
            return "[" + string.Join(",", parts.ToArray()) + "]";
        }
        if (value is Dictionary<string, object>)
        {
            List<string> parts = new List<string>();
            foreach (KeyValuePair<string, object> pair in (Dictionary<string, object>)value)
                parts.Add(Write(pair.Key) + ":" + Write(pair.Value));
            return "{" + string.Join(",", parts.ToArray()) + "}";
        }
        return Write(Machine.Show(value));
    }

    public static object Read(string text, int line)
    {
        int i = 0;
        object value = ReadValue(text, ref i, line);
        Skip(text, ref i);
        if (i != text.Length) throw new VireError("json has extra text", line);
        return value;
    }

    static object ReadValue(string text, ref int i, int line)
    {
        Skip(text, ref i);
        if (i >= text.Length) throw new VireError("json ended early", line);
        char ch = text[i];
        if (ch == '"') return ReadString(text, ref i, line);
        if (ch == '{') return ReadMap(text, ref i, line);
        if (ch == '[') return ReadList(text, ref i, line);
        if (ch == 't' || ch == 'f' || ch == 'n') return ReadWord(text, ref i, line);
        return ReadNumber(text, ref i, line);
    }

    static Dictionary<string, object> ReadMap(string text, ref int i, int line)
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
            map[key] = ReadValue(text, ref i, line);
            Skip(text, ref i);
            if (i < text.Length && text[i] == ',') { i++; continue; }
            if (i < text.Length && text[i] == '}') { i++; return map; }
            break;
        }
        throw new VireError("json map is unfinished", line);
    }

    static List<object> ReadList(string text, ref int i, int line)
    {
        i++;
        List<object> list = new List<object>();
        Skip(text, ref i);
        if (i < text.Length && text[i] == ']') { i++; return list; }
        while (i < text.Length)
        {
            if (list.Count > 100000) throw new VireError("json is too large", line);
            list.Add(ReadValue(text, ref i, line));
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
                else if (esc == 'n') chars.Append('\n');
                else if (esc == 't') chars.Append('\t');
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
        string raw = text.Substring(start, i - start);
        if (!frac)
        {
            int whole;
            if (int.TryParse(raw, out whole)) return whole;
        }
        double real;
        if (double.TryParse(raw, System.Globalization.NumberStyles.Float, System.Globalization.CultureInfo.InvariantCulture, out real))
            return real;
        throw new VireError("json has a bad number", line);
    }

    static void Skip(string text, ref int i)
    {
        while (i < text.Length && (text[i] == ' ' || text[i] == '\n' || text[i] == '\r' || text[i] == '\t')) i++;
    }
}

sealed class Program
{
    static Dictionary<string, Func> Load(string program, string folder, HashSet<string> seen)
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
        FileInfo info = new FileInfo(full);
        if (!info.Exists) throw new VireError("could not read " + Path.GetFileName(full), 1);
        if (info.Length > 1000000) throw new VireError("that file is too large to run", 1);
        Unit unit = new Parser(Lexer.Tokenize(File.ReadAllText(full))).Parse();
        foreach (string used in unit.Uses)
        {
            if (Path.IsPathRooted(used) || used.Contains("..") || !used.EndsWith(".vire", StringComparison.OrdinalIgnoreCase))
                throw new VireError("use stays inside the program folder and only opens .vire files", 1);
            string next = Path.GetFullPath(Path.Combine(folder, used));
            Dictionary<string, Func> imported = Load(next, folder, seen);
            Merge(unit, imported);
        }
        foreach (string package in unit.Needs)
        {
            if (!IsPackage(package))
                throw new VireError("package names are plain words", 1);
            string next = Path.Combine(folder, "deps", package, "lib.vire");
            Merge(unit, Load(next, folder, seen));
        }
        return unit.Funcs;
        }
        finally { seen.Remove(full); }
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
        if (args.Length != 1)
        {
            Console.Error.WriteLine("usage: vire program.vire");
            return 2;
        }
        try
        {
            string program = Path.GetFullPath(args[0]);
            string folder = Path.GetDirectoryName(program);
            Dictionary<string, Func> funcs = Load(program, folder, new HashSet<string>());
            if (!funcs.ContainsKey("main")) throw new VireError("a vire program needs define main", 1);
            new Machine(funcs, folder).Run();
            return 0;
        }
        catch (VireError exc)
        {
            string where = exc.Line > 0 ? "line " + exc.Line + ": " : "";
            Console.Error.WriteLine("vire: " + where + exc.Message);
            return 1;
        }
    }
}
