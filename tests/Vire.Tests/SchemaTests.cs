using System.IO;
using Xunit;

public class SchemaTests
{
    [Fact]
    public void ParseAcceptsNumberWhereHealthWantsBool()
    {
        string src = string.Join("\n", new string[]
        {
            "define main",
            "  let row be parse with \"{\\\"ok\\\":1}\"",
            "  say kind with (row at \"ok\")",
            "  say row at \"ok\"",
            "end",
            ""
        });
        DualMode.DualRun both = DualMode.RunSource(src, null);
        Assert.True(both.Matched, both.InterpOut + both.CompOut + both.InterpErr + both.CompErr);
        Assert.Equal(0, both.InterpCode);
        Assert.Contains("number", DualMode.Norm(both.InterpOut));
        Assert.Contains("1", DualMode.Norm(both.InterpOut));
    }

    [Fact]
    public void SchemaProveGuestPassesOnHost()
    {
        string root = DualMode.FindRoot();
        DualMode.Proc run = DualMode.RunVire(root, new string[] { "schema-prove.vire" }, root);
        Assert.True(run.Code == 0, run.Err + run.Out);
        string outp = DualMode.Norm(run.Out);
        Assert.Contains("SCHEMA PROVE pass", outp);
        Assert.Contains("HEALTH valid PASS", outp);
        Assert.Contains("TYPE mismatch REJECT", outp);
        Assert.Contains("MISSING required REJECT", outp);
        Assert.Contains("UNKNOWN field REJECT", outp);
        Assert.Contains("OVERSIZE string REJECT", outp);
        Assert.Contains("OVERSIZE array REJECT", outp);
        Assert.Contains("ADV too-deep array REJECT", outp);
        Assert.Contains("ADV too-deep object REJECT", outp);
        Assert.DoesNotContain("crash rip", outp);
    }

    [Fact]
    public void SchemaLibraryDoesNotRaiseCaps()
    {
        string root = DualMode.FindRoot();
        string lib = File.ReadAllText(Path.Combine(root, "src", "rt-schema.vire"));
        Assert.Contains("schema_check", lib);
        Assert.Contains("unknown field", lib);
        Assert.Contains("too-deep nesting", lib);
        Assert.DoesNotContain("33554433", lib);
        Assert.DoesNotContain("100001", lib);
        string yml = File.ReadAllText(Path.Combine(root, ".github", "workflows", "check.yml"));
        Assert.Contains("schema-prove-windows.ps1", yml);
        string ps = File.ReadAllText(Path.Combine(root, "tools", "schema-prove-windows.ps1"));
        Assert.Contains("FAIL_BEFORE parse accepted", ps);
        Assert.Contains("ws2_32.dll", ps);
        Assert.Contains("VIRE_BUDGET", ps);
        Assert.Contains("5000000", ps);
        Assert.DoesNotContain("Set-MpPreference", ps);
    }
}
