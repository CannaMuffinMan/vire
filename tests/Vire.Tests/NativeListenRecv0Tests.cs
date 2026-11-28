using System;
using System.Diagnostics;
using System.IO;
using System.Net;
using System.Net.Sockets;
using System.Text;
using Xunit;

public class NativeListenRecv0Tests
{
    [Fact]
    public void PackedR4BlockgateJumpsToPushrouteNotMidNobody()
    {
        string root = DualMode.FindRoot();
        byte[] r4 = HexFile(Path.Combine(root, "src", "rt-net-r4-blob.txt"));
        Assert.Equal(r4, HexFile(Path.Combine(root, "data", "src", "rt-net-r4-blob.txt")));
        Assert.Equal(0xE9, r4[0xA78]);
        bool sawPush = false;
        for (int i = 0; i + 5 <= r4.Length; i++)
        {
            if (r4[i] != 0xE9) continue;
            int rel = BitConverter.ToInt32(r4, i + 1);
            if (i + 5 + rel == 0xA78) sawPush = true;
        }
        Assert.True(sawPush, "cl_blockgate must jmp 0xa78");
        bool sawRecv0 = false;
        for (int i = 0; i + 2 <= r4.Length; i++)
        {
            if (r4[i] == 0xC9 && r4[i + 1] == 0xC3) sawRecv0 = true;
        }
        Assert.True(sawRecv0);
        byte[] r3 = HexFile(Path.Combine(root, "src", "rt-net-blob.txt"));
        int r3tgt = 0x5E4 + BitConverter.ToInt32(r3, 0x5E0);
        Assert.True(r3tgt >= 0 && r3tgt + 1 < r3.Length);
        Assert.Equal(0xC9, r3[r3tgt]);
        Assert.Equal(0xC3, r3[r3tgt + 1]);
        Assert.Contains("listen-recv0-windows.ps1", File.ReadAllText(Path.Combine(root, "tools", "couchstation-windows-all.ps1")));
        Assert.Equal(5000000, Program.ProgramStepCap);
        Assert.Contains("33554432", File.ReadAllText(Path.Combine(root, "src", "rt.vire")));
    }

    [Fact]
    public void LinuxElfHealthEmptyConnectAndSplitHeadersMatchHost()
    {
        if (!OperatingSystem.IsLinux())
            return;
        string root = DualMode.FindRoot();
        string work = Path.Combine(root, "data", "native-listen-recv0", Guid.NewGuid().ToString("N"));
        Directory.CreateDirectory(work);
        try
        {
            File.Copy(Path.Combine(root, "tests", "native", "listen-recv0.vire"), Path.Combine(work, "listen-recv0.vire"));
            string dir = Path.GetRelativePath(root, work).Replace('\\', '/');
            DualMode.Proc compiled = DualMode.RunVire(root, new string[] { "compile-native.vire", dir + "/listen-recv0.vire", dir + "/listen-recv0.hex" }, root);
            Assert.True(compiled.Code == 0, DualMode.Norm(compiled.Out + compiled.Err));
            byte[] elf = HexFile(Path.Combine(work, "listen-recv0.hex"));
            Assert.Equal(0x7F, elf[0]);
            string elfPath = Path.Combine(work, "listen-recv0.elf");
            File.WriteAllBytes(elfPath, elf);
            Process chmod = Process.Start(new ProcessStartInfo("chmod", "+x \"" + elfPath + "\"") { UseShellExecute = false });
            chmod.WaitForExit();
            string dll = typeof(Program).Assembly.Location;
            string dotnet = Environment.GetEnvironmentVariable("DOTNET_HOST_PATH");
            if (string.IsNullOrEmpty(dotnet)) dotnet = "dotnet";
            using (ListenProc host = ListenProc.Start(dotnet, "exec \"" + dll + "\" \"" + Path.Combine(work, "listen-recv0.vire") + "\""))
            using (ListenProc nat = ListenProc.Start(elfPath, ""))
            {
                string hostRaw = HttpGet(host.Port);
                string natRaw = HttpGet(nat.Port);
                Assert.StartsWith("HTTP/1.1 200", hostRaw);
                Assert.Equal(hostRaw, natRaw);
                Assert.Contains("{\"ok\":true}", natRaw);

                ConnectAndClose(nat.Port);
                string afterEmpty = HttpGet(nat.Port);
                Assert.Equal(hostRaw, afterEmpty);

                string split = HttpSplitGet(nat.Port);
                Assert.Equal(hostRaw, split);

                Assert.True(!nat.HasExited, "native listen died after recv0/split");
            }
        }
        finally
        {
            try { Directory.Delete(work, true); } catch (IOException) { }
        }
    }

    static byte[] HexFile(string path)
    {
        string hex = File.ReadAllText(path).Trim();
        byte[] b = new byte[hex.Length / 2];
        for (int i = 0; i < b.Length; i++)
            b[i] = Convert.ToByte(hex.Substring(i * 2, 2), 16);
        return b;
    }

    static string HttpGet(int port)
    {
        return Exchange(port, Encoding.ASCII.GetBytes("GET /api/health HTTP/1.1\r\nHost: 127.0.0.1\r\nConnection: close\r\n\r\n"));
    }

    static string HttpSplitGet(int port)
    {
        using (TcpClient c = new TcpClient())
        {
            c.Connect(IPAddress.Loopback, port);
            NetworkStream ns = c.GetStream();
            byte[] a = Encoding.ASCII.GetBytes("GET /api/health HTTP/1.1\r\nHost: 127.0.0.1\r\n");
            byte[] b = Encoding.ASCII.GetBytes("Connection: close\r\n\r\n");
            ns.Write(a, 0, a.Length);
            ns.Write(b, 0, b.Length);
            return ReadAll(ns);
        }
    }

    static void ConnectAndClose(int port)
    {
        using (TcpClient c = new TcpClient())
        {
            c.Connect(IPAddress.Loopback, port);
        }
    }

    static string Exchange(int port, byte[] req)
    {
        using (TcpClient c = new TcpClient())
        {
            c.Connect(IPAddress.Loopback, port);
            NetworkStream ns = c.GetStream();
            ns.Write(req, 0, req.Length);
            return ReadAll(ns);
        }
    }

    static string ReadAll(NetworkStream ns)
    {
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

    sealed class ListenProc : IDisposable
    {
        public int Port;
        Process proc;

        public bool HasExited
        {
            get { return proc == null || proc.HasExited; }
        }

        public static ListenProc Start(string file, string args)
        {
            ListenProc lp = new ListenProc();
            ProcessStartInfo info = string.IsNullOrEmpty(args)
                ? new ProcessStartInfo(file)
                : new ProcessStartInfo(file, args);
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
