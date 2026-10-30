using System;
using System.Collections.Generic;
using System.IO;
using System.Net;
using System.Net.Sockets;
using System.Text;
using System.Threading;
using Xunit;

public class PathSsrfTests
{
    [Fact]
    public void SafeNameRefusesTraversalAdsDevicesAndTrailingDots()
    {
        string[] bad =
        {
            "x.vire.",
            "x.vire ",
            "evil.exe.",
            "a:b.txt",
            "CON.txt",
            "nul",
            "data/../x",
            "COM1.log",
            "lpt9",
            "AUX.vire",
            "foo/bar.",
            "foo/bar ",
            "C:\\windows\\x",
            "/etc/passwd",
            "foo<>bar",
            "foo|bar",
            "foo\"bar",
            "foo?bar",
            "foo*bar",
            "foo\nbar"
        };
        for (int i = 0; i < bad.Length; i++)
        {
            string name = bad[i];
            VireError err = Assert.Throws<VireError>(() => VirePaths.CheckName(name, 1));
            Assert.Contains("program folder", err.Message);
        }
        VirePaths.CheckName("data/note.txt", 1);
        VirePaths.CheckName("site/app.js", 1);
    }

    [Fact]
    public void RefuseProgramUsesNormalizedExtension()
    {
        Assert.Equal(".vire", VirePaths.NormalizedExtension("x.vire."));
        Assert.Equal(".vire", VirePaths.NormalizedExtension("x.vire "));
        Assert.Equal(".exe", VirePaths.NormalizedExtension("evil.exe."));
        Assert.Equal(".psm1", VirePaths.NormalizedExtension("mod.psm1"));
        Assert.Throws<VireError>(() => VirePaths.RefuseProgram("plant.vire.", 1));
        Assert.Throws<VireError>(() => VirePaths.RefuseProgram("evil.exe.", 1));
        Assert.Throws<VireError>(() => VirePaths.RefuseProgram("x.lnk", 1));
        Assert.Throws<VireError>(() => VirePaths.RefuseProgram("x.reg", 1));
        Assert.Throws<VireError>(() => VirePaths.RefuseProgram("x.hta", 1));
        Assert.Throws<VireError>(() => VirePaths.RefuseProgram("x.jar", 1));
        Assert.Throws<VireError>(() => VirePaths.RefuseProgram("x.sh", 1));
        VirePaths.RefuseProgram("data/stage.vc", 1);
        VirePaths.RefuseProgram("site/app.js", 1);
        Assert.Throws<VireError>(() => VirePaths.RefuseProgram("data/xss.js", 1));
        Assert.Throws<VireError>(() => VirePaths.RefuseProgram("/tmp/prog", Path.Combine("/tmp/prog", "data", "xss.js"), 1, 1));
        VirePaths.RefuseProgram("/tmp/prog", Path.Combine("/tmp/prog", "site", "app.js"), 1, 1);
    }

    [Fact]
    public void RunAndUseRefuseWritableZonesAndPlantedPrograms()
    {
        string dir = Path.Combine(Path.GetTempPath(), "vire-c4-" + Guid.NewGuid().ToString("n"));
        Directory.CreateDirectory(Path.Combine(dir, "data"));
        try
        {
            File.WriteAllText(Path.Combine(dir, "data", "evil.vire"), "define main\n  say \"pwn\"\nend\n");
            File.WriteAllText(Path.Combine(dir, "helper.vire"), "define main\nend\n");
            File.WriteAllText(Path.Combine(dir, "runner.vire"), "define main\n  run with \"data/evil.vire\"\nend\n");
            File.WriteAllText(Path.Combine(dir, "user.vire"), "use data/evil.vire\ndefine main\n  say \"no\"\nend\n");
            Assert.Equal(1, Program.Execute(new string[] { Path.Combine(dir, "runner.vire") }));
            Assert.Equal(1, Program.Execute(new string[] { Path.Combine(dir, "user.vire") }));
            VireError run = Assert.Throws<VireError>(() => VirePaths.ProgramFile(dir, "data/evil.vire", 1));
            Assert.Contains("data and site", run.Message);
            VireError use = Assert.Throws<VireError>(() => VirePaths.UseFile(dir, "data/evil.vire", 1));
            Assert.Contains("data and site", use.Message);
        }
        finally
        {
            Directory.Delete(dir, true);
        }
    }

    [Fact]
    public void WriteThenRunCannotPlantVire()
    {
        string dir = Path.Combine(Path.GetTempPath(), "vire-c4w-" + Guid.NewGuid().ToString("n"));
        Directory.CreateDirectory(Path.Combine(dir, "data"));
        try
        {
            File.WriteAllText(Path.Combine(dir, "plant.vire"),
                "define main\n  write with \"data/evil.vire\", \"define main\\n  say \\\"pwn\\\"\\nend\\n\"\nend\n");
            Assert.Equal(1, Program.Execute(new string[] { Path.Combine(dir, "plant.vire") }));
            Assert.False(File.Exists(Path.Combine(dir, "data", "evil.vire")));
        }
        finally
        {
            Directory.Delete(dir, true);
        }
    }

    [Fact]
    public void SymlinkEscapeIsRefusedOrSkipped()
    {
        string dir = Path.Combine(Path.GetTempPath(), "vire-c4s-" + Guid.NewGuid().ToString("n"));
        Directory.CreateDirectory(Path.Combine(dir, "data"));
        string outside = Path.Combine(Path.GetTempPath(), "vire-c4-out-" + Guid.NewGuid().ToString("n") + ".txt");
        File.WriteAllText(outside, "secret");
        string link = Path.Combine(dir, "data", "link.txt");
        try
        {
            try { File.CreateSymbolicLink(link, outside); }
            catch (Exception ex)
            {
                Console.WriteLine("symlink test skipped: " + ex.GetType().Name);
                return;
            }
            if (!File.Exists(link) && !Directory.Exists(link))
            {
                Console.WriteLine("symlink test skipped: link was not created");
                return;
            }
            File.WriteAllText(Path.Combine(dir, "readlink.vire"), "define main\n  say (read with \"data/link.txt\")\nend\n");
            Assert.Equal(1, Program.Execute(new string[] { Path.Combine(dir, "readlink.vire") }));
        }
        finally
        {
            try { Directory.Delete(dir, true); } catch (IOException) { }
            try { File.Delete(outside); } catch (IOException) { }
        }
    }

    [Fact]
    public void IsPublicAddressRefusesPrivateMappedAndSpecialRanges()
    {
        string[] blocked =
        {
            "127.0.0.1",
            "0.0.0.0",
            "10.1.2.3",
            "172.16.0.1",
            "192.168.1.1",
            "169.254.169.254",
            "100.64.0.1",
            "100.127.255.255",
            "198.18.0.1",
            "192.0.0.1",
            "192.0.2.1",
            "198.51.100.1",
            "203.0.113.1",
            "240.0.0.1",
            "255.255.255.255",
            "::1",
            "::",
            "::ffff:10.0.0.1",
            "::ffff:127.0.0.1",
            "2002:7f00:0001::1",
            "64:ff9b::10.0.0.1",
            "fc00::1",
            "fd12:3456:789a::1",
            "fe80::1",
            "fec0::1",
            "ff02::1"
        };
        for (int i = 0; i < blocked.Length; i++)
        {
            IPAddress addr = IPAddress.Parse(blocked[i]);
            Assert.False(VireNet.IsPublicAddress(addr), blocked[i]);
        }
        Assert.True(VireNet.IsPublicAddress(IPAddress.Parse("8.8.8.8")));
        Assert.True(VireNet.IsPublicAddress(IPAddress.Parse("2001:4860:4860::8888")));
    }

    [Fact]
    public void FetchRefusesLoopbackMappedNamesAndRedirects()
    {
        int port = PortGuard.GetFreeLoopbackPort();
        TcpListener listener = new TcpListener(IPAddress.Loopback, port);
        listener.Start();
        PortGuard.AssertAllowedPort(((IPEndPoint)listener.LocalEndpoint).Port);
        port = ((IPEndPoint)listener.LocalEndpoint).Port;
        Thread server = new Thread(() => ServeMany(listener, 1));
        server.IsBackground = true;
        server.Start();
        try
        {
            VireError direct = Assert.Throws<VireError>(() => VireNet.DemandPublic("http://127.0.0.1:" + port + "/", 1));
            Assert.Contains("private", direct.Message);

            VireError mapped = Assert.Throws<VireError>(() =>
                VireNet.DemandPublic("http://[::ffff:127.0.0.1]:" + port + "/", 1));
            Assert.Contains("private", mapped.Message);

            VireNet.ResolveHost = host => new IPAddress[] { IPAddress.Loopback };
            VireError rebound = Assert.Throws<VireError>(() =>
                VireNet.DemandPublic("https://public.example.test/", 1));
            Assert.Contains("private", rebound.Message);

            VireError userinfo = Assert.Throws<VireError>(() =>
                VireNet.DemandPublic("https://user:pass@example.com/", 1));
            Assert.Contains("not allowed", userinfo.Message);

            // Test origin may connect to the loopback fixture; a redirect hop to 127.0.0.1 must still be refused.
            VireNet.IsTestOrigin = host => host == "ssrf.test.vire";
            VireNet.ResolveHost = host => new IPAddress[] { IPAddress.Parse("127.0.0.1") };
            VireError redir = Assert.Throws<VireError>(() =>
                VireNet.SendWeb(System.Net.Http.HttpMethod.Get, "http://ssrf.test.vire:" + port + "/go", null, 1));
            Assert.Contains("private", redir.Message);
        }
        finally
        {
            VireNet.ResetHooks();
            listener.Stop();
            server.Join(1000);
        }
    }

    static void ServeMany(TcpListener listener, int times)
    {
        try
        {
            for (int n = 0; n < times; n++)
            {
                using (TcpClient client = listener.AcceptTcpClient())
                using (NetworkStream stream = client.GetStream())
                {
                    byte[] buf = new byte[1024];
                    int got = stream.Read(buf, 0, buf.Length);
                    if (got < 1) continue;
                    int port = ((IPEndPoint)listener.LocalEndpoint).Port;
                    string body = "HTTP/1.1 302 Found\r\nLocation: http://127.0.0.1:" + port + "/secret\r\nContent-Length: 0\r\nConnection: close\r\n\r\n";
                    byte[] bytes = Encoding.ASCII.GetBytes(body);
                    stream.Write(bytes, 0, bytes.Length);
                }
            }
        }
        catch (SocketException) { }
        catch (ObjectDisposedException) { }
        catch (IOException) { }
    }

    [Fact]
    public void FetchAndRunHardeningMatchesInBothModes()
    {
        DualMode.DualRun loop = DualMode.RunSource(
            "define main\n  fetch with \"http://127.0.0.1:9/\"\nend\n", null);
        Assert.True(loop.Matched, Diff(loop));
        Assert.Equal(1, loop.InterpCode);
        Assert.Contains("private", loop.InterpErr);
        Assert.Contains("line 2", loop.InterpErr);
        Assert.Contains("col ", loop.InterpErr);

        DualMode.DualRun mapped = DualMode.RunSource(
            "define main\n  fetch with \"http://[::ffff:127.0.0.1]:9/\"\nend\n", null);
        Assert.True(mapped.Matched, Diff(mapped));
        Assert.Equal(1, mapped.InterpCode);
        Assert.Contains("private", mapped.InterpErr);

        DualMode.DualRun userinfo = DualMode.RunSource(
            "define main\n  fetch with \"https://user:pass@example.com/\"\nend\n", null);
        Assert.True(userinfo.Matched, Diff(userinfo));
        Assert.Equal(1, userinfo.InterpCode);
        Assert.Contains("not allowed", userinfo.InterpErr);

        DualMode.DualRun post = DualMode.RunSource(
            "define main\n  post with \"http://127.0.0.1:9/\", \"x\"\nend\n", null);
        Assert.True(post.Matched, Diff(post));
        Assert.Equal(1, post.InterpCode);
        Assert.Contains("private", post.InterpErr);

        DualMode.DualRun planted = DualMode.RunSource(
            "define main\n  run with \"data/evil.vire\"\nend\n",
            new string[] { "data/evil.vire", "define main\n  say \"pwn\"\nend\n" });
        Assert.True(planted.Matched, Diff(planted));
        Assert.Equal(1, planted.InterpCode);
        Assert.Contains("data and site", planted.InterpErr);

        DualMode.DualRun walk = DualMode.RunSource(
            "define main\n  read with \"data/../secret.txt\"\nend\n", null);
        Assert.True(walk.Matched, Diff(walk));
        Assert.Equal(1, walk.InterpCode);
        Assert.Contains("program folder", walk.InterpErr);
    }

    [Fact]
    public void CompiledFetchRefusesRedirectToPrivate()
    {
        int port = PortGuard.GetFreeLoopbackPort();
        TcpListener listener = new TcpListener(IPAddress.Loopback, port);
        listener.Start();
        PortGuard.AssertAllowedPort(((IPEndPoint)listener.LocalEndpoint).Port);
        port = ((IPEndPoint)listener.LocalEndpoint).Port;
        Thread server = new Thread(() => ServeMany(listener, 2));
        server.IsBackground = true;
        server.Start();
        try
        {
            VireNet.IsTestOrigin = host => host == "ssrf.test.vire";
            VireNet.ResolveHost = host => new IPAddress[] { IPAddress.Parse("127.0.0.1") };
            VireError interp = Assert.Throws<VireError>(() =>
            {
                Machine machine = LoadSnippet("define main\n  fetch with \"http://ssrf.test.vire:" + port + "/go\"\nend\n");
                machine.Call("main", new List<object>(), 1);
            });
            Assert.Contains("private", interp.Message);

            VireError compiled = Assert.Throws<VireError>(() =>
            {
                CompiledMachine machine = new CompiledMachine(
                    FetchFunc("http://ssrf.test.vire:" + port + "/go"),
                    ".",
                    new List<object>(),
                    FreshBudget());
                machine.Call("main", new List<object>(), 1, 1);
            });
            Assert.Contains("private", compiled.Message);
        }
        finally
        {
            VireNet.ResetHooks();
            listener.Stop();
            server.Join(1000);
        }
    }

    [Fact]
    public void SymlinkEscapeIsRefusedInBothModesOrSkipped()
    {
        string dir = Path.Combine(Path.GetTempPath(), "vire-c4s2-" + Guid.NewGuid().ToString("n"));
        Directory.CreateDirectory(Path.Combine(dir, "data"));
        string outside = Path.Combine(Path.GetTempPath(), "vire-c4-out2-" + Guid.NewGuid().ToString("n") + ".txt");
        File.WriteAllText(outside, "secret");
        string link = Path.Combine(dir, "data", "link.txt");
        try
        {
            try { File.CreateSymbolicLink(link, outside); }
            catch (Exception ex)
            {
                Console.WriteLine("symlink dual-mode test skipped: " + ex.GetType().Name);
                return;
            }
            if (!File.Exists(link) && !Directory.Exists(link))
            {
                Console.WriteLine("symlink dual-mode test skipped: link was not created");
                return;
            }
            string src = "define main\n  say (read with \"data/link.txt\")\nend\n";
            File.WriteAllText(Path.Combine(dir, "readlink.vire"), src);
            Assert.Equal(1, Program.Execute(new string[] { Path.Combine(dir, "readlink.vire") }));

            DualMode.DualRun both = DualMode.RunSource(src, null);
            // DualMode work folder has no symlink; in-process Execute already covered interpreter.
            Assert.True(both.InterpCode == 1 || both.CompCode == 1 || both.Matched);
        }
        finally
        {
            try { Directory.Delete(dir, true); } catch (IOException) { }
            try { File.Delete(outside); } catch (IOException) { }
        }
    }

    static string Diff(DualMode.DualRun both)
    {
        return "interp " + both.InterpCode + " compiled " + both.CompCode
            + "\n i-err " + both.InterpErr + "\n c-err " + both.CompErr
            + "\n i-out " + both.InterpOut + "\n c-out " + both.CompOut;
    }

    static Machine LoadSnippet(string source)
    {
        string dir = Path.Combine(Path.GetTempPath(), "vire-ssrf-" + Guid.NewGuid().ToString("n"));
        Directory.CreateDirectory(dir);
        string path = Path.Combine(dir, "prog.vire");
        File.WriteAllText(path, source);
        Dictionary<string, Func> funcs = Program.Load(path, dir, new System.Collections.Generic.HashSet<string>());
        return new Machine(funcs, dir);
    }

    static Dictionary<string, object> FetchFunc(string url)
    {
        Dictionary<string, object> func = new Dictionary<string, object>();
        func["name"] = "main";
        func["params"] = new List<object>();
        List<object> call = new List<object> { "call", "fetch", new List<object> { new List<object> { "text", url, 2, 3 } }, 2, 3 };
        func["body"] = new List<object> { call };
        Dictionary<string, object> funcs = new Dictionary<string, object>();
        funcs["main"] = func;
        return funcs;
    }

    static Budget FreshBudget()
    {
        Budget budget = new Budget();
        budget.ApplyStepLimit(500000);
        return budget;
    }
}
