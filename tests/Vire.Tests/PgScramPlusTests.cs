using System;
using System.IO;
using System.Net;
using System.Net.Security;
using System.Net.Sockets;
using System.Security.Authentication;
using System.Security.Cryptography;
using System.Security.Cryptography.X509Certificates;
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
        Assert.Contains("tls plus no bind REJECT", norm);
        Assert.Contains("empty leaf der PASS", norm);
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

    [Fact]
    public void LoopbackTlsPlusBindsHandshakeLeaf()
    {
        RunTlsScram(honest: true);
    }

    [Fact]
    public void LoopbackTlsMitmCertFailsChannelBinding()
    {
        RunTlsScram(honest: false);
    }

    static void RunTlsScram(bool honest)
    {
        using RSA rsa = RSA.Create(2048);
        using RSA mitm = RSA.Create(2048);
        using X509Certificate2 honestCert = MakeLocalCert(rsa);
        using X509Certificate2 mitmCert = MakeLocalCert(mitm);
        X509Certificate2 presented = honest ? honestCert : mitmCert;
        byte[] honestEp = SHA256.HashData(honestCert.RawData);
        byte[] presentedEp = SHA256.HashData(presented.RawData);

        TcpListener listener = new TcpListener(IPAddress.Parse("127.0.0.1"), 0);
        listener.Start();
        int port = ((IPEndPoint)listener.LocalEndpoint).Port;
        string captured = "";
        string clientFinal = "";
        string why = "";
        Thread worker = new Thread(() =>
        {
            try
            {
                using (TcpClient client = listener.AcceptTcpClient())
                using (NetworkStream raw = client.GetStream())
                {
                    raw.ReadTimeout = 8000;
                    raw.WriteTimeout = 8000;
                    byte[] buf = new byte[16384];
                    int n = raw.Read(buf, 0, 8);
                    if (n < 8) return;
                    raw.WriteByte((byte)'S');
                    using (SslStream ssl = new SslStream(raw, false))
                    {
                        ssl.AuthenticateAsServer(new SslServerAuthenticationOptions
                        {
                            ServerCertificate = presented,
                            EnabledSslProtocols = SslProtocols.Tls12 | SslProtocols.Tls13,
                            CertificateRevocationCheckMode = X509RevocationMode.NoCheck
                        });
                        n = ssl.Read(buf, 0, buf.Length);
                        byte[] sasl = AuthSasl("SCRAM-SHA-256-PLUS", "SCRAM-SHA-256");
                        ssl.Write(sasl, 0, sasl.Length);
                        n = ssl.Read(buf, 0, buf.Length);
                        if (n > 0) captured = Encoding.Latin1.GetString(buf, 0, n);
                        int rAt = captured.IndexOf(",r=", StringComparison.Ordinal);
                        if (rAt < 0) return;
                        string cn = captured.Substring(rAt + 3).TrimEnd('\0');
                        int z = cn.IndexOf('\0');
                        if (z >= 0) cn = cn.Substring(0, z);
                        string sn = cn + "s";
                        string sf = "r=" + sn + ",s=W22ZaJ0SNY7soEsUEjb6gQ==,i=2";
                        byte[] cont = AuthContinue(sf);
                        ssl.Write(cont, 0, cont.Length);
                        n = ssl.Read(buf, 0, buf.Length);
                        if (n > 0) clientFinal = Encoding.Latin1.GetString(buf, 0, n);
                        if (!honest)
                        {
                            byte[] err = AuthFinalError("channel binding");
                            ssl.Write(err, 0, err.Length);
                            try { ssl.Read(buf, 0, buf.Length); } catch (IOException) { }
                            return;
                        }
                        int pAt = captured.IndexOf("n=user,r=", StringComparison.Ordinal);
                        string bare = pAt >= 0 ? captured.Substring(pAt).TrimEnd('\0') : "";
                        int comma = clientFinal.LastIndexOf(",p=", StringComparison.Ordinal);
                        string without = "";
                        if (comma > 0)
                        {
                            int cAt = clientFinal.IndexOf("c=", StringComparison.Ordinal);
                            if (cAt >= 0) without = clientFinal.Substring(cAt, comma - cAt);
                        }
                        string v = ServerSig("pencil", "W22ZaJ0SNY7soEsUEjb6gQ==", 2, bare, sf, without);
                        byte[] fin = AuthFinalOk(v);
                        ssl.Write(fin, 0, fin.Length);
                        byte[] ok = AuthOk();
                        ssl.Write(ok, 0, ok.Length);
                        byte[] ready = Ready();
                        ssl.Write(ready, 0, ready.Length);
                        try { ssl.Read(buf, 0, buf.Length); } catch (IOException) { }
                    }
                }
            }
            catch (Exception ex) { why = ex.Message; }
        });
        worker.IsBackground = true;
        worker.Start();
        try
        {
            string root = DualMode.FindRoot();
            string data = Path.Combine(root, "data");
            Directory.CreateDirectory(data);
            string ca = Path.Combine(data, "pg-scram-plus-ca.pem");
            File.WriteAllText(ca, presented.ExportCertificatePem());
            string src = "use \"src/rt-pg.vire\"\n"
                + "define main\n"
                + "  let opened be pg_open_ssl with \"127.0.0.1\", " + port + ", \"user\", \"db\", \"pencil\", \"verify-full\", \"localhost\", \"data/pg-scram-plus-ca.pem\"\n"
                + "  if (opened at \"ok\") == true\n"
                + "    say \"ok\"\n"
                + "    say opened at \"conn\" at \"auth\"\n"
                + "  end\n"
                + "  if (opened at \"ok\") == false\n"
                + "    say opened at \"why\"\n"
                + "  end\n"
                + "end\n";
            string work = Path.Combine(root, "pg-scram-plus-tls-run.vire");
            File.WriteAllText(work, src);
            DualMode.Proc run = DualMode.RunVire(root, new string[] { "pg-scram-plus-tls-run.vire" }, root);
            Assert.True(run.Code == 0, run.Err + run.Out + why);
            Assert.Contains("SCRAM-SHA-256-PLUS", captured);
            Assert.Contains("p=tls-server-end-point", captured);
            string seenB64 = Convert.ToBase64String(ConcatAscii("p=tls-server-end-point,,", presentedEp));
            Assert.Contains(seenB64, clientFinal);
            if (honest)
            {
                Assert.Contains("ok", DualMode.Norm(run.Out));
                Assert.Contains("scram-sha-256-plus", DualMode.Norm(run.Out));
            }
            else
            {
                string honestB64 = Convert.ToBase64String(ConcatAscii("p=tls-server-end-point,,", honestEp));
                Assert.DoesNotContain(honestB64, clientFinal);
                Assert.Contains("channel binding", DualMode.Norm(run.Out));
            }
        }
        finally
        {
            try { listener.Stop(); } catch (Exception) { }
            worker.Join(4000);
            try { File.Delete(Path.Combine(DualMode.FindRoot(), "pg-scram-plus-tls-run.vire")); } catch (Exception) { }
            try { File.Delete(Path.Combine(DualMode.FindRoot(), "data", "pg-scram-plus-ca.pem")); } catch (Exception) { }
        }
    }

    static byte[] AuthContinue(string payload)
    {
        byte[] raw = Encoding.ASCII.GetBytes(payload);
        using (MemoryStream msg = new MemoryStream())
        {
            msg.WriteByte((byte)'R');
            byte[] hdr = Be32(4 + 4 + raw.Length);
            msg.Write(hdr, 0, 4);
            msg.Write(Be32(11), 0, 4);
            msg.Write(raw, 0, raw.Length);
            return msg.ToArray();
        }
    }

    static byte[] AuthFinalOk(string v)
    {
        byte[] payload = Encoding.ASCII.GetBytes("v=" + v);
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

    static byte[] AuthOk()
    {
        using (MemoryStream msg = new MemoryStream())
        {
            msg.WriteByte((byte)'R');
            msg.Write(Be32(8), 0, 4);
            msg.Write(Be32(0), 0, 4);
            return msg.ToArray();
        }
    }

    static byte[] Ready()
    {
        using (MemoryStream msg = new MemoryStream())
        {
            msg.WriteByte((byte)'Z');
            msg.Write(Be32(5), 0, 4);
            msg.WriteByte((byte)'I');
            return msg.ToArray();
        }
    }

    static string ServerSig(string secret, string saltB64, int rounds, string bare, string serverFirst, string without)
    {
        byte[] salt = Convert.FromBase64String(saltB64);
        byte[] salted = Rfc2898DeriveBytes.Pbkdf2(secret, salt, rounds, HashAlgorithmName.SHA256, 32);
        byte[] serverKey = HMACSHA256.HashData(salted, Encoding.ASCII.GetBytes("Server Key"));
        byte[] auth = Encoding.ASCII.GetBytes(bare + "," + serverFirst + "," + without);
        return Convert.ToBase64String(HMACSHA256.HashData(serverKey, auth));
    }

    static byte[] ConcatAscii(string prefix, byte[] ep)
    {
        byte[] a = Encoding.ASCII.GetBytes(prefix);
        byte[] all = new byte[a.Length + ep.Length];
        Buffer.BlockCopy(a, 0, all, 0, a.Length);
        Buffer.BlockCopy(ep, 0, all, a.Length, ep.Length);
        return all;
    }

    static X509Certificate2 MakeLocalCert(RSA rsa)
    {
        CertificateRequest req = new CertificateRequest("CN=localhost", rsa, HashAlgorithmName.SHA256, RSASignaturePadding.Pkcs1);
        SubjectAlternativeNameBuilder san = new SubjectAlternativeNameBuilder();
        san.AddDnsName("localhost");
        san.AddIpAddress(IPAddress.Loopback);
        req.CertificateExtensions.Add(san.Build());
        using (X509Certificate2 cert = req.CreateSelfSigned(DateTimeOffset.UtcNow.AddHours(-1), DateTimeOffset.UtcNow.AddDays(1)))
        {
            byte[] pfx = cert.Export(X509ContentType.Pfx);
            return X509CertificateLoader.LoadPkcs12(pfx, (string)null,
                X509KeyStorageFlags.Exportable | X509KeyStorageFlags.EphemeralKeySet);
        }
    }
}
