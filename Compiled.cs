using System;
using System.Collections.Generic;
using System.IO;
using System.Text;

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
        machine.Call("main", new List<object>());
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

    public CompiledMachine(Dictionary<string, object> funcs, string root, List<object> args, Budget budget)
    {
        this.funcs = funcs;
        this.root = root;
        programArgs = args;
        this.budget = budget;
    }

    public object Call(string name, List<object> args)
    {
        if (!funcs.ContainsKey(name)) return Builtin(name, args);
        Dictionary<string, object> func = (Dictionary<string, object>)funcs[name];
        List<object> names = (List<object>)func["params"];
        if (names.Count != args.Count) throw new VireError(name + " argument count", 1);
        Dictionary<string, object> env = new Dictionary<string, object>();
        for (int i = 0; i < names.Count; i++) env[(string)names[i]] = args[i];
        depth++;
        if (depth > 64) throw new VireError("definitions called too deeply", 1);
        try
        {
            foreach (object step in (List<object>)func["body"])
            {
                object[] hit = Run((List<object>)step, env);
                if (hit != null)
                {
                    if (hit.Length > 1 && (string)hit[1] == "stop") throw new VireError("stop is outside a loop", 1);
                    return hit[0];
                }
            }
            return null;
        }
        finally { depth--; }
    }

    object[] Run(List<object> step, Dictionary<string, object> env)
    {
        budget.Steps++;
        if (budget.Steps > budget.MaxSteps) throw new VireError("program ran too long and was stopped", 1);
        string op = (string)step[0];
        if (op == "let") { env[(string)step[1]] = Eval((List<object>)step[2], env); return null; }
        if (op == "say") { Console.WriteLine(Show(Eval((List<object>)step[1], env))); return null; }
        if (op == "return") return new object[] { Eval((List<object>)step[1], env), "return" };
        if (op == "stop") return new object[] { null, "stop" };
        if (op == "if")
        {
            if (Truth(Eval((List<object>)step[1], env))) return Block((List<object>)step[2], env);
            if (step.Count > 3 && step[3] != null) return Block((List<object>)step[3], env);
            return null;
        }
        if (op == "while")
        {
            while (Truth(Eval((List<object>)step[1], env)))
            {
                budget.WhilePasses++;
                if (budget.WhilePasses > budget.MaxWhilePasses) throw new VireError("while ran too long", 1);
                object[] hit = Block((List<object>)step[2], env);
                if (hit != null && hit.Length > 1 && (string)hit[1] == "stop") break;
                if (hit != null) return hit;
            }
            return null;
        }
        if (op == "call")
        {
            Call((string)step[1], Values((List<object>)step[2], env));
            return null;
        }
        if (op == "put")
        {
            object target;
            if (!env.TryGetValue((string)step[2], out target)) throw new VireError("put needs a list or a map", 1);
            object key = Eval((List<object>)step[3], env);
            object stored = Eval((List<object>)step[1], env);
            Put(target, key, stored);
            return null;
        }
        throw new VireError("unknown compiled step " + op, 1);
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
        if (exprDepth > 256) throw new VireError("expression is too deep", 1);
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
            if (called == "args" || called == "now") return Builtin(called, new List<object>());
            if (funcs.ContainsKey(called))
            {
                Dictionary<string, object> named = (Dictionary<string, object>)funcs[called];
                List<object> names = (List<object>)named["params"];
                if (names.Count == 0) return Call(called, new List<object>());
            }
            throw new VireError("there is no value named " + called, 1);
        }
        if (op == "list") return Values((List<object>)expr[1], env);
        if (op == "call") return Call((string)expr[1], Values((List<object>)expr[2], env));
        if (op == "at") return At(Eval((List<object>)expr[1], env), Eval((List<object>)expr[2], env));
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
                map[KeyOf(Eval((List<object>)item[0], env))] = Eval((List<object>)item[1], env);
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
            if (ToDouble(right) == 0) throw new VireError("division by zero", 1);
            return ToDouble(left) / ToDouble(right);
        }
        if (op == "%")
        {
            if (ToDouble(right) == 0) throw new VireError("division by zero", 1);
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
        throw new VireError("unknown compiled expression " + op, 1);
        }
        finally { exprDepth--; }
    }

    object At(object target, object index)
    {
        string text = target as string;
        if (text != null) return text.Substring(WholeIndex(index, text.Length), 1);
        List<object> list = target as List<object>;
        if (list != null) return list[WholeIndex(index, list.Count)];
        Dictionary<string, object> map = target as Dictionary<string, object>;
        if (map != null)
        {
            string key = KeyOf(index);
            object found;
            if (!map.TryGetValue(key, out found)) throw new VireError("map has no key " + key, 1);
            return found;
        }
        throw new VireError("at needs a list, text, or map", 1);
    }

    void Put(object target, object key, object value)
    {
        List<object> list = target as List<object>;
        if (list != null)
        {
            list[WholeIndex(key, list.Count)] = value;
            return;
        }
        Dictionary<string, object> map = target as Dictionary<string, object>;
        if (map != null)
        {
            map[KeyOf(key)] = value;
            return;
        }
        throw new VireError("put needs a list or a map", 1);
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

    static int WholeIndex(object value, int size)
    {
        int index;
        if (value is int) index = (int)value;
        else if (value is double)
        {
            double real = (double)value;
            if (double.IsNaN(real) || double.IsInfinity(real) || real != Math.Floor(real))
                throw new VireError("an index must be a whole number", 1);
            if (real < int.MinValue || real > int.MaxValue) throw new VireError("an index must be a whole number", 1);
            index = (int)real;
        }
        else throw new VireError("an index must be a whole number", 1);
        if (index < 0) index += size;
        if (index < 0 || index >= size) throw new VireError("index is outside the value", 1);
        return index;
    }

    static string KeyOf(object value)
    {
        if (value is int) return value.ToString();
        if (value is double)
        {
            double real = (double)value;
            if (double.IsNaN(real) || double.IsInfinity(real)) throw new VireError("map keys must be text or numbers", 1);
            if (real == Math.Floor(real)) return ((long)real).ToString(System.Globalization.CultureInfo.InvariantCulture);
            return real.ToString(System.Globalization.CultureInfo.InvariantCulture);
        }
        string text = value as string;
        if (text != null) return text;
        throw new VireError("map keys must be text or numbers", 1);
    }

    object Builtin(string name, List<object> args)
    {
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
            throw new VireError("length needs text, a list, or a map", 1);
        }
        if (name == "push")
        {
            List<object> list = args[0] as List<object>;
            if (list == null) throw new VireError("push needs a list", 1);
            list.Add(args[1]);
            return args[0];
        }
        if (name == "text") return Show(args[0]);
        if (name == "number")
        {
            if (args[0] is int || args[0] is double) return args[0];
            string raw = args[0] as string;
            if (raw == null) throw new VireError("number needs text or a number", 1);
            int whole;
            double real;
            if (raw.IndexOf('.') < 0 && int.TryParse(raw, out whole)) return whole;
            if (double.TryParse(raw, System.Globalization.NumberStyles.Float, System.Globalization.CultureInfo.InvariantCulture, out real))
                return real;
            throw new VireError("that text is not a number", 1);
        }
        if (name == "slice")
        {
            int start = AsWhole(args[1]);
            int end = AsWhole(args[2]);
            string text = args[0] as string;
            if (text != null) return SliceText(text, start, end);
            List<object> list = args[0] as List<object>;
            if (list == null) throw new VireError("slice needs text or a list", 1);
            return SliceList(list, start, end);
        }
        if (name == "find")
        {
            string raw = args[0] as string;
            string needle = args[1] as string;
            if (raw == null || needle == null) throw new VireError("find needs two texts", 1);
            return raw.IndexOf(needle);
        }
        if (name == "json") return Json.Write(args[0]);
        if (name == "seal") return VireSeal.Seal(args[0] as string ?? Show(args[0]));
        if (name == "hash") return VireSeal.HashText(args[0] as string ?? Show(args[0]));
        if (name == "read")
        {
            try { return File.ReadAllText(Safe(args[0])); }
            catch (VireError) { throw; }
            catch (IOException) { throw new VireError("could not read that file", 1); }
            catch (UnauthorizedAccessException) { throw new VireError("could not read that file", 1); }
        }
        if (name == "write")
        {
            string path = Safe(args[0]);
            RefuseProgram(path);
            string payload = Show(args[1]);
            try
            {
                string parent = Path.GetDirectoryName(path);
                if (parent != null && parent.Length > 0) Directory.CreateDirectory(parent);
                if (VirePaths.NormalizedExtension(path) == ".vc") VireSeal.WritePacked(path, payload);
                else File.WriteAllText(path, payload);
            }
            catch (IOException) { throw new VireError("could not write that file", 1); }
            catch (UnauthorizedAccessException) { throw new VireError("could not write that file", 1); }
            return payload;
        }
        if (name == "has") return Has(args[0], args[1]);
        throw new VireError("compiled builtin missing: " + name, 1);
    }

    object Has(object target, object key)
    {
        Dictionary<string, object> map = target as Dictionary<string, object>;
        if (map != null) return map.ContainsKey(Show(key));
        List<object> pairs = target as List<object>;
        if (pairs != null)
        {
            foreach (object item in pairs)
            {
                List<object> pair = item as List<object>;
                if (pair != null && pair.Count >= 2 && Same(pair[0], key)) return true;
            }
            return false;
        }
        throw new VireError("has needs a map", 1);
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

    string Safe(object value)
    {
        string rel = value as string;
        if (rel == null || rel.Length == 0)
            throw new VireError("files stay inside the program folder", 1);
        string full = VirePaths.CombineUnder(root, rel, 1);
        if (!VirePaths.UnderWritableZone(root, full) && !RootIsDataOrSite())
            throw new VireError("files stay in data or site", 1);
        if (RootIsDataOrSite() && !VirePaths.InFolder(root, full))
            throw new VireError("files stay in data or site", 1);
        return full;
    }

    bool RootIsDataOrSite()
    {
        string full = Path.GetFullPath(root);
        string name = Path.GetFileName(full.TrimEnd(Path.DirectorySeparatorChar, Path.AltDirectorySeparatorChar));
        return name.Equals("data", StringComparison.OrdinalIgnoreCase) ||
            name.Equals("site", StringComparison.OrdinalIgnoreCase);
    }

    static void RefuseProgram(string path)
    {
        VirePaths.RefuseProgram(path, 1);
    }

    static string Show(object value)
    {
        return Machine.Show(value);
    }
}
