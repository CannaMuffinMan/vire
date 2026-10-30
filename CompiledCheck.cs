using System;
using System.Collections.Generic;

sealed class CompiledCheck
{
    const int MaxFuncs = 4096;
    const int MaxSteps = 100000;
    const int MaxExprNodes = 200000;
    int steps;
    int exprNodes;

    public static void Program(Dictionary<string, object> funcs)
    {
        new CompiledCheck().CheckProgram(funcs);
    }

    static VireError Underflow()
    {
        return new VireError("compiled stack underflow", 1, 1);
    }

    static VireError BadOperand()
    {
        return new VireError("bad compiled operand type", 1, 1);
    }

    static VireError BadOpcode()
    {
        return new VireError("bad compiled opcode type", 1, 1);
    }

    void CheckProgram(Dictionary<string, object> funcs)
    {
        if (funcs == null) throw BadOperand();
        if (funcs.Count > MaxFuncs) throw new VireError("compiled file has too many functions", 1, 1);
        foreach (KeyValuePair<string, object> pair in funcs)
        {
            Dictionary<string, object> func = pair.Value as Dictionary<string, object>;
            if (func == null) throw BadOperand();
            object rawParams;
            object rawBody;
            if (!func.TryGetValue("params", out rawParams) || !func.TryGetValue("body", out rawBody))
                throw Underflow();
            List<object> names = rawParams as List<object>;
            List<object> body = rawBody as List<object>;
            if (names == null || body == null) throw BadOperand();
            foreach (object name in names)
                if (!(name is string)) throw BadOperand();
            CheckBlock(body, 0);
        }
    }

    void CheckBlock(List<object> body, int depth)
    {
        if (depth > VireLimits.SourceNest) throw new VireError(VireLimits.NestError, 1, 1);
        if (body == null) throw BadOperand();
        for (int i = 0; i < body.Count; i++)
        {
            List<object> step = body[i] as List<object>;
            if (step == null) throw BadOperand();
            CheckStep(step, body.Count, depth);
        }
    }

    void CheckStep(List<object> step, int blockCount, int depth)
    {
        steps++;
        if (steps > MaxSteps) throw new VireError("compiled program is too large", 1, 1);
        if (step.Count < 1) throw Underflow();
        string op = step[0] as string;
        if (op == null) throw BadOpcode();
        if (op == "jump" || op == "goto")
        {
            if (step.Count < 2) throw Underflow();
            if (!CompiledMachine.IsWholeNum(step[1])) throw BadOperand();
            int target = Convert.ToInt32(step[1]);
            if (target < 0 || target >= blockCount)
                throw new VireError("compiled jump is out of range", 1, 1);
            throw new VireError("unknown compiled step " + op, 1, 1);
        }
        if (op == "let")
        {
            Need(step, 3);
            if (!(step[1] is string)) throw BadOperand();
            CheckExpr(AsExpr(step[2]), 0);
            return;
        }
        if (op == "say" || op == "return")
        {
            Need(step, 2);
            CheckExpr(AsExpr(step[1]), 0);
            return;
        }
        if (op == "stop" || op == "skip") return;
        if (op == "if")
        {
            Need(step, 3);
            CheckExpr(AsExpr(step[1]), 0);
            CheckBlock(AsBlock(step[2]), depth + 1);
            if (step.Count > 3 && step[3] is List<object>) CheckBlock((List<object>)step[3], depth + 1);
            return;
        }
        if (op == "while")
        {
            Need(step, 3);
            CheckExpr(AsExpr(step[1]), 0);
            CheckBlock(AsBlock(step[2]), depth + 1);
            return;
        }
        if (op == "for")
        {
            Need(step, 4);
            if (!(step[1] is string)) throw BadOperand();
            CheckExpr(AsExpr(step[2]), 0);
            CheckBlock(AsBlock(step[3]), depth + 1);
            return;
        }
        if (op == "try")
        {
            Need(step, 2);
            CheckBlock(AsBlock(step[1]), depth + 1);
            if (step.Count >= 4 && step[3] is List<object>) CheckBlock((List<object>)step[3], depth + 1);
            return;
        }
        if (op == "call")
        {
            Need(step, 3);
            if (!(step[1] is string)) throw BadOperand();
            CheckExprList(AsBlock(step[2]), 0);
            return;
        }
        if (op == "put")
        {
            Need(step, 4);
            CheckExpr(AsExpr(step[1]), 0);
            if (!(step[2] is string)) throw BadOperand();
            CheckExpr(AsExpr(step[3]), 0);
            return;
        }
        throw new VireError("unknown compiled step " + op, 1, 1);
    }

    void CheckExprList(List<object> exprs, int depth)
    {
        if (exprs == null) throw BadOperand();
        foreach (object item in exprs) CheckExpr(AsExpr(item), depth);
    }

    void CheckExpr(List<object> expr, int depth)
    {
        if (depth > VireLimits.SourceNest) throw new VireError(VireLimits.NestError, 1, 1);
        exprNodes++;
        if (exprNodes > MaxExprNodes) throw new VireError("compiled expression is too large", 1, 1);
        if (expr == null) throw BadOperand();
        if (expr.Count < 1) throw Underflow();
        string op = expr[0] as string;
        if (op == null) throw BadOpcode();
        if (op == "num" || op == "text" || op == "bool")
        {
            Need(expr, 2);
            return;
        }
        if (op == "none") return;
        if (op == "name")
        {
            Need(expr, 2);
            if (!(expr[1] is string)) throw BadOperand();
            return;
        }
        if (op == "list")
        {
            Need(expr, 2);
            CheckExprList(AsBlock(expr[1]), depth + 1);
            return;
        }
        if (op == "call")
        {
            Need(expr, 3);
            if (!(expr[1] is string)) throw BadOperand();
            CheckExprList(AsBlock(expr[2]), depth + 1);
            return;
        }
        if (op == "at" || op == "and" || op == "or" || op == "+" || op == "-" || op == "*" || op == "/" || op == "%"
            || op == "==" || op == "!=" || op == "<" || op == "<=" || op == ">" || op == ">=")
        {
            Need(expr, 3);
            CheckExpr(AsExpr(expr[1]), depth + 1);
            CheckExpr(AsExpr(expr[2]), depth + 1);
            return;
        }
        if (op == "not" || op == "neg")
        {
            Need(expr, 2);
            CheckExpr(AsExpr(expr[1]), depth + 1);
            return;
        }
        if (op == "map")
        {
            if (expr.Count < 2 || expr[1] == null) return;
            List<object> pairs = expr[1] as List<object>;
            if (pairs == null) throw BadOperand();
            foreach (object pair in pairs)
            {
                List<object> item = pair as List<object>;
                if (item == null || item.Count < 2) throw Underflow();
                CheckExpr(AsExpr(item[0]), depth + 1);
                CheckExpr(AsExpr(item[1]), depth + 1);
            }
            return;
        }
        throw new VireError("unknown compiled expression " + op, 1, 1);
    }

    static void Need(List<object> node, int count)
    {
        if (node.Count < count) throw Underflow();
    }

    static List<object> AsExpr(object value)
    {
        List<object> expr = value as List<object>;
        if (expr == null) throw BadOperand();
        return expr;
    }

    static List<object> AsBlock(object value)
    {
        List<object> block = value as List<object>;
        if (block == null) throw BadOperand();
        return block;
    }
}
