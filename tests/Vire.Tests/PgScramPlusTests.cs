using System;
using System.IO;
using System.Net;
using System.Net.Sockets;
using System.Security.Cryptography;
using System.Text;
using System.Threading;
using Xunit;

public class PgScramPlusTests
{
    static byte[] Be32(int n)
    {
        return new byte[] { (byte)(n >> 24), (byte)(n >> 16), (byte)(n >> 8), (byte)n };
    }

    static byte[] AuthSasl(params string[] mechs)
    {
        using (MemoryStream body = new MemoryStream())
        {
            body.Write(Be32(10), 0, 4);
            foreach (string mech in mechs)
            {
                byte[] raw = Encoding.ASCII.GetBytes(mech);
                body.Write(raw, 0, raw.Length);
                body.WriteByte(0);
            }
            body.WriteByte(0);
            byte[] payload = body.ToArray();
            using (MemoryStream msg = new MemoryStream())
            {
                msg.WriteByte((byte)'R');
                byte[] len = Be32(payload.Length + 4);
                msg.Write(len, 0, 4);
                msg.Write(payload, 0, payload.Length);
                return msg.ToArray();
            }
        }
    }

    static byte[] AuthFinalError(string e)
    {
        byte[] payload = Encoding.ASCII.GetBytes("e=" + e);
        using (MemoryStream msg = new MemoryStream())
        {
            msg.WriteByte((byte)'R');
            byte[] hdr = Be32(4 + 4 + payload.Length);
            msg.Write(hdr, 0, 4);
            msg.Write(Be32(12), 0, 4);
            msg.Write(payload, 0, payload.Length);
            return msg.ToArray();
        }
    }

    [Fact]
    public void Rfc7677PublishedProofAt4096()
    {
        byte[] salt = Convert.FromBase64String("W22ZaJ0SNY7soEsUEjb6gQ==");
        byte[] salted = Rfc2898DeriveBytes.Pbkdf2("pencil", salt, 4096, HashAlgorithmName.SHA256, 32);
        byte[] clientKey = HMACSHA256.HashData(salted, Encoding.ASCII.GetBytes("Client Key"));
        byte[] stored = SHA256.HashData(clientKey);
        string cn = "rOprNGfwEbeRWgbNEkqO";
        string sn = "rOprNGfwEbeRWgbNEkqO%hvYDpWUa2RaTCAfuxFIlj)hNlF$k0";
        string bare = "n=user,r=" + cn;
        string serverFirst = "r=" + sn + ",s=W22ZaJ0SNY7soEsUEjb6gQ==,i=4096";
        string without = "c=biws,r=" + sn;
        byte[] auth = Encoding.ASCII.GetBytes(bare + "," + serverFirst + "," + without);
        byte[] sig = HMACSHA256.HashData(stored, auth);
        byte[] proof = new byte[32];
        for (int i = 0; i < 32; i++) proof[i] = (byte)(clientKey[i] ^ sig[i]);
        Assert.Equal("dHzbZapWIk4jUhN+Ute9ytag9zjfMHgsqmmiz7AndVQ=", Convert.ToBase64String(proof));
        byte[] serverKey = HMACSHA256.HashData(salted, Encoding.ASCII.GetBytes("Server Key"));
        byte[] v = HMACSHA256.HashData(serverKey, auth);
        Assert.Equal("6rriTRBi23WpRR/wtup+mMhUZUn/dB5nLTJRsjl95G4=", Convert.ToBase64String(v));
    }

    [Fact]
    public void Rfc7677AndPlusVectorsOnHost()
    {
        string root = DualMode.FindRoot();
        DualMode.Proc run = DualMode.RunVire(root, new string[] { "pg-scram-plus-prove.vire" }, root);
        Assert.True(run.Code == 0, run.Err + run.Out);
        string norm = DualMode.Norm(run.Out);
        Assert.Contains("RFC7677 client-final PASS", norm);
        Assert.Contains("PLUS client-final p PASS", norm);
        Assert.Contains("PLUS server-signature PASS", norm);
        Assert.Contains("plus-only no bind REJECT", norm);
        Assert.Contains("PG SCRAM PLUS PROVE pass", norm);
    }

    [Fact]
    public void LoopbackPlusOnlyWithoutBindFailsClosed()
    {
        TcpListener listener = new TcpListener(IPAddress.Parse("127.0.0.1"), 0);
        listener.Start();
        int port = ((IPEndPoint)listener.LocalEndpoint).Port;
        string captured = "";
        Thread worker = new Thread(() =>
        {
            try
            {
                using (TcpClient client = listener.AcceptTcpClient())
                using (NetworkStream stream = client.GetStream())
                {
                    stream.ReadTimeout = 5000;
                    byte[] buf = new byte[4096];
                    int n = stream.Read(buf, 0, buf.Length);
                    if (n < 4) return;
                    byte[] sasl = AuthSasl("SCRAM-SHA-256-PLUS");
                    stream.Write(sasl, 0, sasl.Length);
                    try
                    {
                        int m = stream.Read(buf, 0, buf.Length);
                        if (m > 0) captured = Encoding.Latin1.GetString(buf, 0, m);
                    }
                    catch (IOException) { }
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
            string root = DualMode.FindRoot();
            string src = "use \"src/rt-pg.vire\"\n"
                + "define main\n"
                + "  let opened be pg_open with \"127.0.0.1\", " + port + ", \"user\", \"db\", \"pencil\"\n"
                + "  say opened at \"why\"\n"
                + "end\n";
            string work = Path.Combine(root, "pg-scram-plus-loopback-run.vire");
            File.WriteAllText(work, src);
            DualMode.Proc run = DualMode.RunVire(root, new string[] { "pg-scram-plus-loopback-run.vire" }, root);
            Assert.True(run.Code == 0, run.Err + run.Out);
            Assert.Contains("channel binding", DualMode.Norm(run.Out));
            Assert.DoesNotContain("SCRAM-SHA-256", captured);
        }
        finally
        {
            try { listener.Stop(); } catch (Exception) { }
            worker.Join(2000);
            try { File.Delete(Path.Combine(DualMode.FindRoot(), "pg-scram-plus-loopback-run.vire")); } catch (Exception) { }
        }
    }

    [Fact]
    public void LoopbackBothMechsWithoutTlsStaysPlainScram()
    {
        TcpListener listener = new TcpListener(IPAddress.Parse("127.0.0.1"), 0);
        listener.Start();
        int port = ((IPEndPoint)listener.LocalEndpoint).Port;
        string captured = "";
        Thread worker = new Thread(() =>
        {
            try
            {
                using (TcpClient client = listener.AcceptTcpClient())
                using (NetworkStream stream = client.GetStream())
                {
                    stream.ReadTimeout = 8000;
                    byte[] buf = new byte[8192];
                    stream.Read(buf, 0, buf.Length);
                    byte[] sasl = AuthSasl("SCRAM-SHA-256-PLUS", "SCRAM-SHA-256");
                    stream.Write(sasl, 0, sasl.Length);
                    int m = stream.Read(buf, 0, buf.Length);
                    if (m > 0) captured = Encoding.Latin1.GetString(buf, 0, m);
                    byte[] err = AuthFinalError("server-does-support-channel-binding");
                    stream.Write(err, 0, err.Length);
                    try { stream.Read(buf, 0, buf.Length); } catch (IOException) { }
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
            string root = DualMode.FindRoot();
            string src = "use \"src/rt-pg.vire\"\n"
                + "define main\n"
                + "  let opened be pg_open with \"127.0.0.1\", " + port + ", \"user\", \"db\", \"pencil\"\n"
                + "  say opened at \"why\"\n"
                + "end\n";
            string work = Path.Combine(root, "pg-scram-plain-loopback-run.vire");
            File.WriteAllText(work, src);
            DualMode.Proc run = DualMode.RunVire(root, new string[] { "pg-scram-plain-loopback-run.vire" }, root);
            Assert.True(run.Code == 0, run.Err + run.Out);
            Assert.Contains("SCRAM-SHA-256", captured);
            Assert.DoesNotContain("SCRAM-SHA-256-PLUS", captured);
            Assert.Contains("server-does-support-channel-binding", DualMode.Norm(run.Out));
        }
        finally
        {
            try { listener.Stop(); } catch (Exception) { }
            worker.Join(2000);
            try { File.Delete(Path.Combine(DualMode.FindRoot(), "pg-scram-plain-loopback-run.vire")); } catch (Exception) { }
        }
    }
}
