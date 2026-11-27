using System;
using System.Collections.Generic;
using System.IO;
using System.Net;
using System.Net.Sockets;
using System.Threading;
using Xunit;

public class DnsTests
{
    [Fact]
    public void SkipNameRejectsTruncationPointerLoopAndReservedBits()
    {
        int hops;
        Assert.Equal(-1, VireDns.SkipName(new byte[] { 1 }, 1, 0, out hops));
        Assert.Equal(-1, VireDns.SkipName(new byte[0], 0, 0, out hops));
        Assert.Equal(-1, VireDns.SkipName(null, 0, 0, out hops));
        Assert.Equal(-1, VireDns.SkipName(new byte[] { 3, (byte)'a' }, 2, 0, out hops));
        Assert.Equal(-1, VireDns.SkipName(new byte[] { 0xC0 }, 1, 0, out hops));
        Assert.Equal(-1, VireDns.SkipName(new byte[] { 0x40, 0 }, 2, 0, out hops));
        Assert.Equal(-1, VireDns.SkipName(new byte[] { 0x80, 0 }, 2, 0, out hops));

        byte[] loop = new byte[12];
        loop[0] = 0xC0;
        loop[1] = 0x00;
        Assert.Equal(-1, VireDns.SkipName(loop, loop.Length, 0, out hops));
        Assert.True(hops > VireDns.MaxHops || hops >= 1);

        byte[] self = new byte[] { 0xC0, 0x00 };
        Assert.Equal(-1, VireDns.SkipName(self, 2, 0, out hops));

        byte[] far = new byte[] { 0xC0, 0xFF };
        Assert.Equal(-1, VireDns.SkipName(far, 2, 0, out hops));

        byte[] ok = new byte[] { 1, (byte)'a', 0 };
        Assert.Equal(3, VireDns.SkipName(ok, 3, 0, out hops));
        Assert.Equal(0, hops);

        byte[] ptrOk = new byte[] { 1, (byte)'a', 0, 0xC0, 0x00 };
        Assert.Equal(5, VireDns.SkipName(ptrOk, 5, 3, out hops));
        Assert.Equal(1, hops);
    }

    [Fact]
    public void ParseResponseRejectsHostileRdataAndShortPackets()
    {
        List<string> into = new List<string>();
        Assert.False(VireDns.ParseResponse(new byte[11], 11, 1, VireDns.TypeA, into));
        byte[] huge = new byte[VireDns.MaxPacket + 1];
        Assert.False(VireDns.ParseResponse(huge, huge.Length, 1, VireDns.TypeA, into));

        byte[] q = VireDns.BuildQuery("ok.example", 0x1111, VireDns.TypeA);
        Assert.NotNull(q);
        byte[] badQr = (byte[])q.Clone();
        Assert.False(VireDns.ParseResponse(badQr, badQr.Length, 0x1111, VireDns.TypeA, into));

        byte[] over = Answer(0x2222, "x.test", new byte[] { 1, 2, 3, 4 }, 5);
        over[over.Length - 5] = 0;
        over[over.Length - 4] = 99;
        Assert.False(VireDns.ParseResponse(over, over.Length, 0x2222, VireDns.TypeA, into));

        byte[] good = AnswerFromQuery(VireDns.BuildQuery("x.test", 0x3333, VireDns.TypeA), 0x3333, VireDns.TypeA, new byte[] { 127, 0, 0, 1 });
        into.Clear();
        Assert.True(VireDns.ParseResponse(good, good.Length, 0x3333, VireDns.TypeA, into));
        Assert.Equal(new[] { "127.0.0.1" }, into.ToArray());
    }

    [Fact]
    public void HostsAndResolvParseStayOnLoopbackFixtureNames()
    {
        List<string> found = new List<string>();
        VireDns.AddHosts(found, "local.test", "127.0.0.1 local.test\n# 10.0.0.1 other\n");
        Assert.Equal(new[] { "127.0.0.1" }, found.ToArray());
        IPEndPoint[] ns = VireDns.ParseResolv("nameserver 127.0.0.1\nnameserver not-an-ip\n");
        Assert.Single(ns);
        Assert.Equal(IPAddress.Loopback, ns[0].Address);
        Assert.Equal(53, ns[0].Port);
        Assert.False(VireDns.HostOk(""));
        Assert.False(VireDns.HostOk("bad_name"));
        Assert.True(VireDns.HostOk("local.test"));
    }

    [Fact]
    public void DualModeResolveUsesLoopbackFakeDns()
    {
        UdpClient server = new UdpClient(new IPEndPoint(IPAddress.Loopback, 0));
        int port = ((IPEndPoint)server.Client.LocalEndPoint).Port;
        Thread worker = new Thread(() =>
        {
            try
            {
                for (int i = 0; i < 32; i++)
                {
                    IPEndPoint from = new IPEndPoint(IPAddress.Any, 0);
                    byte[] req = server.Receive(ref from);
                    if (req == null || req.Length < 12) continue;
                    int id = (req[0] << 8) | req[1];
                    int qtype = 1;
                    int off = VireDns.SkipName(req, req.Length, 12);
                    if (off >= 0 && off + 2 <= req.Length)
                        qtype = (req[off] << 8) | req[off + 1];
                    byte[] rdata = qtype == VireDns.TypeAaaa
                        ? new byte[] { 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1 }
                        : new byte[] { 127, 0, 0, 1 };
                    byte[] ans = AnswerFromQuery(req, id, qtype, rdata);
                    server.Send(ans, ans.Length, from);
                }
            }
            catch (SocketException) { }
            catch (ObjectDisposedException) { }
        });
        worker.IsBackground = true;
        worker.Start();
        string prev = Environment.GetEnvironmentVariable("VIRE_DNS");
        try
        {
            Environment.SetEnvironmentVariable("VIRE_DNS", "127.0.0.1:" + port);
            DualMode.DualRun run = DualMode.RunSource(
                "define main\n  let xs be resolve with \"ok.test\"\n  say (xs at 0)\nend\n",
                null);
            Assert.True(run.Matched, Diff(run));
            Assert.True(run.InterpCode == 0, Diff(run));
            Assert.Equal("127.0.0.1\n", DualMode.Norm(run.InterpOut));

            DualMode.DualRun guest = DualMode.RunSource(
                File.ReadAllText(Path.Combine(DualMode.FindRoot(), "tests", "native", "dns-resolve.vire")),
                null);
            Assert.True(guest.InterpCode == 0, Diff(guest));
            string hostOut = DualMode.Norm(guest.InterpOut);
            Assert.Contains("that name is not valid", hostOut);
            Assert.Contains("127.0.0.1", hostOut);
            Assert.DoesNotContain("invalid-missed", hostOut);
        }
        finally
        {
            Environment.SetEnvironmentVariable("VIRE_DNS", prev);
            try { server.Close(); } catch (Exception) { }
            worker.Join(2000);
        }
    }

    [Fact]
    public void DualModeConnectHostnameUsesResolvedLoopback()
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
                        byte[] buf = new byte[16];
                        int n = stream.Read(buf, 0, buf.Length);
                        if (n > 0) stream.Write(buf, 0, n);
                    }
                }
            }
            catch (SocketException) { }
            catch (ObjectDisposedException) { }
        });
        worker.IsBackground = true;
        worker.Start();
        UdpClient dns = new UdpClient(new IPEndPoint(IPAddress.Loopback, 0));
        int dnsPort = ((IPEndPoint)dns.Client.LocalEndPoint).Port;
        Thread dnsWorker = new Thread(() =>
        {
            try
            {
                    for (int i = 0; i < 32; i++)
                    {
                        IPEndPoint from = new IPEndPoint(IPAddress.Any, 0);
                        byte[] req = dns.Receive(ref from);
                    if (req == null || req.Length < 12) continue;
                    int id = (req[0] << 8) | req[1];
                    byte[] ans = AnswerFromQuery(req, id, VireDns.TypeA, new byte[] { 127, 0, 0, 1 });
                    dns.Send(ans, ans.Length, from);
                }
            }
            catch (SocketException) { }
            catch (ObjectDisposedException) { }
        });
        dnsWorker.IsBackground = true;
        dnsWorker.Start();
        string prev = Environment.GetEnvironmentVariable("VIRE_DNS");
        try
        {
            Environment.SetEnvironmentVariable("VIRE_DNS", "127.0.0.1:" + dnsPort);
            DualMode.DualRun run = DualMode.RunSource(
                "define main\n  let h be connect with \"loop.test\", " + port + "\n  send with h, \"hi\"\n  let got be recv with h, 8\n  close with h\n  say got\nend\n",
                null);
            Assert.True(run.Matched, Diff(run));
            Assert.Equal(0, run.InterpCode);
            Assert.Equal("hi\n", DualMode.Norm(run.InterpOut));
        }
        finally
        {
            Environment.SetEnvironmentVariable("VIRE_DNS", prev);
            try { listener.Stop(); } catch (Exception) { }
            try { dns.Close(); } catch (Exception) { }
            worker.Join(2000);
            dnsWorker.Join(2000);
        }
    }

    [Fact]
    public void MalformedFuzzCorpusNeverReadsPastLength()
    {
        Random rng = new Random(7);
        for (int n = 0; n < 200; n++)
        {
            int len = rng.Next(0, 600);
            byte[] pkt = new byte[len];
            rng.NextBytes(pkt);
            int hops;
            int off = VireDns.SkipName(pkt, Math.Min(len, pkt.Length), 0, out hops);
            Assert.True(off == -1 || (off >= 0 && off <= Math.Min(len, pkt.Length)));
            List<string> into = new List<string>();
            VireDns.ParseResponse(pkt, Math.Min(len, pkt.Length), rng.Next(0, 65536), VireDns.TypeA, into);
        }
    }

    static byte[] Answer(int id, string host, byte[] rdata, int rdlenUse)
    {
        byte[] q = VireDns.BuildQuery(host, id, VireDns.TypeA);
        byte[] pkt = new byte[q.Length + 12 + rdata.Length];
        Buffer.BlockCopy(q, 0, pkt, 0, q.Length);
        pkt[2] = 0x81;
        pkt[3] = 0x80;
        pkt[6] = 0;
        pkt[7] = 1;
        int off = q.Length;
        pkt[off] = 0xC0;
        pkt[off + 1] = 12;
        pkt[off + 2] = 0;
        pkt[off + 3] = 1;
        pkt[off + 4] = 0;
        pkt[off + 5] = 1;
        pkt[off + 8] = 0;
        pkt[off + 9] = (byte)rdlenUse;
        Buffer.BlockCopy(rdata, 0, pkt, off + 10, rdata.Length);
        return pkt;
    }

    static byte[] AnswerFromQuery(byte[] q, int id, int qtype, byte[] rdata)
    {
        byte[] pkt = new byte[q.Length + 12 + rdata.Length];
        Buffer.BlockCopy(q, 0, pkt, 0, q.Length);
        pkt[0] = (byte)((id >> 8) & 255);
        pkt[1] = (byte)(id & 255);
        pkt[2] = 0x81;
        pkt[3] = 0x80;
        pkt[6] = 0;
        pkt[7] = 1;
        int off = q.Length;
        pkt[off] = 0xC0;
        pkt[off + 1] = 12;
        pkt[off + 2] = (byte)((qtype >> 8) & 255);
        pkt[off + 3] = (byte)(qtype & 255);
        pkt[off + 4] = 0;
        pkt[off + 5] = 1;
        pkt[off + 10] = (byte)((rdata.Length >> 8) & 255);
        pkt[off + 11] = (byte)(rdata.Length & 255);
        Buffer.BlockCopy(rdata, 0, pkt, off + 12, rdata.Length);
        return pkt;
    }

    static string Diff(DualMode.DualRun run)
    {
        return "interp=" + run.InterpCode + " compiled=" + run.CompCode
            + " out=" + DualMode.Norm(run.InterpOut) + "/" + DualMode.Norm(run.CompOut)
            + " err=" + DualMode.Norm(run.InterpErr) + "/" + DualMode.Norm(run.CompErr);
    }
}
