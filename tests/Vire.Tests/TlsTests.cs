using System;
using System.Diagnostics;
using System.IO;
using System.Net;
using System.Net.Sockets;
using System.Text;
using System.Threading;
using Xunit;

public class TlsTests
{
    [Fact]
    public void DualModeTlsConnectRefusesPrivate()
    {
        DualMode.DualRun run = DualMode.RunSource(
            "define main\n  tls_connect with \"10.0.0.1\", 443, \"x\", \"\"\nend\n", null);
        Assert.True(run.Matched, Diff(run));
        Assert.Equal(1, run.InterpCode);
        Assert.Contains("private", run.InterpErr);
    }

    [Fact]
    public void DualModeTlsConnectNeedsFourValues()
    {
        DualMode.DualRun run = DualMode.RunSource(
            "define main\n  tls_connect with \"127.0.0.1\", 443\nend\n", null);
        Assert.True(run.Matched, Diff(run));
        Assert.Equal(1, run.InterpCode);
        Assert.Contains("tls_connect takes 4", run.InterpErr);
    }

    [Fact]
    public void DualModeTlsConnectRefusesPathTraversal()
    {
        DualMode.DualRun run = DualMode.RunSource(
            "define main\n  tls_connect with \"127.0.0.1\", 443, \"localhost\", \"../etc/passwd\"\nend\n", null);
        Assert.True(run.Matched, Diff(run));
        Assert.Equal(1, run.InterpCode);
        Assert.Contains("folder", DualMode.Norm(run.InterpErr) + DualMode.Norm(run.InterpOut));
    }

    [Fact]
    public void DualModeTlsConnectRefusesAbsoluteOutsideGate()
    {
        DualMode.DualRun run = DualMode.RunSource(
            "define main\n  tls_connect with \"127.0.0.1\", 443, \"localhost\", \"/etc/passwd\"\nend\n", null);
        Assert.True(run.Matched, Diff(run));
        Assert.Equal(1, run.InterpCode);
        string err = DualMode.Norm(run.InterpErr) + DualMode.Norm(run.InterpOut);
        Assert.True(err.Contains("folder") || err.Contains("inside") || err.Contains("path"), err);
    }

    [Fact]
    public void NativeCompilerWiresTlsBuiltins()
    {
        string root = DualMode.FindRoot();
        string native = File.ReadAllText(Path.Combine(root, "compile-native.vire"));
        Assert.Contains("tls_connect", native);
        Assert.Contains("tls_wrap", native);
        Assert.Contains("tls_peer_cert", native);
        Assert.Contains("tls_end_point", native);
        Assert.Contains("rt_tls_peer_cert", File.ReadAllText(Path.Combine(root, "src", "rt-tls.vire")));
        Assert.Contains("rt_tls_connect", File.ReadAllText(Path.Combine(root, "src", "rt-tls.vire")));
        Assert.Contains("rt_tls_wrap", File.ReadAllText(Path.Combine(root, "src", "rt-tls.vire")));
        Assert.Contains("rt_tls_listen", File.ReadAllText(Path.Combine(root, "src", "rt-tls.vire")));
        string elfTls = File.ReadAllText(Path.Combine(root, "src", "rt-tls.vire"));
        Assert.Contains("76, 137, 77, 208", elfTls);
        Assert.DoesNotContain("emitList with image, [72, 137, 85, 208]\n  emitList with image, [72, 137, 85, 224]", elfTls);
        Assert.Contains("rt_tls_wrap", File.ReadAllText(Path.Combine(root, "src", "rt-tls-pe.vire")));
        Assert.Contains("openPeTlsImage", File.ReadAllText(Path.Combine(root, "src", "pe.vire")));
        Assert.Contains("openTlsPeImage", File.ReadAllText(Path.Combine(root, "src", "pe.vire")));
        Assert.Contains("secur32.dll", File.ReadAllText(Path.Combine(root, "src", "pe.vire")));
        Assert.Contains("InitializeSecurityContextA", File.ReadAllText(Path.Combine(root, "src", "pe.vire")));
        Assert.Contains("SSL_VERIFY", File.ReadAllText(Path.Combine(root, "docs", "native-tls.md")));
        Assert.DoesNotContain("SSL_VERIFY_NONE", File.ReadAllText(Path.Combine(root, "src", "rt-tls.vire")));
        Assert.DoesNotContain("native tls_listen is fail-closed", File.ReadAllText(Path.Combine(root, "src", "rt-tls.vire")));
        string peTls = File.ReadAllText(Path.Combine(root, "src", "rt-tls-pe.vire"));
        string peImg = File.ReadAllText(Path.Combine(root, "src", "pe.vire"));
        Assert.Contains("AcquireCredentialsHandleA", peImg);
        Assert.Contains("InitializeSecurityContextA", peImg);
        Assert.Contains("AcceptSecurityContext", peImg);
        Assert.Contains("EncryptMessage", peImg);
        Assert.Contains("iat_ach", peTls);
        Assert.Contains("iat_isc", peTls);
        Assert.Contains("iat_asc", peTls);
        Assert.Contains("iat_enc", peTls);
        Assert.DoesNotContain("SCH_CRED_NO_SERVERNAME_CHECK", peTls);
        Assert.DoesNotContain("SCH_CRED_MANUAL_CRED_VALIDATION", peTls);
        Assert.DoesNotContain("SCH_CRED_IGNORE_NO_REVOCATION_CHECK", peTls);
        Assert.Contains("openTlsPeImage", File.ReadAllText(Path.Combine(root, "src", "pe.vire")));
        Assert.Contains("openTlsPeImage", native);
    }

    [Fact]
    public void HostTlsHandshakeAgainstOpensslIfPresent()
    {
        if (!HasOpenssl()) return;
        string root = DualMode.FindRoot();
        string data = Path.Combine(root, "data");
        Directory.CreateDirectory(data);
        string cert = Path.Combine(data, "tls-test-cert.pem");
        string key = Path.Combine(data, "tls-test-key.pem");
        MakeCert(cert, key);
        int port = FreePort();
        Process server = StartOpenssl(new string[] { "s_server", "-accept", port.ToString(), "-cert", cert, "-key", key, "-www", "-tls1_2" });
        try
        {
            WaitPort(port);
            string work = Path.Combine(root, "data", "tls-host");
            Directory.CreateDirectory(Path.Combine(work, "data"));
            File.Copy(cert, Path.Combine(work, "data", "tls-test-cert.pem"), true);
            string src = "define main\n  let h be tls_connect with \"127.0.0.1\", " + port + ", \"localhost\", \"data/tls-test-cert.pem\"\n  tls_send with h, \"GET / HTTP/1.0\\r\\n\\r\\n\"\n  let got be tls_recv with h, 200\n  tls_close with h\n  say got\nend\n";
            File.WriteAllText(Path.Combine(work, "prog.vire"), src);
            DualMode.Proc interp = DualMode.RunVire(root, new string[] { "prog.vire" }, work);
            Assert.Equal(0, interp.Code);
            Assert.Contains("HTTP", interp.Out);
        }
        finally
        {
            try { server.Kill(); } catch (Exception) { }
        }
    }

    static bool HasOpenssl()
    {
        try
        {
            ProcessStartInfo info = new ProcessStartInfo("openssl", "version");
            info.RedirectStandardOutput = true;
            info.RedirectStandardError = true;
            info.UseShellExecute = false;
            Process p = Process.Start(info);
            p.WaitForExit(5000);
            return p.ExitCode == 0;
        }
        catch (Exception) { return false; }
    }

    static void MakeCert(string cert, string key)
    {
        ProcessStartInfo info = new ProcessStartInfo("openssl",
            "req -x509 -newkey rsa:2048 -keyout \"" + key + "\" -out \"" + cert + "\" -days 1 -nodes -subj /CN=localhost");
        info.RedirectStandardOutput = true;
        info.RedirectStandardError = true;
        info.UseShellExecute = false;
        Process p = Process.Start(info);
        p.WaitForExit(15000);
        if (p.ExitCode != 0) throw new InvalidOperationException(p.StandardError.ReadToEnd());
    }

    static Process StartOpenssl(string[] args)
    {
        ProcessStartInfo info = new ProcessStartInfo();
        info.FileName = "openssl";
        info.Arguments = string.Join(" ", args);
        info.RedirectStandardOutput = true;
        info.RedirectStandardError = true;
        info.UseShellExecute = false;
        return Process.Start(info);
    }

    static int FreePort()
    {
        TcpListener l = new TcpListener(IPAddress.Loopback, 0);
        l.Start();
        int p = ((IPEndPoint)l.LocalEndpoint).Port;
        l.Stop();
        return p;
    }

    static void WaitPort(int port)
    {
        DateTime until = DateTime.UtcNow.AddSeconds(5);
        while (DateTime.UtcNow < until)
        {
            try
            {
                using (TcpClient c = new TcpClient())
                {
                    c.Connect("127.0.0.1", port);
                    return;
                }
            }
            catch (Exception) { Thread.Sleep(50); }
        }
        throw new TimeoutException("openssl s_server");
    }

    static string Diff(DualMode.DualRun run)
    {
        return "interp=" + run.InterpCode + " compiled=" + run.CompCode
            + " err=" + DualMode.Norm(run.InterpErr) + "/" + DualMode.Norm(run.CompErr);
    }
}
