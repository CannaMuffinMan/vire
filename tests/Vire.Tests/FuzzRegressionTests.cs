using System;
using System.IO;
using System.Text;
using Xunit;

public class FuzzRegressionTests
{
    [Fact]
    public void NestedBlocksHitAVireErrorNotAStackOverflow()
    {
        StringBuilder source = new StringBuilder();
        source.Append("define main\n");
        int depth = 300;
        for (int i = 0; i < depth; i++) source.Append("if 1\n");
        source.Append("say 1\n");
        for (int i = 0; i < depth; i++) source.Append("end\n");
        source.Append("end\n");
        VireError err = Assert.Throws<VireError>(() =>
        {
            new Parser(Lexer.Tokenize(source.ToString())).Parse();
        });
        Assert.Contains("nested too deeply", err.Message);
    }

    [Fact]
    public void JsonOverSizeLimitIsRefused()
    {
        string huge = "\"" + new string('a', 1000001) + "\"";
        VireError err = Assert.Throws<VireError>(() => Json.Read(huge, 1));
        Assert.Contains("too large", err.Message);
    }

    [Fact]
    public void SealedGarbageJsonDoesNotRunAndDoesNotCrash()
    {
        WithKey(() =>
        {
            byte[] packed = VireSeal.SealBytes(Encoding.UTF8.GetBytes("{\"funcs\":\"nope\"}"));
            VireError err = Assert.Throws<VireError>(() => CompiledProgram.LoadFuncs(packed));
            Assert.Contains("funcs", err.Message);

            byte[] badFn = VireSeal.SealBytes(Encoding.UTF8.GetBytes("{\"funcs\":[{\"name\":1,\"params\":[],\"body\":[]}]}"));
            VireError damaged = Assert.Throws<VireError>(() => CompiledProgram.LoadFuncs(badFn));
            Assert.Contains("damaged", damaged.Message);

            string dir = Path.Combine(Path.GetTempPath(), "vire-fuzz-vc-" + Guid.NewGuid().ToString("n"));
            Directory.CreateDirectory(dir);
            try
            {
                string file = Path.Combine(dir, "x.vc");
                File.WriteAllBytes(file, packed);
                int code = Program.Execute(new string[] { "run", file });
                Assert.Equal(1, code);
            }
            finally
            {
                try { Directory.Delete(dir, true); } catch (IOException) { }
            }
        });
    }

    [Fact]
    public void HostileLockfilesAreVireErrorsNotCrashes()
    {
        int pid = Environment.ProcessId;
        Assert.Throws<VireError>(() => VireLock.ParseText("vire.lock 1\n" + new string('#', VireLock.MaxLineChars + 1) + "\n"));
        Assert.Throws<VireError>(() => VireLock.ParseText("vire.lock 2\n"));
        Assert.Throws<VireError>(() => VireLock.ParseText("vire.lock 1\npkg ui 0 packages/ui/" + new string('a', 300) + " " + new string('0', 64) + "\n"));
        StringBuilder lines = new StringBuilder("vire.lock 1\n");
        for (int i = 0; i < VireLock.MaxLockLines; i++) lines.Append("# x\n");
        Assert.Throws<VireError>(() => VireLock.ParseText(lines.ToString()));
        Assert.Equal(pid, Environment.ProcessId);
    }

    [Fact]
    public void UnsealedForgedMagicIsRefused()
    {
        WithKey(() =>
        {
            byte[] packed = Encoding.ASCII.GetBytes("VIRE1" + new string('x', 40));
            VireError err = Assert.Throws<VireError>(() => VireSeal.OpenBytes(packed));
            Assert.Contains("old seal", err.Message);
            Assert.Throws<VireError>(() => CompiledProgram.LoadFuncs(packed));
        });
    }

    static void WithKey(Action body)
    {
        string previous = Environment.GetEnvironmentVariable("VIRE_SEAL_KEY");
        byte[] key = new byte[32];
        for (int i = 0; i < key.Length; i++) key[i] = (byte)(i + 3);
        Environment.SetEnvironmentVariable("VIRE_SEAL_KEY", Convert.ToBase64String(key));
        VireSeal.ClearKey();
        try
        {
            VireSeal.LoadFromEnvironment();
            body();
        }
        finally
        {
            VireSeal.ClearKey();
            Environment.SetEnvironmentVariable("VIRE_SEAL_KEY", previous);
        }
    }
}
