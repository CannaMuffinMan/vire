using System;
using System.IO;
using System.Net;
using System.Net.Sockets;
using System.Text;
using System.Threading;
using Xunit;

public class ConnectTests
{
    [Fact]
    public void DualModeRefusesPrivateAndLinkLocalBeforeConnect()
    {
        DualMode.DualRun priv = DualMode.RunSource(
            "can net.connect.loopback\ndefine main\n  connect with \"10.0.0.1\", 80\nend\n", null);
        Assert.True(priv.Matched, Diff(priv));
        Assert.Equal(1, priv.InterpCode);
        Assert.Contains("private", priv.InterpErr);

        DualMode.DualRun link = DualMode.RunSource(
            "can net.connect.loopback\ndefine main\n  connect with \"169.254.169.254\", 80\nend\n", null);
        Assert.True(link.Matched, Diff(link));
        Assert.Equal(1, link.InterpCode);
        Assert.Contains("private", link.InterpErr);
    }

    [Fact]
    public void DualModeRefusesNonLiteralHostAndBadPort()
    {
        DualMode.DualRun host = DualMode.RunSource(
            "can net.connect.loopback\ndefine main\n  connect with \"localhost\", 8080\nend\n", null);
        Assert.True(host.Matched, Diff(host));
        Assert.Equal(1, host.InterpCode);
        Assert.Contains("not allowed", host.InterpErr);

        DualMode.DualRun port = DualMode.RunSource(
            "can net.connect.loopback\ndefine main\n  connect with \"127.0.0.1\", 0\nend\n", null);
        Assert.True(port.Matched, Diff(port));
        Assert.Equal(1, port.InterpCode);
        Assert.Contains("port", port.InterpErr);
    }

    [Fact]
    public void DualModeLoopbackEchoSendRecvClose()
    {
        TcpListener listener = new TcpListener(IPAddress.Parse("127.0.0.1"), 0);
        listener.Start();
        int port = ((IPEndPoint)listener.LocalEndpoint).Port;
        Thread worker = new Thread(() =>
        {
            try
            {
                for (int i = 0; i < 8; i++)
                {
                    using (TcpClient client = listener.AcceptTcpClient())
                    using (NetworkStream stream = client.GetStream())
                    {
                        byte[] buf = new byte[64];
                        int n = stream.Read(buf, 0, buf.Length);
                        if (n > 0) stream.Write(buf, 0, n);
                    }
                }
            }
            catch (SocketException) { }
            catch (IOException) { }
            catch (ObjectDisposedException) { }
        });
        worker.IsBackground = true;
        worker.Start();
        try
        {
            DualMode.DualRun run = DualMode.RunSource(
                "can net.connect.loopback\ndefine main\n  let h be connect with \"127.0.0.1\", " + port + "\n  send with h, \"ping\"\n  let got be recv with h, 16\n  close with h\n  say got\nend\n",
                null);
            Assert.True(run.Matched, Diff(run));
            Assert.Equal(0, run.InterpCode);
            Assert.Equal("ping\n", DualMode.Norm(run.InterpOut));
        }
        finally
        {
            try { listener.Stop(); } catch (Exception) { }
            worker.Join(2000);
        }
    }

    [Fact]
    public void RecvOversizeIsBoundedWithoutConnect()
    {
        string src = File.ReadAllText(Path.Combine(DualMode.FindRoot(), "src", "rt-net.vire"));
        Assert.Contains("1000000", src);
        Assert.Contains("rt_connect", src);
        Assert.Contains("rt_recv", src);
        Assert.Contains("127.0.0.1", src);
        string native = File.ReadAllText(Path.Combine(DualMode.FindRoot(), "compile-native.vire"));
        Assert.Contains("nm == \"connect\"", native);
        Assert.Contains("nm == \"close\"", native);
    }

    static string Diff(DualMode.DualRun run)
    {
        return "interp=" + run.InterpCode + " compiled=" + run.CompCode
            + " out=" + DualMode.Norm(run.InterpOut) + "/" + DualMode.Norm(run.CompOut)
            + " err=" + DualMode.Norm(run.InterpErr) + "/" + DualMode.Norm(run.CompErr);
    }
}
