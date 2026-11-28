using System;
using System.Diagnostics;
using System.IO;
using System.Net;
using System.Net.Sockets;
using System.Text;
using System.Threading;
using Xunit;

public class NativeProxyReplyTests
{
    [Fact]
    public void PackedListenParksGetBodyAsTxtEmpty()
    {
        string root = DualMode.FindRoot();
        string net = File.ReadAllText(Path.Combine(root, "src", "rt-net.vire"));
        string blob = File.ReadAllText(Path.Combine(root, "src", "rt-net-blob.txt")).Trim();
        Assert.Equal("488d15", blob.Substring(2728 * 2, 6));
        Assert.Contains("pr_body_fix", net);
        Assert.Contains("land_st_405", net);
        Assert.Contains("land_ws_echo", net);
        Assert.Contains("a90a0000a400", File.ReadAllText(Path.Combine(root, "src", "rt-net-fixes.txt")));
        Assert.True(File.Exists(Path.Combine(root, "tests", "native", "proxy-reply.vire")));
        Assert.True(File.Exists(Path.Combine(root, "tools", "proxy-reply-proof.sh")));
        Assert.True(File.Exists(Path.Combine(root, "tools", "proxy-reply-windows.ps1")));
        Assert.Contains("proxy-reply-windows.ps1", File.ReadAllText(Path.Combine(root, "tools", "couchstation-windows-all.ps1")));
        Assert.Equal(5000000, Program.ProgramStepCap);
    }

    [Fact]
    public void LinuxElfListenProxyReplyMatchesHost()
    {
        if (!OperatingSystem.IsLinux())
            return;
        string root = DualMode.FindRoot();
        string work = Path.Combine(root, "data", "native-proxy-reply-test", Guid.NewGuid().ToString("N"));
        Directory.CreateDirectory(work);
        TcpListener up = new TcpListener(IPAddress.Loopback, 0);
        up.Start();
        int upPort = ((IPEndPoint)up.LocalEndpoint).Port;
        using (CancellationTokenSource cts = new CancellationTokenSource())
        {
            Thread upThread = new Thread(() =>
            {
                while (!cts.IsCancellationRequested)
                {
                    try
                    {
                        up.Server.ReceiveTimeout = 500;
                        TcpClient c = up.AcceptTcpClient();
                        NetworkStream ns = c.GetStream();
                        byte[] buf = new byte[4096];
                        ns.Read(buf, 0, buf.Length);
                        byte[] payload = Encoding.ASCII.GetBytes(
                            "HTTP/1.1 200 OK\r\nContent-Type: text/plain\r\nContent-Length: 5\r\n\r\nup-ok");
                        ns.Write(payload, 0, payload.Length);
                        c.Close();
                    }
                    catch (Exception)
                    {
                        break;
                    }
                }
            });
            upThread.IsBackground = true;
            upThread.Start();
            try
            {
                File.Copy(Path.Combine(root, "tests", "native", "proxy-reply.vire"), Path.Combine(work, "proxy-reply.vire"));
                File.Copy(Path.Combine(root, "src", "http-client.vire"), Path.Combine(work, "http-client.vire"));
                string dir = Path.GetRelativePath(root, work).Replace('\\', '/');
                DualMode.Proc compiled = DualMode.RunVire(root, new string[] { "compile-native.vire", dir + "/proxy-reply.vire", dir + "/proxy-reply.hex" }, root);
                Assert.True(compiled.Code == 0, DualMode.Norm(compiled.Out + " " + compiled.Err));
                string hex = File.ReadAllText(Path.Combine(work, "proxy-reply.hex")).Trim();
                byte[] elf = new byte[hex.Length / 2];
                for (int i = 0; i < elf.Length; i++)
                    elf[i] = Convert.ToByte(hex.Substring(i * 2, 2), 16);
                string elfPath = Path.Combine(work, "proxy-reply.elf");
                File.WriteAllBytes(elfPath, elf);
                if (OperatingSystem.IsLinux())
                {
                    Process chmod = Process.Start(new ProcessStartInfo("chmod", "+x \"" + elfPath + "\"") { UseShellExecute = false });
                    chmod.WaitForExit();
                }
                string dll = typeof(Program).Assembly.Location;
                string dotnet = Environment.GetEnvironmentVariable("DOTNET_HOST_PATH");
                if (string.IsNullOrEmpty(dotnet)) dotnet = "dotnet";
                ListenProc host = ListenProc.Start(dotnet, "exec \"" + dll + "\" \"" + Path.Combine(work, "proxy-reply.vire") + "\" " + upPort);
                ListenProc nat = ListenProc.Start(elfPath, upPort.ToString());
                string hostRaw = HttpGet(host.Port);
                string natRaw = HttpGet(nat.Port);
                host.Dispose();
                nat.Dispose();
                Assert.StartsWith("HTTP/", hostRaw);
                Assert.StartsWith("HTTP/", natRaw);
                Assert.Contains("up-ok", hostRaw);
                Assert.Contains("up-ok", natRaw);
                Assert.Equal(Status(hostRaw), Status(natRaw));
                Assert.Equal(Body(hostRaw), Body(natRaw));
            }
            finally
            {
                cts.Cancel();
                try { up.Stop(); } catch (Exception) { }
            }
        }
    }

    static int Status(string raw)
    {
        string line = raw.Split(new[] { "\r\n" }, StringSplitOptions.None)[0];
        return int.Parse(line.Split(' ')[1]);
    }

    static string Body(string raw)
    {
        int i = raw.IndexOf("\r\n\r\n", StringComparison.Ordinal);
        return i < 0 ? "" : raw.Substring(i + 4);
    }

    static string HttpGet(int port)
    {
        using (TcpClient c = new TcpClient())
        {
            c.Connect(IPAddress.Loopback, port);
            NetworkStream ns = c.GetStream();
            byte[] req = Encoding.ASCII.GetBytes("GET /proxy HTTP/1.1\r\nHost: x\r\nConnection: close\r\n\r\n");
            ns.Write(req, 0, req.Length);
            ns.ReadTimeout = 5000;
            MemoryStream ms = new MemoryStream();
            byte[] buf = new byte[4096];
            try
            {
                int n;
                while ((n = ns.Read(buf, 0, buf.Length)) > 0)
                    ms.Write(buf, 0, n);
            }
            catch (IOException) { }
            return Encoding.ASCII.GetString(ms.ToArray());
        }
    }

    sealed class ListenProc : IDisposable
    {
        public int Port;
        Process proc;

        public static ListenProc Start(string file, string args)
        {
            ListenProc lp = new ListenProc();
            ProcessStartInfo info = new ProcessStartInfo(file, args);
            info.WorkingDirectory = DualMode.FindRoot();
            info.RedirectStandardOutput = true;
            info.RedirectStandardError = true;
            info.UseShellExecute = false;
            info.Environment["VIRE_HEADLESS"] = "1";
            info.Environment.Remove("VIRE_BUDGET");
            lp.proc = Process.Start(info);
            string acc = "";
            DateTime until = DateTime.UtcNow.AddSeconds(10);
            while (DateTime.UtcNow < until)
            {
                string line = lp.proc.StandardOutput.ReadLine();
                if (line == null)
                    break;
                acc += line + "\n";
                int at = acc.IndexOf("listening on 127.0.0.1:", StringComparison.Ordinal);
                if (at >= 0)
                {
                    int colon = acc.IndexOf(':', at + "listening on 127.0.0.1".Length);
                    int start = colon + 1;
                    int end = start;
                    while (end < acc.Length && char.IsDigit(acc[end])) end++;
                    lp.Port = int.Parse(acc.Substring(start, end - start));
                    return lp;
                }
            }
            throw new InvalidOperationException("no listen: " + acc);
        }

        public void Dispose()
        {
            try { if (proc != null && !proc.HasExited) proc.Kill(); } catch (Exception) { }
        }
    }
}
