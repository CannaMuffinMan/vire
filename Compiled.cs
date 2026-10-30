using System;
using System.Collections.Generic;
using System.IO;
using System.Net.Http;
using System.Text;
using System.Threading;

sealed class CompiledProgram
{
    public static void Run(string file, string folder, List<object> args)
    {
        if (!file.EndsWith(".vc", StringComparison.OrdinalIgnoreCase))
            throw new VireError("compiled programs use a .vc file", 1);
        byte[] packed;
        try { packed = File.ReadAllBytes(file); }
        catch (IOException) { throw new VireError("could not read that file", 1); }
        catch (UnauthorizedAccessException) { throw new VireError("could not read that file", 1); }
        string text = Encoding.UTF8.GetString(VireSeal.OpenBytes(packed));
        object tree = Json.Read(text, 1);
        Dictionary<string, object> root = tree as Dictionary<string, object>;
        if (root == null || !root.ContainsKey("funcs")) throw new VireError("compiled file has no funcs", 1);
        Dictionary<string, object> funcs = new Dictionary<string, object>();
        foreach (object item in (List<object>)root["funcs"])
        {
            Dictionary<string, object> func = (Dictionary<string, object>)item;
            funcs[(string)func["name"]] = func;
        }
        Budget budget = new Budget();
        budget.ApplyStepLimit(Program.BudgetOf(""));
        CompiledMachine machine = new CompiledMachine(funcs, folder, args, budget);
        machine.Call("main", new List<object>(), 1, 1);
    }
}

sealed class CompiledMachine
{
    Dictionary<string, object> funcs;
    string root;
    List<object> programArgs;
    Budget budget;
    int depth;
    int exprDepth;
    string title;
    List<Stroke> termOps = new List<Stroke>();
    bool termSheet;
    int inkR;
    int inkG;
    int inkB;
    List<string> termLines = new List<string>();
    List<string> termFields = new List<string>();
    Dictionary<string, string> termValues = new Dictionary<string, string>();
    List<string> termButtons = new List<string>();
    List<string> termActions = new List<string>();
    string watchName;
    int watchLine;
    int nextTop = 16;
    int nextLeft = 16;
    internal int ListenPort;
    const int MaxItems = 100000;
    const int MaxText = 1000000;

    public CompiledMachine(Dictionary<string, object> funcs, string root, List<object> args, Budget budget)
    {
        this.funcs = funcs;
        this.root = root;
        programArgs = args;
        this.budget = budget;
    }

    public object Call(string name, List<object> args)
    {
        return Call(name, args, 1, 1);
    }

    internal void ListenCore(int port, int line, CancellationToken stop)
    {
        if (!funcs.ContainsKey("route")) throw new VireError("listen needs define route with method, path, body", line);
        VireListen.Run(port, line, stop, root, DispatchRoute, Show, p => ListenPort = p);
    }

    public object Call(string name, List<object> args, int line, int col)
    {
        if (!funcs.ContainsKey(name)) return Builtin(name, args, line, col);
        Dictionary<string, object> func = (Dictionary<string, object>)funcs[name];
        List<object> names = (List<object>)func["params"];
        if (names.Count != args.Count) throw new VireError(name + " argument count", 1, 1);
        Dictionary<string, object> env = new Dictionary<string, object>();
        for (int i = 0; i < names.Count; i++) env[(string)names[i]] = args[i];
        depth++;
        if (depth > 64) throw new VireError("definitions called too deeply", 1, 1);
        try
        {
            foreach (object step in (List<object>)func["body"])
            {
                object[] hit = Run((List<object>)step, env);
                if (hit != null)
                {
                    if (hit.Length > 1 && (string)hit[1] == "skip") throw new VireError("skip is only valid inside while or for", 1, 1);
                    if (hit.Length > 1 && (string)hit[1] == "stop") throw new VireError("stop is only valid inside while or for", 1, 1);
                    return hit[0];
                }
            }
            return null;
        }
        finally { depth--; }
    }

    object[] Run(List<object> step, Dictionary<string, object> env)
    {
        if (budget.DeadlinePassed()) Fail("request ran too long", step);
        budget.Steps++;
        if (budget.Steps > budget.MaxSteps) Fail("program ran too long and was stopped", step);
        string op = (string)step[0];
        if (op == "let") { env[(string)step[1]] = Eval((List<object>)step[2], env); return null; }
        if (op == "say") { Console.WriteLine(Show(Eval((List<object>)step[1], env))); return null; }
        if (op == "return") return new object[] { Eval((List<object>)step[1], env), "return" };
        if (op == "stop") return new object[] { null, "stop" };
        if (op == "skip") return new object[] { null, "skip" };
        if (op == "if")
        {
            if (Truth(Eval((List<object>)step[1], env))) return Block((List<object>)step[2], env);
            if (step.Count > 3 && step[3] is List<object>) return Block((List<object>)step[3], env);
            return null;
        }
        if (op == "while")
        {
            while (Truth(Eval((List<object>)step[1], env)))
            {
                budget.WhilePasses++;
                if (budget.WhilePasses > budget.MaxWhilePasses) Fail("while ran too long", step);
                object[] hit = Block((List<object>)step[2], env);
                if (hit != null && hit.Length > 1 && (string)hit[1] == "skip") continue;
                if (hit != null && hit.Length > 1 && (string)hit[1] == "stop") break;
                if (hit != null) return hit;
            }
            return null;
        }
        if (op == "for")
        {
            object values = Eval((List<object>)step[2], env);
            List<object> items = new List<object>();
            if (values is Dictionary<string, object>) items = new List<object>(((Dictionary<string, object>)values).Keys);
            else if (values is string)
            {
                foreach (char ch in (string)values) items.Add(ch.ToString());
            }
            else if (values is List<object>) items = (List<object>)values;
            else Fail("for walks a list, map, or text", step);
            foreach (object item in items)
            {
                env[(string)step[1]] = item;
                object[] hit = Block((List<object>)step[3], env);
                if (hit != null && hit.Length > 1 && (string)hit[1] == "skip") continue;
                if (hit != null && hit.Length > 1 && (string)hit[1] == "stop") break;
                if (hit != null) return hit;
            }
            return null;
        }
        if (op == "try")
        {
            try { return Block((List<object>)step[1], env); }
            catch (VireError exc)
            {
                if (step.Count < 4 || step[3] == null || !(step[3] is List<object>)) throw;
                if (step[2] != null) env[Show(step[2])] = exc.Message;
                return Block((List<object>)step[3], env);
            }
        }
        if (op == "call")
        {
            Call((string)step[1], Values((List<object>)step[2], env), AsLine(step), AsCol(step));
            return null;
        }
        if (op == "put")
        {
            object target;
            if (!env.TryGetValue((string)step[2], out target)) Fail("put needs a list or a map", step);
            object key = Eval((List<object>)step[3], env);
            object stored = Eval((List<object>)step[1], env);
            Put(target, key, stored, AsLine(step), AsCol(step));
            return null;
        }
        Fail("unknown compiled step " + op, step);
        return null;
    }

    static bool IsWholeNum(object value)
    {
        if (value is int) return true;
        if (value is double)
        {
            double real = (double)value;
            return !double.IsNaN(real) && !double.IsInfinity(real) && real == Math.Floor(real);
        }
        return false;
    }

    static int AsLine(List<object> node)
    {
        if (node == null || node.Count < 2) return 1;
        object prev = node[node.Count - 2];
        object last = node[node.Count - 1];
        if (IsWholeNum(prev) && IsWholeNum(last)) return Convert.ToInt32(prev);
        if (IsWholeNum(last)) return Convert.ToInt32(last);
        return 1;
    }

    static int AsCol(List<object> node)
    {
        if (node == null || node.Count < 2) return 1;
        object prev = node[node.Count - 2];
        object last = node[node.Count - 1];
        if (IsWholeNum(prev) && IsWholeNum(last)) return Convert.ToInt32(last);
        return 1;
    }

    static void Fail(string message, List<object> node)
    {
        throw new VireError(message, AsLine(node), AsCol(node));
    }

    object[] Block(List<object> steps, Dictionary<string, object> env)
    {
        foreach (object step in steps)
        {
            object[] hit = Run((List<object>)step, env);
            if (hit != null) return hit;
        }
        return null;
    }

    List<object> Values(List<object> exprs, Dictionary<string, object> env)
    {
        List<object> values = new List<object>();
        foreach (object expr in exprs) values.Add(Eval((List<object>)expr, env));
        return values;
    }

    object Eval(List<object> expr, Dictionary<string, object> env)
    {
        exprDepth++;
        try
        {
        if (exprDepth > 256) Fail("expression is too deep", expr);
        string op = (string)expr[0];
        if (op == "num") return expr[1];
        if (op == "text") return expr[1];
        if (op == "bool") return expr[1];
        if (op == "none") return null;
        if (op == "name")
        {
            string called = (string)expr[1];
            object found;
            if (env.TryGetValue(called, out found)) return found;
            if (called == "args" || called == "now" || called == "term" || called == "screen" || called == "show" || called == "marks" || called == "clear")
                return Builtin(called, new List<object>(), AsLine(expr), AsCol(expr));
            if (funcs.ContainsKey(called))
            {
                Dictionary<string, object> named = (Dictionary<string, object>)funcs[called];
                List<object> names = (List<object>)named["params"];
                if (names.Count == 0) return Call(called, new List<object>(), AsLine(expr), AsCol(expr));
            }
            Fail(called + " has no value", expr);
        }
        if (op == "list") return Values((List<object>)expr[1], env);
        if (op == "call") return Call((string)expr[1], Values((List<object>)expr[2], env), AsLine(expr), AsCol(expr));
        if (op == "at") return At(Eval((List<object>)expr[1], env), Eval((List<object>)expr[2], env), expr);
        if (op == "not") return !Truth(Eval((List<object>)expr[1], env));
        if (op == "neg")
        {
            object value = Eval((List<object>)expr[1], env);
            if (value is int)
            {
                int whole = (int)value;
                if (whole == int.MinValue) return -(double)whole;
                return -whole;
            }
            return -ToDouble(value);
        }
        if (op == "and")
        {
            if (!Truth(Eval((List<object>)expr[1], env))) return false;
            return Truth(Eval((List<object>)expr[2], env));
        }
        if (op == "or")
        {
            if (Truth(Eval((List<object>)expr[1], env))) return true;
            return Truth(Eval((List<object>)expr[2], env));
        }
        if (op == "map")
        {
            Dictionary<string, object> map = new Dictionary<string, object>();
            if (expr.Count < 2 || expr[1] == null) return map;
            foreach (object pair in (List<object>)expr[1])
            {
                List<object> item = (List<object>)pair;
                map[KeyOf(Eval((List<object>)item[0], env), expr)] = Eval((List<object>)item[1], env);
            }
            return map;
        }
        object left = Eval((List<object>)expr[1], env);
        object right = Eval((List<object>)expr[2], env);
        if (op == "+")
        {
            if (left is string || right is string) return Show(left) + Show(right);
            if (left is List<object> && right is List<object>)
            {
                List<object> joined = new List<object>((List<object>)left);
                joined.AddRange((List<object>)right);
                return joined;
            }
            return Add(left, right);
        }
        if (op == "-") return Sub(left, right);
        if (op == "*") return Mul(left, right);
        if (op == "/")
        {
            if (ToDouble(right) == 0) Fail("division by zero", expr);
            return ToDouble(left) / ToDouble(right);
        }
        if (op == "%")
        {
            if (ToDouble(right) == 0) Fail("division by zero", expr);
            if (left is int && right is int)
            {
                if ((int)right == -1) return 0;
                return ((int)left) % ((int)right);
            }
            return ToDouble(left) % ToDouble(right);
        }
        if (op == "==") return Same(left, right);
        if (op == "!=") return !Same(left, right);
        if (op == "<") return ToDouble(left) < ToDouble(right);
        if (op == "<=") return ToDouble(left) <= ToDouble(right);
        if (op == ">") return ToDouble(left) > ToDouble(right);
        if (op == ">=") return ToDouble(left) >= ToDouble(right);
        Fail("unknown compiled expression " + op, expr);
        return null;
        }
        finally { exprDepth--; }
    }

    object At(object target, object index, List<object> expr)
    {
        string text = target as string;
        if (text != null) return text.Substring(WholeIndex(index, text.Length, expr), 1);
        List<object> list = target as List<object>;
        if (list != null) return list[WholeIndex(index, list.Count, expr)];
        Dictionary<string, object> map = target as Dictionary<string, object>;
        if (map != null)
        {
            string key = KeyOf(index, expr);
            object found;
            if (!map.TryGetValue(key, out found)) Fail("map has no key " + key, expr);
            return found;
        }
        Fail("at needs a list, text, or map", expr);
        return null;
    }

    void Put(object target, object key, object value, int line, int col)
    {
        List<object> loc = new List<object> { "put", line, col };
        List<object> list = target as List<object>;
        if (list != null)
        {
            list[WholeIndex(key, list.Count, loc)] = value;
            return;
        }
        Dictionary<string, object> map = target as Dictionary<string, object>;
        if (map != null)
        {
            map[KeyOf(key, loc)] = value;
            return;
        }
        throw new VireError("put needs a list or a map", line, col);
    }

    static int AsWhole(object value)
    {
        if (value is int) return (int)value;
        if (value is double)
        {
            double real = (double)value;
            if (double.IsNaN(real) || double.IsInfinity(real) || real != Math.Floor(real))
                throw new VireError("slice bounds must be whole numbers", 1);
            if (real < int.MinValue || real > int.MaxValue) throw new VireError("slice bounds must be whole numbers", 1);
            return (int)real;
        }
        throw new VireError("slice bounds must be whole numbers", 1);
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

    static int WholeIndex(object value, int size, List<object> expr)
    {
        int index = 0;
        if (value is int) index = (int)value;
        else if (value is double)
        {
            double real = (double)value;
            if (double.IsNaN(real) || double.IsInfinity(real) || real != Math.Floor(real))
                Fail("an index must be a whole number", expr);
            if (real < int.MinValue || real > int.MaxValue) Fail("an index must be a whole number", expr);
            index = (int)real;
        }
        else Fail("an index must be a whole number", expr);
        if (index < 0) index += size;
        if (index < 0 || index >= size) Fail("index is outside the value", expr);
        return index;
    }

    static string KeyOf(object value, List<object> expr)
    {
        if (value is int) return value.ToString();
        if (value is double)
        {
            double real = (double)value;
            if (double.IsNaN(real) || double.IsInfinity(real)) Fail("map keys must be text or numbers", expr);
            if (real == Math.Floor(real)) return ((long)real).ToString(System.Globalization.CultureInfo.InvariantCulture);
            return real.ToString(System.Globalization.CultureInfo.InvariantCulture);
        }
        string text = value as string;
        if (text != null) return text;
        Fail("map keys must be text or numbers", expr);
        return "";
    }

    object Builtin(string name, List<object> args, int line, int col)
    {
        if (VireCrypto.IsName(name)) return VireCrypto.Builtin(name, args, line, col);
        if (name == "args") return programArgs;
        if (name == "now") return DateTime.Now.ToString("yyyy-MM-dd HH:mm:ss");
        if (name == "halt")
        {
            int code = 1;
            if (args.Count > 0 && args[0] is int) code = (int)args[0];
            else if (args.Count > 0 && args[0] is double) code = (int)(double)args[0];
            throw new HaltSignal(code);
        }
        if (name == "length")
        {
            if (args[0] is string) return ((string)args[0]).Length;
            if (args[0] is List<object>) return ((List<object>)args[0]).Count;
            Dictionary<string, object> map = args[0] as Dictionary<string, object>;
            if (map != null) return map.Count;
            throw new VireError("length needs text, a list, or a map", line, col);
        }
        if (name == "push")
        {
            List<object> list = args[0] as List<object>;
            if (list == null) throw new VireError("push needs a list", line, col);
            if (list.Count >= MaxItems) throw new VireError("list is too large", line, col);
            list.Add(args[1]);
            return args[0];
        }
        if (name == "text") return Show(args[0]);
        if (name == "number")
        {
            if (args[0] is int || args[0] is double) return args[0];
            string raw = args[0] as string;
            if (raw == null) throw new VireError("number needs text or a number", line, col);
            int whole;
            double real;
            if (raw.IndexOf('.') < 0 && int.TryParse(raw, out whole)) return whole;
            if (double.TryParse(raw, System.Globalization.NumberStyles.Float, System.Globalization.CultureInfo.InvariantCulture, out real))
                return real;
            throw new VireError("that text is not a number", line, col);
        }
        if (name == "slice")
        {
            int start = AsWhole(args[1]);
            int end = AsWhole(args[2]);
            string text = args[0] as string;
            if (text != null) return SliceText(text, start, end);
            List<object> list = args[0] as List<object>;
            if (list == null) throw new VireError("slice needs text or a list", line, col);
            return SliceList(list, start, end);
        }
        if (name == "find")
        {
            string raw = args[0] as string;
            string needle = args[1] as string;
            if (raw == null || needle == null) throw new VireError("find needs two texts", line, col);
            return raw.IndexOf(needle);
        }
        if (name == "json") return Json.Write(args[0]);
        if (name == "seal") return VireSeal.Seal(args[0] as string ?? Show(args[0]));
        if (name == "hash") return VireSeal.HashText(args[0] as string ?? Show(args[0]));
        if (name == "read")
        {
            try
            {
                string text = File.ReadAllText(Safe(args[0], line, col));
                if (text.Length > MaxText) throw new VireError("file is too large", line, col);
                return text;
            }
            catch (VireError) { throw; }
            catch (IOException) { throw new VireError("could not read that file", line, col); }
            catch (UnauthorizedAccessException) { throw new VireError("could not read that file", line, col); }
        }
        if (name == "write")
        {
            string path = Safe(args[0], line, col);
            VirePaths.RefuseProgram(root, path, line, col);
            string payload = Show(args[1]);
            if (payload.Length > MaxText) throw new VireError("text is too large to write", line, col);
            try
            {
                string parent = Path.GetDirectoryName(path);
                if (parent != null && parent.Length > 0) Directory.CreateDirectory(parent);
                if (VirePaths.NormalizedExtension(path) == ".vc") VireSeal.WritePacked(path, payload);
                else VireFiles.WriteAllText(path, payload);
            }
            catch (IOException) { throw new VireError("could not write that file", line, col); }
            catch (UnauthorizedAccessException) { throw new VireError("could not write that file", line, col); }
            return payload;
        }
        if (name == "has")
        {
            Dictionary<string, object> map = args[0] as Dictionary<string, object>;
            if (map == null) throw new VireError("has needs a map", line, col);
            return map.ContainsKey(KeyOf(args[1], new List<object> { "has", line, col }));
        }
        if (name == "parse")
        {
            if (args.Count != 1 && args.Count != 2)
                throw new VireError("parse takes 1 or 2 values, got " + args.Count, line, col);
            string raw = args[0] as string;
            if (raw == null) throw new VireError("parse needs text", line, col);
            object value = Json.Read(raw, line);
            if (args.Count == 2) Json.Check(value, args[1], line);
            return value;
        }
        if (name == "kind")
        {
            if (args[0] is bool) return "bool";
            if (args[0] == null) return "none";
            if (args[0] is int || args[0] is double) return "number";
            if (args[0] is string) return "text";
            if (args[0] is List<object>) return "list";
            if (args[0] is Dictionary<string, object>) return "map";
            return "value";
        }
        if (name == "join")
        {
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
        if (name == "escape")
        {
            string raw = args[0] as string;
            if (raw == null) raw = Show(args[0]);
            return raw.Replace("&", "&amp;").Replace("<", "&lt;").Replace(">", "&gt;").Replace("\"", "&quot;");
        }
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
        if (name == "keys")
        {
            Dictionary<string, object> map = args[0] as Dictionary<string, object>;
            if (map == null) throw new VireError("keys needs a map", line, col);
            return new List<object>(map.Keys);
        }
        if (name == "abs")
        {
            if (!(args[0] is int) && !(args[0] is double)) throw new VireError("abs needs a number", line, col);
            if (args[0] is int)
            {
                int n = (int)args[0];
                if (n == int.MinValue) return -(double)n;
                return n < 0 ? -n : n;
            }
            double real = (double)args[0];
            return real < 0 ? -real : real;
        }
        if (name == "round")
        {
            if (!(args[0] is int) && !(args[0] is double)) throw new VireError("round needs a number", line, col);
            double real = args[0] is int ? (int)args[0] : (double)args[0];
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
        if (name == "exists")
        {
            string path = Safe(args[0], line, col);
            return File.Exists(path) || Directory.Exists(path);
        }
        if (name == "erase")
        {
            string path = Safe(args[0], line, col);
            VirePaths.RefuseProgram(root, path, line, col);
            VireFiles.Erase(path);
            return true;
        }
        if (name == "copy")
        {
            string from = Safe(args[0], line, col);
            string to = Safe(args[1], line, col);
            VirePaths.RefuseProgram(root, to, line, col);
            try { VireFiles.Copy(from, to); }
            catch (IOException) { throw new VireError("could not write that file", line, col); }
            catch (UnauthorizedAccessException) { throw new VireError("could not write that file", line, col); }
            return args[1];
        }
        if (name == "append")
        {
            string path = Safe(args[0], line, col);
            VirePaths.RefuseProgram(root, path, line, col);
            string text = Show(args[1]);
            if (text.Length > MaxText) throw new VireError("text is too large to write", line, col);
            try { VireFiles.AppendAllText(path, text); }
            catch (IOException) { throw new VireError("could not write that file", line, col); }
            catch (UnauthorizedAccessException) { throw new VireError("could not write that file", line, col); }
            return text;
        }
        if (name == "fetch")
        {
            string url = args[0] as string;
            if (url == null || !(url.StartsWith("https://") || url.StartsWith("http://")))
                throw new VireError("fetch needs an http or https address", line, col);
            try { return VireNet.SendWeb(HttpMethod.Get, url, null, line, col); }
            catch (VireError) { throw; }
            catch (Exception) { throw new VireError("could not fetch that address", line, col); }
        }
        if (name == "run")
        {
            string rel = args[0] as string;
            string full = VirePaths.ProgramFile(root, rel, line, col);
            budget.Runs++;
            System.IO.StringWriter sink = new System.IO.StringWriter();
            System.IO.TextWriter previous = Console.Out;
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
        if (name == "term")
        {
            return "term";
        }
        if (name == "open")
        {
            string heading = args[0] as string;
            if (heading == null) throw new VireError("open needs a window title", line, col);
            title = heading;
            termOps = new List<Stroke>();
            termSheet = false;
            return 0;
        }
        if (name == "sheet")
        {
            if (!(args[0] is int) || !(args[1] is int)) throw new VireError("sheet needs a width and a height", line, col);
            if (title == null) throw new VireError("open a window first", line, col);
            int width = (int)args[0];
            int height = (int)args[1];
            if (width < 1 || height < 1 || width > 2000 || height > 2000) throw new VireError("sheet size is out of range", line, col);
            termSheet = true;
            return 0;
        }
        if (name == "ink")
        {
            if (!(args[0] is int) || !(args[1] is int) || !(args[2] is int))
                throw new VireError("ink needs three whole numbers", line, col);
            int rr = (int)args[0];
            int gg = (int)args[1];
            int bb = (int)args[2];
            if (rr < 0 || rr > 255 || gg < 0 || gg > 255 || bb < 0 || bb > 255)
                throw new VireError("ink numbers run from 0 to 255", line, col);
            inkR = rr; inkG = gg; inkB = bb;
            return 0;
        }
        if (name == "fill" || name == "stroke")
        {
            if (!(args[0] is int) || !(args[1] is int) || !(args[2] is int) || !(args[3] is int))
                throw new VireError(name + " needs four whole numbers", line, col);
            if (!termSheet) throw new VireError("open a sheet first", line, col);
            if (termOps.Count > 10000) throw new VireError("the sheet has too many marks", line, col);
            termOps.Add(new Stroke(name, (int)args[0], (int)args[1], (int)args[2], (int)args[3], inkR, inkG, inkB));
            return 0;
        }
        if (name == "dot")
        {
            if (!(args[0] is int) || !(args[1] is int) || !(args[2] is int)) throw new VireError("dot needs three whole numbers", line, col);
            if (!termSheet) throw new VireError("open a sheet first", line, col);
            termOps.Add(new Stroke("dot", (int)args[0], (int)args[1], (int)args[2], 0, inkR, inkG, inkB));
            return 0;
        }
        if (name == "marks")
        {
            List<object> list = new List<object>();
            foreach (Stroke mark in termOps)
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
        if (name == "ask")
        {
            if (!(args[0] is string)) throw new VireError("ask needs text", line, col);
            Console.Write((string)args[0]);
            return Console.ReadLine() ?? "";
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
        if (name == "post")
        {
            string postUrl = args[0] as string;
            if (postUrl == null || !(postUrl.StartsWith("https://") || postUrl.StartsWith("http://")))
                throw new VireError("post needs an http or https address", line, col);
            try
            {
                string payload = Show(args[1]);
                if (payload.Length > 1000000) throw new VireError("text is too large to send", line, col);
                return VireNet.SendWeb(HttpMethod.Post, postUrl, payload, line, col);
            }
            catch (VireError) { throw; }
            catch (Exception) { throw new VireError("could not post to that address", line, col); }
        }
        if (name == "files")
        {
            string path = Safe(args[0], line, col);
            if (!Directory.Exists(path)) throw new VireError("there is no folder by that name", line, col);
            List<object> names = new List<object>();
            foreach (string file in Directory.GetFiles(path)) names.Add(Path.GetFileName(file));
            return names;
        }
        if (name == "folders")
        {
            string path = Safe(args[0], line, col);
            if (!Directory.Exists(path)) throw new VireError("there is no folder by that name", line, col);
            List<object> names = new List<object>();
            foreach (string dir in Directory.GetDirectories(path)) names.Add(Path.GetFileName(dir));
            return names;
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
        if (name == "listen")
        {
            if (!funcs.ContainsKey("route")) throw new VireError("listen needs define route with method, path, body", line, col);
            int port = Machine.RequirePort(args[0], line);
            VireListen.WithCancel(port, line, root, DispatchRoute, Show, p => ListenPort = p);
            return null;
        }
        if (name == "line")
        {
            string text = args[0] as string;
            if (text == null) text = Show(args[0]);
            if (title == null) throw new VireError("open a window first", line, col);
            termLines.Add(text);
            return 0;
        }
        if (name == "field")
        {
            string fieldName = args[0] as string;
            if (fieldName == null) throw new VireError("field needs a name", line, col);
            if (title == null) throw new VireError("open a window first", line, col);
            termFields.Add(fieldName);
            termValues[fieldName] = "";
            return 0;
        }
        if (name == "button")
        {
            string label = args[0] as string;
            string func = args[1] as string;
            if (label == null || func == null) throw new VireError("button needs a label and a definition name", line, col);
            if (title == null) throw new VireError("open a window first", line, col);
            if (!funcs.ContainsKey(func)) throw new VireError("there is no definition named " + func, line, col);
            termButtons.Add(label);
            termActions.Add(func);
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
            if (args.Count < 5 || !(args[0] is int) || !(args[1] is int) || !(args[2] is int) || !(args[3] is int))
                throw new VireError("mark needs four whole numbers and a definition name", line, col);
            string func = args[4] as string;
            if (func == null) throw new VireError("mark needs four whole numbers and a definition name", line, col);
            if (title == null) throw new VireError("open a window first", line, col);
            if (!funcs.ContainsKey(func)) throw new VireError("there is no definition named " + func, line, col);
            termButtons.Add("mark");
            termActions.Add(func);
            return 0;
        }
        if (name == "watch")
        {
            string func = args[0] as string;
            if (func == null || !funcs.ContainsKey(func)) throw new VireError("watch needs a definition name", line, col);
            if (!termSheet) throw new VireError("open a sheet first", line, col);
            watchName = func;
            watchLine = line;
            return 0;
        }
        if (name == "value")
        {
            string fieldName = args[0] as string;
            if (fieldName == null || !termValues.ContainsKey(fieldName))
                throw new VireError("there is no field by that name", line, col);
            return termValues[fieldName];
        }
        if (name == "show")
        {
            if (title == null) throw new VireError("open a window before show", line, col);
            TermShow();
            return 0;
        }
        if (name == "screen") return string.Join("\n", termLines.ToArray());
        if (name == "clear")
        {
            termOps.Clear();
            return 0;
        }
        if (name == "serve")
            throw new VireError("serve was removed; use listen", line, col);
        throw new VireError("compiled builtin missing: " + name, line, col);
    }

    object DispatchRoute(string method, string path, string body, int line, out int maxOutput)
    {
        CompiledMachine worker = new CompiledMachine(funcs, root, programArgs, Budget.ForRequest(budget));
        maxOutput = worker.budget.MaxOutput;
        List<object> call = new List<object>();
        call.Add(method);
        call.Add(path);
        call.Add(body);
        object result = worker.Call("route", call, line, 1);
        string text = result as string;
        if (text == null) text = Show(result);
        if (text == null) text = "null";
        worker.budget.Output = text.Length;
        return result;
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
                try { Call(termActions[pick - 1], new List<object>(), watchLine, 1); }
                catch (VireError exc) { Console.WriteLine(exc.Message); }
                continue;
            }
            string[] bits = choice.Split(' ');
            int x, y;
            if (termSheet && bits.Length == 2 && int.TryParse(bits[0], out x) && int.TryParse(bits[1], out y))
                HitSheet(x, y);
        }
    }

    void HitSheet(int x, int y)
    {
        if (watchName == null) return;
        Dictionary<string, object> named = (Dictionary<string, object>)funcs[watchName];
        List<object> names = (List<object>)named["params"];
        List<object> args = new List<object>();
        if (names.Count >= 1) args.Add(x);
        if (names.Count >= 2) args.Add(y);
        try { Call(watchName, args, watchLine, 1); }
        catch (VireError exc) { Console.WriteLine(exc.Message); }
    }

    static bool Same(object left, object right)
    {
        if (left == null || right == null) return left == null && right == null;
        if (IsNum(left) && IsNum(right)) return ToDouble(left) == ToDouble(right);
        return left.Equals(right);
    }

    static bool IsNum(object value) { return value is int || value is double; }

    static bool Truth(object value)
    {
        if (value == null) return false;
        if (value is bool) return (bool)value;
        if (value is int) return (int)value != 0;
        if (value is double) return (double)value != 0 && !double.IsNaN((double)value);
        if (value is string) return ((string)value).Length != 0;
        if (value is List<object>) return ((List<object>)value).Count != 0;
        if (value is Dictionary<string, object>) return ((Dictionary<string, object>)value).Count != 0;
        return true;
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
        if (value is double) return (double)value;
        throw new VireError("that value is not a number", 1);
    }

    string Safe(object value, int line, int col)
    {
        string rel = value as string;
        if (rel == null || rel.Length == 0)
            throw new VireError("files stay inside the program folder", line, col);
        string full = VirePaths.CombineUnder(root, rel, line, col);
        if (!VirePaths.UnderWritableZone(root, full) && !RootIsDataOrSite())
            throw new VireError("files stay in data or site", line, col);
        if (RootIsDataOrSite() && !VirePaths.InFolder(root, full))
            throw new VireError("files stay in data or site", line, col);
        return full;
    }

    bool RootIsDataOrSite()
    {
        string full = Path.GetFullPath(root);
        string name = Path.GetFileName(full.TrimEnd(Path.DirectorySeparatorChar, Path.AltDirectorySeparatorChar));
        return name.Equals("data", StringComparison.OrdinalIgnoreCase) ||
            name.Equals("site", StringComparison.OrdinalIgnoreCase);
    }

    static string Show(object value)
    {
        return Machine.Show(value);
    }
}
