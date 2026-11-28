using System;
using System.Diagnostics;
using System.IO;
using System.Text;
using Xunit;

public class PgRedisTlsStubTests
{
    [Fact]
    public void WindowsScriptsStartVireProofLoopbackStubs()
    {
        string root = DualMode.FindRoot();
        string pg = File.ReadAllText(Path.Combine(root, "tools", "pg-tls-prove-windows.ps1"));
        Assert.Contains("pg-tls-stub", pg);
        Assert.Contains("Get-VireProofDll", pg);
        Assert.DoesNotContain("initdb.exe", pg);
        Assert.DoesNotContain("Set-MpPreference", pg);
        string rd = File.ReadAllText(Path.Combine(root, "tools", "redis-tls-prove-windows.ps1"));
        Assert.Contains("redis-tls-stub", rd);
        Assert.Contains("Get-VireProofDll", rd);
        Assert.DoesNotContain("tls-cert-file", rd);
        string all = File.ReadAllText(Path.Combine(root, "tools", "couchstation-windows-all.ps1"));
        Assert.Contains("pg-tls-prove-windows.ps1", all);
        Assert.Contains("redis-tls-prove-windows.ps1", all);
        Assert.Contains("pg-redis-tls-windows.ps1", all);
        string proof = File.ReadAllText(Path.Combine(root, "tools", "VireProof", "Program.cs"));
        Assert.Contains("pg-tls-stub", proof);
        Assert.Contains("redis-tls-stub", proof);
    }

    [Fact]
    public void HostMatchesPgSslRequestStubAndPeImportsSchannel()
    {
        string root = DualMode.FindRoot();
        string proof = BuildProof(root);
        string work = Path.Combine(root, "data", "pg-stub", Guid.NewGuid().ToString("N"));
        Directory.CreateDirectory(work);
        Directory.CreateDirectory(Path.Combine(work, "data"));
        Process stub = null;
        try
        {
            string pfx = Path.Combine(work, "data", "pg-tls.pfx");
            string ca = Path.Combine(work, "data", "pg-ca.pem");
            RunProof(proof, root, "write-pfx", pfx, ca, "x");
            File.Copy(ca, Path.Combine(root, "data", "pg-ca.pem"), true);
            stub = StartProof(proof, root, "pg-tls-stub", pfx, "x");
            int port = ReadPort(stub);
            string lib = File.ReadAllText(Path.Combine(root, "src", "rt-pg.vire"));
            string guest = File.ReadAllText(Path.Combine(root, "tests", "native", "pg-tls.vire"));
            guest = guest.Replace("PORT_PLACEHOLDER", port.ToString())
                .Replace("PGUSER_PLACEHOLDER", "vire")
                .Replace("PGDB_PLACEHOLDER", "vire")
                .Replace("PGSECRET_PLACEHOLDER", "x");
            string src = Path.Combine(work, "run.vire");
            File.WriteAllText(src, lib + "\n" + guest);
            string rel = Rel(root, src);
            File.Copy(src, Path.Combine(root, "pg-tls-run.vire"), true);
            DualMode.Proc host = DualMode.RunVire(root, new string[] { "pg-tls-run.vire" }, root);
            Assert.True(host.Code == 0, DualMode.Norm(host.Out + " " + host.Err));
            Assert.Contains("auth trust", DualMode.Norm(host.Out));
            Assert.Contains("PG TLS PROVE pass", DualMode.Norm(host.Out));
            string peRel = Rel(root, Path.Combine(work, "run.pe.hex"));
            DualMode.Proc pe = DualMode.RunVire(
                root,
                new string[] { "compile-native.vire", rel, peRel, "pe" },
                root);
            Assert.True(pe.Code == 0, DualMode.Norm(pe.Out + " " + pe.Err));
            byte[] image = HexFile(root, peRel);
            string ascii = Encoding.ASCII.GetString(image);
            Assert.Contains("secur32.dll", ascii.ToLowerInvariant());
        }
        finally
        {
            try { if (stub != null && !stub.HasExited) stub.Kill(); } catch (Exception) { }
            try { Directory.Delete(work, true); } catch (IOException) { }
        }
    }

    [Fact]
    public void LinuxElfPgTlsWrapAndRedisTlsConnectAgainstStubs()
    {
        if (!OperatingSystem.IsLinux())
            return;
        string root = DualMode.FindRoot();
        string proof = BuildProof(root);
        string work = Path.Combine(root, "data", "elf-tls-stub", Guid.NewGuid().ToString("N"));
        Directory.CreateDirectory(work);
        Directory.CreateDirectory(Path.Combine(work, "data"));
        Process pgStub = null;
        Process redisStub = null;
        try
        {
            string pfx = Path.Combine(work, "data", "pg-tls.pfx");
            string ca = Path.Combine(work, "data", "pg-ca.pem");
            string unPfx = Path.Combine(work, "data", "pg-untrusted.pfx");
            string unCer = Path.Combine(work, "data", "pg-untrusted.pem");
            RunProof(proof, root, "write-pfx", pfx, ca, "x");
            RunProof(proof, root, "write-pfx-expired", unPfx, unCer, "x");
            File.Copy(ca, Path.Combine(root, "data", "pg-ca.pem"), true);
            File.Copy(unCer, Path.Combine(root, "data", "pg-untrusted.pem"), true);
            pgStub = StartProof(proof, root, "pg-tls-stub", pfx, "x");
            int pgPort = ReadPort(pgStub);
            string lib = File.ReadAllText(Path.Combine(root, "src", "rt-pg.vire"));
            string guest = File.ReadAllText(Path.Combine(root, "tests", "native", "pg-tls.vire"));
            guest = guest.Replace("PORT_PLACEHOLDER", pgPort.ToString())
                .Replace("PGUSER_PLACEHOLDER", "vire")
                .Replace("PGDB_PLACEHOLDER", "vire")
                .Replace("PGSECRET_PLACEHOLDER", "x");
            string src = Path.Combine(work, "pg-run.vire");
            File.WriteAllText(src, lib + "\n" + guest);
            string rel = Rel(root, src);
            File.Copy(src, Path.Combine(root, "pg-tls-run.vire"), true);
            DualMode.Proc host = DualMode.RunVire(root, new string[] { "pg-tls-run.vire" }, root);
            Assert.True(host.Code == 0, DualMode.Norm(host.Out + " " + host.Err));
            Assert.Contains("PG TLS PROVE pass", DualMode.Norm(host.Out));
            string hexRel = Rel(root, Path.Combine(work, "pg-run.hex"));
            DualMode.Proc compiled = DualMode.RunVire(
                root,
                new string[] { "compile-native.vire", rel, hexRel, "elf" },
                root);
            Assert.True(compiled.Code == 0, DualMode.Norm(compiled.Out + " " + compiled.Err));
            DualMode.Proc elf = RunElf(root, HexPath(root, hexRel));
            Assert.True(elf.Code == 0, DualMode.Norm(elf.Out + " " + elf.Err) + " code=" + elf.Code);
            Assert.Contains("non-loopback refused", DualMode.Norm(elf.Out));
            Assert.Contains("PG TLS PROVE pass", DualMode.Norm(elf.Out));

            string vguest = File.ReadAllText(Path.Combine(root, "tests", "native", "pg-tls-verify.vire"));
            vguest = vguest.Replace("PORT_PLACEHOLDER", pgPort.ToString())
                .Replace("PGUSER_PLACEHOLDER", "vire")
                .Replace("PGDB_PLACEHOLDER", "vire")
                .Replace("PGSECRET_PLACEHOLDER", "x");
            File.WriteAllText(Path.Combine(root, "pg-tls-verify-run.vire"), lib + "\n" + vguest);
            DualMode.Proc verify = DualMode.RunVire(root, new string[] { "pg-tls-verify-run.vire" }, root);
            Assert.True(verify.Code == 0, DualMode.Norm(verify.Out + " " + verify.Err));
            Assert.Contains("wrong-host ", DualMode.Norm(verify.Out));
            Assert.Contains("untrusted-ca ", DualMode.Norm(verify.Out));

            string rpfx = Path.Combine(work, "data", "redis-tls.pfx");
            string rca = Path.Combine(work, "data", "redis-ca.pem");
            string expPfx = Path.Combine(work, "data", "redis-expired.pfx");
            string expCer = Path.Combine(work, "data", "redis-expired.pem");
            RunProof(proof, root, "write-pfx", rpfx, rca, "x");
            RunProof(proof, root, "write-pfx-expired", expPfx, expCer, "x");
            File.Copy(rca, Path.Combine(root, "data", "redis-ca.pem"), true);
            File.WriteAllText(Path.Combine(root, "data", "redis-untrusted.pem"), File.ReadAllText(expCer));
            redisStub = StartProof(proof, root, "redis-tls-stub", rpfx, "x", expPfx, "x");
            int tlsPort = ReadPort(redisStub);
            string rlib = File.ReadAllText(Path.Combine(root, "src", "rt-redis.vire"));
            string rguest = File.ReadAllText(Path.Combine(root, "tests", "native", "redis-tls.vire"));
            rguest = rguest.Replace("TLS_PORT_PLACEHOLDER", tlsPort.ToString())
                .Replace("SECRET_PLACEHOLDER", "x");
            string rsrc = Path.Combine(work, "redis-run.vire");
            File.WriteAllText(rsrc, rlib + "\n" + rguest);
            string rrel = Rel(root, rsrc);
            File.Copy(rsrc, Path.Combine(root, "redis-tls-run.vire"), true);
            DualMode.Proc rhost = DualMode.RunVire(root, new string[] { "redis-tls-run.vire" }, root);
            Assert.True(rhost.Code == 0, DualMode.Norm(rhost.Out + " " + rhost.Err));
            Assert.Contains("REDIS TLS PROVE pass", DualMode.Norm(rhost.Out));
            string rhex = Rel(root, Path.Combine(work, "redis-run.hex"));
            DualMode.Proc rcompiled = DualMode.RunVire(
                root,
                new string[] { "compile-native.vire", rrel, rhex, "elf" },
                root);
            Assert.True(rcompiled.Code == 0, DualMode.Norm(rcompiled.Out + " " + rcompiled.Err));
            DualMode.Proc relf = RunElf(root, HexPath(root, rhex));
            Assert.True(relf.Code == 0, DualMode.Norm(relf.Out + " " + relf.Err) + " code=" + relf.Code);
            Assert.Contains("REDIS TLS PROVE pass", DualMode.Norm(relf.Out));
        }
        finally
        {
            try { if (pgStub != null && !pgStub.HasExited) pgStub.Kill(); } catch (Exception) { }
            try { if (redisStub != null && !redisStub.HasExited) redisStub.Kill(); } catch (Exception) { }
            try { Directory.Delete(work, true); } catch (IOException) { }
        }
    }

    [Fact]
    public void HostMatchesRedisTlsStubFailClosedAndPeImportsSchannel()
    {
        string root = DualMode.FindRoot();
        string proof = BuildProof(root);
        string work = Path.Combine(root, "data", "redis-stub", Guid.NewGuid().ToString("N"));
        Directory.CreateDirectory(work);
        Directory.CreateDirectory(Path.Combine(work, "data"));
        Process stub = null;
        try
        {
            string pfx = Path.Combine(work, "data", "redis-tls.pfx");
            string ca = Path.Combine(work, "data", "redis-ca.pem");
            string expPfx = Path.Combine(work, "data", "redis-expired.pfx");
            string expCer = Path.Combine(work, "data", "redis-expired.pem");
            RunProof(proof, root, "write-pfx", pfx, ca, "x");
            RunProof(proof, root, "write-pfx-expired", expPfx, expCer, "x");
            File.Copy(ca, Path.Combine(root, "data", "redis-ca.pem"), true);
            File.WriteAllText(Path.Combine(root, "data", "redis-untrusted.pem"), File.ReadAllText(expCer));
            stub = StartProof(proof, root, "redis-tls-stub", pfx, "x", expPfx, "x");
            int tlsPort = ReadPort(stub);
            int plain = ReadTaggedPort(stub, "listening-plain on 127.0.0.1:");
            int exp = ReadTaggedPort(stub, "listening-expired on 127.0.0.1:");
            string lib = File.ReadAllText(Path.Combine(root, "src", "rt-redis.vire"));
            string guest = File.ReadAllText(Path.Combine(root, "tests", "native", "redis-tls.vire"));
            guest = guest.Replace("TLS_PORT_PLACEHOLDER", tlsPort.ToString())
                .Replace("SECRET_PLACEHOLDER", "x");
            string src = Path.Combine(work, "run.vire");
            File.WriteAllText(src, lib + "\n" + guest);
            string rel = Rel(root, src);
            File.Copy(src, Path.Combine(root, "redis-tls-run.vire"), true);
            DualMode.Proc host = DualMode.RunVire(root, new string[] { "redis-tls-run.vire" }, root);
            Assert.True(host.Code == 0, DualMode.Norm(host.Out + " " + host.Err));
            Assert.Contains("REDIS TLS PROVE pass", DualMode.Norm(host.Out));
            string vguest = File.ReadAllText(Path.Combine(root, "tests", "native", "redis-tls-verify.vire"));
            vguest = vguest.Replace("TLS_PORT_PLACEHOLDER", tlsPort.ToString())
                .Replace("SECRET_PLACEHOLDER", "x")
                .Replace("EXP_PORT_PLACEHOLDER", exp.ToString());
            string vsrc = Path.Combine(work, "verify.vire");
            File.WriteAllText(vsrc, lib + "\n" + vguest);
            File.Copy(vsrc, Path.Combine(root, "redis-tls-verify-run.vire"), true);
            DualMode.Proc verify = DualMode.RunVire(root, new string[] { "redis-tls-verify-run.vire" }, root);
            Assert.True(verify.Code == 0, DualMode.Norm(verify.Out + " " + verify.Err));
            Assert.Contains("wrong-host ", DualMode.Norm(verify.Out));
            Assert.Contains("untrusted-ca ", DualMode.Norm(verify.Out));
            Assert.Contains("expired-cert ", DualMode.Norm(verify.Out));
            string ng = File.ReadAllText(Path.Combine(root, "tests", "native", "redis-tls-neg.vire"));
            ng = ng.Replace("PLAIN_PORT_PLACEHOLDER", plain.ToString());
            string nsrc = Path.Combine(work, "neg.vire");
            File.WriteAllText(nsrc, lib + "\n" + ng);
            File.Copy(nsrc, Path.Combine(root, "redis-tls-neg-run.vire"), true);
            DualMode.Proc neg = DualMode.RunVire(root, new string[] { "redis-tls-neg-run.vire" }, root);
            Assert.True(neg.Code == 0, DualMode.Norm(neg.Out + " " + neg.Err));
            Assert.Contains("downgrade ", DualMode.Norm(neg.Out));
            string hexRel = Rel(root, Path.Combine(work, "run.hex"));
            DualMode.Proc compiled = DualMode.RunVire(
                root,
                new string[] { "compile-native.vire", rel, hexRel, "pe" },
                root);
            Assert.True(compiled.Code == 0, DualMode.Norm(compiled.Out + " " + compiled.Err));
            byte[] pe = HexFile(root, hexRel);
            Assert.Contains("secur32.dll", Encoding.ASCII.GetString(pe).ToLowerInvariant());
        }
        finally
        {
            try { if (stub != null && !stub.HasExited) stub.Kill(); } catch (Exception) { }
            try { Directory.Delete(work, true); } catch (IOException) { }
        }
    }

    static string BuildProof(string root)
    {
        string proj = Path.Combine(root, "tools", "VireProof", "VireProof.csproj");
        ProcessStartInfo info = new ProcessStartInfo("dotnet", "build \"" + proj + "\" -c Release --nologo");
        info.WorkingDirectory = root;
        info.RedirectStandardOutput = true;
        info.RedirectStandardError = true;
        info.UseShellExecute = false;
        Process p = Process.Start(info);
        p.WaitForExit(120000);
        Assert.Equal(0, p.ExitCode);
        string dll = Path.Combine(root, "tools", "VireProof", "bin", "Release", "net10.0", "vire-proof.dll");
        Assert.True(File.Exists(dll), dll);
        return dll;
    }

    static void RunProof(string dll, string root, params string[] args)
    {
        ProcessStartInfo info = new ProcessStartInfo("dotnet", "exec \"" + dll + "\" " + string.Join(" ", Quote(args)));
        info.WorkingDirectory = root;
        info.RedirectStandardOutput = true;
        info.RedirectStandardError = true;
        info.UseShellExecute = false;
        Process p = Process.Start(info);
        p.WaitForExit(30000);
        Assert.True(p.ExitCode == 0, p.StandardOutput.ReadToEnd() + p.StandardError.ReadToEnd());
    }

    static Process StartProof(string dll, string root, params string[] args)
    {
        ProcessStartInfo info = new ProcessStartInfo("dotnet", "exec \"" + dll + "\" " + string.Join(" ", Quote(args)));
        info.WorkingDirectory = root;
        info.RedirectStandardOutput = true;
        info.RedirectStandardError = true;
        info.UseShellExecute = false;
        return Process.Start(info);
    }

    static string[] Quote(string[] args)
    {
        string[] outv = new string[args.Length];
        for (int i = 0; i < args.Length; i++) outv[i] = "\"" + args[i] + "\"";
        return outv;
    }

    static int ReadPort(Process p)
    {
        return ReadTaggedPort(p, "listening on 127.0.0.1:");
    }

    static int ReadTaggedPort(Process p, string prefix)
    {
        DateTime dead = DateTime.UtcNow.AddSeconds(12);
        while (DateTime.UtcNow < dead)
        {
            if (p.HasExited) throw new InvalidOperationException("stub exited " + p.ExitCode + " " + p.StandardError.ReadToEnd());
            string line = p.StandardOutput.ReadLine();
            if (line == null) continue;
            if (line.StartsWith(prefix, StringComparison.Ordinal))
                return int.Parse(line.Substring(prefix.Length).Trim());
        }
        throw new TimeoutException("no " + prefix);
    }

    static string Rel(string root, string path)
    {
        return Path.GetRelativePath(root, path).Replace('\\', '/');
    }

    static string HexPath(string root, string hexRel)
    {
        return Path.Combine(root, hexRel.Replace('/', Path.DirectorySeparatorChar));
    }

    static byte[] HexFile(string root, string hexRel)
    {
        string hex = File.ReadAllText(HexPath(root, hexRel)).Trim();
        byte[] raw = new byte[hex.Length / 2];
        for (int i = 0; i < raw.Length; i++)
            raw[i] = Convert.ToByte(hex.Substring(i * 2, 2), 16);
        return raw;
    }

    static DualMode.Proc RunElf(string root, string hexPath)
    {
        string hex = File.ReadAllText(hexPath).Trim();
        byte[] raw = new byte[hex.Length / 2];
        for (int i = 0; i < raw.Length; i++)
            raw[i] = Convert.ToByte(hex.Substring(i * 2, 2), 16);
        string elfPath = hexPath + ".elf";
        File.WriteAllBytes(elfPath, raw);
        Process chmod = Process.Start(new ProcessStartInfo("chmod", "+x \"" + elfPath + "\"") { UseShellExecute = false });
        chmod.WaitForExit();
        ProcessStartInfo ninfo = new ProcessStartInfo(elfPath)
        {
            RedirectStandardOutput = true,
            RedirectStandardError = true,
            UseShellExecute = false,
            WorkingDirectory = root
        };
        Process nat = Process.Start(ninfo);
        string nout = nat.StandardOutput.ReadToEnd();
        string nerr = nat.StandardError.ReadToEnd();
        Assert.True(nat.WaitForExit(60000), "elf timed out");
        return new DualMode.Proc(nat.ExitCode, nout, nerr);
    }
}
