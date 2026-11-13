using System;
using System.Collections.Generic;

sealed class CapDecl
{
    public string Name;
    public string Arg;
    public string Label()
    {
        if (Arg == null || Arg.Length == 0) return Name;
        return Name + " " + Arg;
    }
}

static class VireCheck
{
    public const string Any = "any";

    static readonly HashSet<string> Types = new HashSet<string>(new string[] {
        "number", "text", "bool", "list", "map", "none", "any"
    });

    static readonly Dictionary<string, string> BuiltinCaps = Caps();
    static readonly Dictionary<string, string> BuiltinRet = Rets();

    static Dictionary<string, string> Caps()
    {
        Dictionary<string, string> map = new Dictionary<string, string>();
        map["now"] = "clock";
        map["ticks"] = "clock";
        map["listen"] = "net.listen";
        map["connect"] = "net.connect.loopback";
        map["send"] = "net.connect.loopback";
        map["recv"] = "net.connect.loopback";
        map["close"] = "net.connect.loopback";
        map["read"] = "fs.read";
        map["exists"] = "fs.read";
        map["files"] = "fs.read";
        map["folders"] = "fs.read";
        map["sources"] = "fs.read";
        map["write"] = "fs.write";
        map["erase"] = "fs.write";
        map["copy"] = "fs.write";
        map["append"] = "fs.write";
        return map;
    }

    static Dictionary<string, string> Rets()
    {
        Dictionary<string, string> map = new Dictionary<string, string>();
        map["length"] = "number";
        map["text"] = "text";
        map["number"] = "number";
        map["kind"] = "text";
        map["now"] = "text";
        map["ticks"] = "number";
        map["abs"] = "number";
        map["min"] = "number";
        map["max"] = "number";
        map["round"] = "number";
        map["lower"] = "text";
        map["upper"] = "text";
        map["join"] = "text";
        map["split"] = "list";
        map["find"] = "number";
        map["json"] = "text";
        map["read"] = "text";
        map["keys"] = "list";
        map["has"] = "bool";
        map["begins"] = "bool";
        map["ends"] = "bool";
        map["exists"] = "bool";
        map["files"] = "list";
        map["folders"] = "list";
        map["sources"] = "list";
        map["args"] = "list";
        map["bytes"] = "list";
        map["idiv"] = "number";
        map["shl8"] = "number";
        map["chr"] = "text";
        map["hex"] = "text";
        map["hash"] = "text";
        return map;
    }

    public static bool IsTypeName(string name)
    {
        return name != null && Types.Contains(name);
    }

    public static string KnownCap(string name)
    {
        if (name == "clock" || name == "net.listen" || name == "net.connect.loopback" || name == "fs.read" || name == "fs.write")
            return name;
        return null;
    }

    public static string NeedFor(string builtin)
    {
        string cap;
        if (BuiltinCaps.TryGetValue(builtin, out cap)) return cap;
        return null;
    }

    public static string FormatCaps(List<CapDecl> caps)
    {
        if (caps == null || caps.Count == 0) return "none";
        List<string> labels = new List<string>();
        HashSet<string> seen = new HashSet<string>();
        foreach (CapDecl cap in caps)
        {
            string label = cap.Label();
            if (seen.Add(label)) labels.Add(label);
        }
        labels.Sort(StringComparer.Ordinal);
        return string.Join(", ", labels.ToArray());
    }

    public static void Apply(Unit unit)
    {
        HashSet<string> allowed = new HashSet<string>();
        foreach (CapDecl cap in unit.Caps)
        {
            if (cap.Name == "fs.read" || cap.Name == "fs.write") allowed.Add(cap.Name);
            else allowed.Add(cap.Label());
        }
        Dictionary<string, Func> funcs = unit.Funcs;
        foreach (KeyValuePair<string, Func> pair in funcs)
            CheckFunc(pair.Value, funcs, allowed);
    }

    static void CheckFunc(Func func, Dictionary<string, Func> funcs, HashSet<string> allowed)
    {
        Dictionary<string, string> env = new Dictionary<string, string>();
        for (int i = 0; i < func.Params.Count; i++)
        {
            string ty = i < func.ParamTypes.Count ? func.ParamTypes[i] : "";
            if (ty == null || ty.Length == 0) ty = Any;
            env[func.Params[i]] = ty;
        }
        CheckBlock(func.Body, env, func, funcs, allowed);
    }

    static void CheckBlock(List<object> stmts, Dictionary<string, string> env, Func func, Dictionary<string, Func> funcs, HashSet<string> allowed)
    {
        if (stmts == null) return;
        foreach (object stmt in stmts) CheckStmt((object[])stmt, env, func, funcs, allowed);
    }

    static void CheckStmt(object[] stmt, Dictionary<string, string> env, Func func, Dictionary<string, Func> funcs, HashSet<string> allowed)
    {
        string kind = (string)stmt[0];
        int line = LineOf(stmt);
        int col = ColOf(stmt);
        if (kind == "let")
        {
            string name = (string)stmt[1];
            object expr = stmt[2];
            string want = "";
            if (stmt.Length >= 6) want = stmt[3] as string ?? "";
            string got = Infer(expr, env, funcs, allowed);
            if (want.Length > 0) Expect(want, got, name + " is " + want + ", got " + got, line, col);
            env[name] = want.Length > 0 ? want : Any;
            return;
        }
        if (kind == "put")
        {
            Infer(stmt[1], env, funcs, allowed);
            Infer(stmt[3], env, funcs, allowed);
            return;
        }
        if (kind == "say") { Infer(stmt[1], env, funcs, allowed); return; }
        if (kind == "return")
        {
            string got = Infer(stmt[1], env, funcs, allowed);
            if (func.ReturnType != null && func.ReturnType.Length > 0)
                Expect(func.ReturnType, got, "return is " + func.ReturnType + ", got " + got, line, col);
            return;
        }
        if (kind == "while")
        {
            Infer(stmt[1], env, funcs, allowed);
            CheckBlock((List<object>)stmt[2], env, func, funcs, allowed);
            return;
        }
        if (kind == "for")
        {
            Infer(stmt[2], env, funcs, allowed);
            Dictionary<string, string> inner = CopyEnv(env);
            inner[(string)stmt[1]] = Any;
            CheckBlock((List<object>)stmt[3], inner, func, funcs, allowed);
            return;
        }
        if (kind == "if")
        {
            Infer(stmt[1], env, funcs, allowed);
            CheckBlock((List<object>)stmt[2], env, func, funcs, allowed);
            if (stmt[3] != null) CheckBlock((List<object>)stmt[3], env, func, funcs, allowed);
            return;
        }
        if (kind == "try")
        {
            CheckBlock((List<object>)stmt[1], env, func, funcs, allowed);
            if (stmt[3] != null)
            {
                Dictionary<string, string> inner = CopyEnv(env);
                if (stmt[2] != null) inner[(string)stmt[2]] = "text";
                CheckBlock((List<object>)stmt[3], inner, func, funcs, allowed);
            }
            return;
        }
        if (kind == "call")
        {
            CheckCall((string)stmt[1], (List<object>)stmt[2], env, funcs, allowed, line, col);
            return;
        }
    }

    static void CheckCall(string name, List<object> args, Dictionary<string, string> env, Dictionary<string, Func> funcs, HashSet<string> allowed, int line, int col)
    {
        NeedCap(name, allowed, line, col);
        List<string> got = new List<string>();
        if (args != null)
        {
            foreach (object arg in args) got.Add(Infer(arg, env, funcs, allowed));
        }
        Func target;
        if (funcs.TryGetValue(name, out target))
        {
            for (int i = 0; i < target.Params.Count && i < got.Count; i++)
            {
                string want = i < target.ParamTypes.Count ? target.ParamTypes[i] : "";
                if (want == null || want.Length == 0) continue;
                Expect(want, got[i], name + " takes " + want + ", got " + got[i], line, col);
            }
        }
    }

    static string Infer(object node, Dictionary<string, string> env, Dictionary<string, Func> funcs, HashSet<string> allowed)
    {
        object[] tree = (object[])node;
        string kind = (string)tree[0];
        int line = LineOf(tree);
        int col = ColOf(tree);
        if (kind == "num") return "number";
        if (kind == "str") return "text";
        if (kind == "bool") return "bool";
        if (kind == "none") return "none";
        if (kind == "now")
        {
            NeedCap("now", allowed, line, col);
            return "text";
        }
        if (kind == "list")
        {
            foreach (object item in (List<object>)tree[1]) Infer(item, env, funcs, allowed);
            return "list";
        }
        if (kind == "map")
        {
            foreach (object[] pair in (List<object[]>)tree[1])
            {
                Infer(pair[0], env, funcs, allowed);
                Infer(pair[1], env, funcs, allowed);
            }
            return "map";
        }
        if (kind == "var")
        {
            string name = (string)tree[1];
            string ty;
            if (env.TryGetValue(name, out ty)) return ty;
            NeedCap(name, allowed, line, col);
            string ret;
            if (BuiltinRet.TryGetValue(name, out ret)) return ret;
            Func fn;
            if (funcs.TryGetValue(name, out fn) && fn.ReturnType != null && fn.ReturnType.Length > 0 && fn.Params.Count == 0)
                return fn.ReturnType;
            return Any;
        }
        if (kind == "call")
        {
            string name = (string)tree[1];
            CheckCall(name, (List<object>)tree[2], env, funcs, allowed, line, col);
            Func fn;
            if (funcs.TryGetValue(name, out fn) && fn.ReturnType != null && fn.ReturnType.Length > 0) return fn.ReturnType;
            string ret;
            if (BuiltinRet.TryGetValue(name, out ret)) return ret;
            return Any;
        }
        if (kind == "not" || kind == "neg")
        {
            Infer(tree[1], env, funcs, allowed);
            return kind == "not" ? "bool" : "number";
        }
        if (kind == "bin")
        {
            string op = (string)tree[1];
            string left = Infer(tree[2], env, funcs, allowed);
            string right = Infer(tree[3], env, funcs, allowed);
            if (op == "and" || op == "or") return "bool";
            if (op == "==" || op == "!=" || op == "<" || op == ">" || op == "<=" || op == ">=") return "bool";
            if (op == "+")
            {
                if (left == "number" && right == "number") return "number";
                if (left == "text" && right == "text") return "text";
                if (left == "list" && right == "list") return "list";
                return Any;
            }
            return "number";
        }
        if (kind == "at")
        {
            Infer(tree[1], env, funcs, allowed);
            Infer(tree[2], env, funcs, allowed);
            return Any;
        }
        return Any;
    }

    static void NeedCap(string builtin, HashSet<string> allowed, int line, int col)
    {
        string cap = NeedFor(builtin);
        if (cap == null) return;
        if (allowed.Contains(cap)) return;
        throw new VireError(builtin + " needs capability " + cap, line, col);
    }

    static void Expect(string want, string got, string message, int line, int col)
    {
        if (want == null || want.Length == 0 || want == Any) return;
        if (got == null || got.Length == 0 || got == Any) return;
        if (want == got) return;
        throw new VireError(message, line, col);
    }

    static Dictionary<string, string> CopyEnv(Dictionary<string, string> env)
    {
        return new Dictionary<string, string>(env);
    }

    static int LineOf(object[] node)
    {
        if (node == null || node.Length < 2) return 1;
        object last = node[node.Length - 1];
        object prev = node[node.Length - 2];
        if (prev is int && last is int) return (int)prev;
        if (last is int) return (int)last;
        return 1;
    }

    static int ColOf(object[] node)
    {
        if (node == null || node.Length < 2) return 1;
        object last = node[node.Length - 1];
        object prev = node[node.Length - 2];
        if (prev is int && last is int) return (int)last;
        return 1;
    }
}
