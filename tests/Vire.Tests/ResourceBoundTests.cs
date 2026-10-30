using System;
using System.Text;
using Xunit;

public class ResourceBoundTests
{
    const int Limit = 256;

    [Fact]
    public void ParensAtLimitMinusOneLimitAndOverMatchInBothModes()
    {
        DualOk(ParenProgram(Limit - 1), "1");
        DualOk(ParenProgram(Limit), "1");
        DualFail(ParenProgram(Limit + 1), VireLimits.NestError);
        DualFail(ParenProgram(100000), VireLimits.NestError);
    }

    [Fact]
    public void NestedIfsAtLimitMinusOneLimitAndOverMatchInBothModes()
    {
        DualOk(IfProgram(Limit - 1), "ok");
        DualOk(IfProgram(Limit), "ok");
        DualFail(IfProgram(Limit + 1), VireLimits.NestError);
    }

    [Fact]
    public void NestedListsAndCallsMatchInBothModes()
    {
        DualOk(ListProgram(Limit - 1), "1");
        DualFail(ListProgram(Limit), "expression is too deep");
        DualFail(ListProgram(Limit + 1), VireLimits.NestError);
        DualFail(CallProgram(Limit + 1), VireLimits.NestError);
        DualFail(NotProgram(Limit + 1), VireLimits.NestError);
    }

    [Fact]
    public void NumericLiteralsMatchAtDigitCapInBothModes()
    {
        DualOk(NumberProgram(new string('1', VireLimits.MaxLiteralDigits - 1)), null);
        DualOk(NumberProgram(new string('1', VireLimits.MaxLiteralDigits)), null);
        DualFail(NumberProgram(new string('9', VireLimits.MaxLiteralDigits + 1)), VireLimits.NumberError);
        DualMode.DualRun huge = DualFail(NumberProgram(new string('9', 400)), VireLimits.NumberError);
        Assert.Contains("line 2 col 7", DualMode.Norm(huge.InterpErr));
        Assert.Equal(DualMode.Norm(huge.InterpErr), DualMode.Norm(huge.CompErr));
    }

    [Fact]
    public void InProcessLexerParserRefuseVeryDeepInputWithoutClrThrow()
    {
        VireError parens = Assert.Throws<VireError>(() => new Parser(Lexer.Tokenize(ParenProgram(100000))).Parse());
        Assert.Equal(VireLimits.NestError, parens.Message);
        Assert.Equal(2, parens.Line);
        Assert.True(parens.Column > 1);

        VireError digits = Assert.Throws<VireError>(() => Lexer.Tokenize(NumberProgram(new string('9', 100000))));
        Assert.Equal(VireLimits.NumberError, digits.Message);
        Assert.Equal(2, digits.Line);
        Assert.Equal(7, digits.Column);

        VireError ifs = Assert.Throws<VireError>(() => new Parser(Lexer.Tokenize(IfProgram(100000))).Parse());
        Assert.Equal(VireLimits.NestError, ifs.Message);
    }

    [Fact]
    public void SeededNestAndDigitFuzzNeverThrowsClrExceptions()
    {
        Random rng = new Random(20261030);
        for (int n = 0; n < 80; n++)
        {
            int kind = rng.Next(5);
            int depth = rng.Next(0, 400);
            string source;
            if (kind == 0) source = ParenProgram(depth);
            else if (kind == 1) source = ListProgram(Math.Min(depth, 300));
            else if (kind == 2) source = IfProgram(Math.Min(depth, 300));
            else if (kind == 3) source = NotProgram(Math.Min(depth, 300));
            else source = NumberProgram(new string('9', rng.Next(1, 500)));
            try
            {
                new Parser(Lexer.Tokenize(source)).Parse();
            }
            catch (VireError)
            {
            }
        }
    }

    static void DualOk(string source, string stdout)
    {
        DualMode.DualRun both = DualMode.RunSource(source, null);
        Assert.True(both.Matched, Diff(both));
        Assert.Equal(0, both.InterpCode);
        if (stdout != null) Assert.Contains(stdout, DualMode.Norm(both.InterpOut));
    }

    static DualMode.DualRun DualFail(string source, string message)
    {
        DualMode.DualRun both = DualMode.RunSource(source, null);
        Assert.True(both.Matched, Diff(both));
        Assert.Equal(1, both.InterpCode);
        Assert.Equal(1, both.CompCode);
        Assert.Contains(message, both.InterpErr);
        Assert.Contains(message, both.CompErr);
        Assert.Contains("line ", both.InterpErr);
        Assert.Contains("col ", both.InterpErr);
        Assert.DoesNotContain("internal error", both.InterpErr);
        Assert.DoesNotContain("internal error", both.CompErr);
        return both;
    }

    static string Diff(DualMode.DualRun both)
    {
        return "interp " + both.InterpCode + " [" + both.InterpErr + "][" + both.InterpOut + "] compile "
            + both.CompCode + " [" + both.CompErr + "][" + both.CompOut + "]";
    }

    static string ParenProgram(int depth)
    {
        return "define main\n  say " + new string('(', depth) + "1" + new string(')', depth) + "\nend\n";
    }

    static string ListProgram(int depth)
    {
        StringBuilder text = new StringBuilder();
        text.Append("define main\n  say ");
        for (int i = 0; i < depth; i++) text.Append('[');
        text.Append('1');
        for (int i = 0; i < depth; i++) text.Append(']');
        text.Append("\nend\n");
        return text.ToString();
    }

    static string CallProgram(int depth)
    {
        StringBuilder text = new StringBuilder();
        text.Append("define main\n  say ");
        for (int i = 0; i < depth; i++) text.Append('(');
        text.Append("abs with 1");
        for (int i = 0; i < depth; i++) text.Append(')');
        text.Append("\nend\n");
        return text.ToString();
    }

    static string NotProgram(int depth)
    {
        StringBuilder text = new StringBuilder();
        text.Append("define main\n  say ");
        for (int i = 0; i < depth; i++) text.Append("not ");
        text.Append("true\nend\n");
        return text.ToString();
    }

    static string IfProgram(int depth)
    {
        StringBuilder text = new StringBuilder();
        text.Append("define main\n");
        for (int i = 0; i < depth; i++) text.Append("  if 1\n");
        text.Append("  say \"ok\"\n");
        for (int i = 0; i < depth; i++) text.Append("  end\n");
        text.Append("end\n");
        return text.ToString();
    }

    static string NumberProgram(string digits)
    {
        return "define main\n  say " + digits + "\nend\n";
    }
}
