using System.Text;
using Xunit;

public class UseNeedTests
{
    [Fact]
    public void GoodUsePrintsKnownLine()
    {
        DualMode.DualRun both = DualMode.RunSource(
            "use \"helper.vire\"\ndefine main\n  say used_line\nend\n",
            new string[]
            {
                "helper.vire",
                "define used_line\n  return \"used-line-ok\"\nend\n"
            });
        Assert.True(both.Matched, Dump(both));
        Assert.Equal(0, both.InterpCode);
        Assert.Contains("used-line-ok", both.InterpOut);
    }

    [Fact]
    public void UseCycleFails()
    {
        DualMode.DualRun both = DualMode.RunSource(
            "use \"cycle_b.vire\"\ndefine main\n  say \"no\"\nend\n",
            new string[]
            {
                "cycle_b.vire",
                "use \"prog.vire\"\ndefine other\n  return 1\nend\n"
            });
        Assert.NotEqual(0, both.InterpCode);
        Assert.NotEqual(0, both.CompCode);
        Assert.Contains("circle", both.InterpErr);
        Assert.Contains("circle", both.CompOut + both.CompErr);
    }

    [Fact]
    public void UseDotDotFails()
    {
        DualMode.DualRun both = DualMode.RunSource(
            "use \"../outside.vire\"\ndefine main\n  say \"no\"\nend\n",
            null);
        Assert.NotEqual(0, both.InterpCode);
        Assert.NotEqual(0, both.CompCode);
        Assert.Contains("program folder", both.InterpErr);
        Assert.Contains("program folder", both.CompOut + both.CompErr);
    }

    [Fact]
    public void NeedPackagePrintsKnownLine()
    {
        string lib = "define greet\n  return \"tiny-package-ok\"\nend\n";
        DualMode.DualRun both = DualMode.RunSource(
            "need \"tiny\"\ndefine main\n  say greet\nend\n",
            new string[]
            {
                "deps/tiny/lib.vire",
                lib,
                "deps.lock",
                "tiny " + VireSeal.HashText(lib)
            });
        Assert.True(both.Matched, Dump(both));
        Assert.Equal(0, both.InterpCode);
        Assert.Contains("tiny-package-ok", both.InterpOut);
    }

    [Fact]
    public void UnicodePackageNameFails()
    {
        DualMode.DualRun both = DualMode.RunSource(
            "need \"caf\u00e9\"\ndefine main\n  say \"no\"\nend\n",
            null);
        Assert.NotEqual(0, both.InterpCode);
        Assert.NotEqual(0, both.CompCode);
        Assert.Contains("plain words", both.InterpErr);
        Assert.Contains("plain words", both.CompOut + both.CompErr);
    }

    [Fact]
    public void DataFolderUseFailsIgnoringCase()
    {
        DualMode.DualRun both = DualMode.RunSource(
            "use \"Data/evil.vire\"\ndefine main\n  say \"no\"\nend\n",
            new string[]
            {
                "Data/evil.vire",
                "define evil\n  return \"no\"\nend\n"
            });
        Assert.NotEqual(0, both.InterpCode);
        Assert.NotEqual(0, both.CompCode);
        Assert.Contains("data and site", both.InterpErr + both.CompOut + both.CompErr);
    }

    [Fact]
    public void BadPackageNameFails()
    {
        DualMode.DualRun both = DualMode.RunSource(
            "need \"bad-name\"\ndefine main\n  say \"no\"\nend\n",
            null);
        Assert.NotEqual(0, both.InterpCode);
        Assert.NotEqual(0, both.CompCode);
        Assert.Contains("plain words", both.InterpErr);
        Assert.Contains("plain words", both.CompOut + both.CompErr);
    }

    [Fact]
    public void MissingPackageFails()
    {
        DualMode.DualRun both = DualMode.RunSource(
            "need \"missingpkg\"\ndefine main\n  say \"no\"\nend\n",
            null);
        Assert.NotEqual(0, both.InterpCode);
        Assert.NotEqual(0, both.CompCode);
        Assert.Contains("deps.lock", both.InterpErr + both.CompErr);
    }

    [Fact]
    public void UseOnlyOpensVireFiles()
    {
        DualMode.DualRun both = DualMode.RunSource(
            "use \"note.txt\"\ndefine main\n  say line\nend\n",
            new string[]
            {
                "note.txt",
                "define line\n  return \"not-vire\"\nend\n"
            });
        Assert.NotEqual(0, both.InterpCode);
        Assert.NotEqual(0, both.CompCode);
        Assert.DoesNotContain("not-vire", both.InterpOut);
        Assert.Contains(".vire", both.InterpErr);
        Assert.Contains(".vire", both.CompOut + both.CompErr);
    }

    [Fact]
    public void UseStaysOutOfData()
    {
        DualMode.DualRun both = DualMode.RunSource(
            "use \"data/evil.vire\"\ndefine main\n  say \"no\"\nend\n",
            new string[]
            {
                "data/evil.vire",
                "define line\n  return \"from-data\"\nend\n"
            });
        Assert.NotEqual(0, both.InterpCode);
        Assert.NotEqual(0, both.CompCode);
        Assert.DoesNotContain("from-data", both.InterpOut + both.CompOut);
        Assert.Contains("data and site", both.InterpErr);
        Assert.Contains("data and site", both.CompOut + both.CompErr);
    }

    [Fact]
    public void ThirtyThirdFileFails()
    {
        DualMode.DualRun both = DualMode.RunSource(ChainSource(32), ChainExtras(32));
        Assert.NotEqual(0, both.InterpCode);
        Assert.NotEqual(0, both.CompCode);
        Assert.Contains("too many files were used", both.InterpErr);
        Assert.Contains("too many files were used", both.CompOut + both.CompErr);
    }

    static string ChainSource(int extras)
    {
        if (extras == 0)
            return "define main\n  say \"files-ok\"\nend\n";
        return "use \"u1.vire\"\ndefine main\n  say mark\nend\n";
    }

    static string[] ChainExtras(int extras)
    {
        string[] files = new string[extras * 2];
        for (int i = 1; i <= extras; i++)
        {
            files[(i - 1) * 2] = "u" + i + ".vire";
            if (i == extras)
                files[(i - 1) * 2 + 1] = "define mark\n  return \"files-ok\"\nend\n";
            else
                files[(i - 1) * 2 + 1] = "use \"u" + (i + 1) + ".vire\"\n";
        }
        return files;
    }

    static string Dump(DualMode.DualRun both)
    {
        StringBuilder text = new StringBuilder();
        text.Append("i ").Append(both.InterpCode).Append(" c ").Append(both.CompCode).Append('\n');
        text.Append(both.InterpOut).Append('\n').Append(both.InterpErr).Append('\n');
        text.Append(both.CompOut).Append('\n').Append(both.CompErr);
        return text.ToString();
    }
}
