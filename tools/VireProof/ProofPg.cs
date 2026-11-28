using System;
using System.Collections.Generic;
using System.IO;
using System.Net;
using System.Net.Security;
using System.Net.Sockets;
using System.Security.Authentication;
using System.Security.Cryptography;
using System.Security.Cryptography.X509Certificates;
using System.Text;
using System.Threading;

static class ProofPg
{
    static byte[] Be32(int n)
    {
        return new byte[] { (byte)(n >> 24), (byte)(n >> 16), (byte)(n >> 8), (byte)n };
    }

    static byte[] AuthSasl()
    {
        return AuthSaslMechs(true);
    }

    static byte[] AuthSaslPlainOnly()
    {
        return AuthSaslMechs(false);
    }

    static byte[] AuthSaslMechs(bool plus)
    {
        byte[] plusName = Encoding.ASCII.GetBytes("SCRAM-SHA-256-PLUS");
        byte[] plain = Encoding.ASCII.GetBytes("SCRAM-SHA-256");
        using (MemoryStream body = new MemoryStream())
        {
            body.Write(Be32(10), 0, 4);
            if (plus)
            {
                body.Write(plusName, 0, plusName.Length);
                body.WriteByte(0);
            }
            body.Write(plain, 0, plain.Length);
            body.WriteByte(0);
            body.WriteByte(0);
            byte[] payload = body.ToArray();
            using (MemoryStream msg = new MemoryStream())
            {
                msg.WriteByte((byte)'R');
                msg.Write(Be32(payload.Length + 4), 0, 4);
                msg.Write(payload, 0, payload.Length);
                return msg.ToArray();
            }
        }
    }

    static byte[] AuthContinue(string payload)
    {
        byte[] raw = Encoding.ASCII.GetBytes(payload);
        using (MemoryStream msg = new MemoryStream())
        {
            msg.WriteByte((byte)'R');
            msg.Write(Be32(4 + 4 + raw.Length), 0, 4);
            msg.Write(Be32(11), 0, 4);
            msg.Write(raw, 0, raw.Length);
            return msg.ToArray();
        }
    }

    static byte[] AuthFinalError(string e)
    {
        byte[] payload = Encoding.ASCII.GetBytes("e=" + e);
        using (MemoryStream msg = new MemoryStream())
        {
            msg.WriteByte((byte)'R');
            msg.Write(Be32(4 + 4 + payload.Length), 0, 4);
            msg.Write(Be32(12), 0, 4);
            msg.Write(payload, 0, payload.Length);
            return msg.ToArray();
        }
    }

    static byte[] AuthFinalOk(string v)
    {
        byte[] payload = Encoding.ASCII.GetBytes("v=" + v);
        using (MemoryStream msg = new MemoryStream())
        {
            msg.WriteByte((byte)'R');
            msg.Write(Be32(4 + 4 + payload.Length), 0, 4);
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

    public static int TlsStub(string pfxPath, string password, string mode)
    {
        bool mitm = mode == "mitm";
        X509Certificate2 cert = X509CertificateLoader.LoadPkcs12FromFile(pfxPath, password);
        TcpListener l = new TcpListener(IPAddress.Loopback, 0);
        l.Start();
        int port = ((IPEndPoint)l.LocalEndpoint).Port;
        Console.WriteLine("listening on 127.0.0.1:" + port);
        Console.Out.Flush();
        while (true)
        {
            TcpClient c = l.AcceptTcpClient();
            Thread inner = new Thread(() => Serve(c, cert, mitm, password));
            inner.IsBackground = true;
            inner.Start();
        }
    }

    static void Serve(TcpClient c, X509Certificate2 cert, bool mitm, string secret)
    {
        try
        {
            using (c)
            using (NetworkStream raw = c.GetStream())
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
                        ServerCertificate = cert,
                        EnabledSslProtocols = SslProtocols.Tls12 | SslProtocols.Tls13,
                        CertificateRevocationCheckMode = X509RevocationMode.NoCheck
                    });
                    ssl.Read(buf, 0, buf.Length);
                    byte[] sasl = AuthSasl();
                    ssl.Write(sasl, 0, sasl.Length);
                    n = ssl.Read(buf, 0, buf.Length);
                    if (n < 1) return;
                    string captured = Encoding.Latin1.GetString(buf, 0, n);
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
                    if (n < 1) return;
                    string clientFinal = Encoding.Latin1.GetString(buf, 0, n);
                    if (mitm)
                    {
                        byte[] err = AuthFinalError("channel binding");
                        ssl.Write(err, 0, err.Length);
                        try { ssl.Read(buf, 0, buf.Length); } catch (IOException) { }
                        return;
                    }
                    int pAt = captured.IndexOf("n=", StringComparison.Ordinal);
                    string bare = "";
                    if (pAt >= 0)
                    {
                        bare = captured.Substring(pAt).TrimEnd('\0');
                        int z2 = bare.IndexOf('\0');
                        if (z2 >= 0) bare = bare.Substring(0, z2);
                    }
                    int comma = clientFinal.LastIndexOf(",p=", StringComparison.Ordinal);
                    string without = "";
                    if (comma > 0)
                    {
                        int cAt = clientFinal.IndexOf("c=", StringComparison.Ordinal);
                        if (cAt >= 0) without = clientFinal.Substring(cAt, comma - cAt);
                    }
                    string v = ServerSig(secret, "W22ZaJ0SNY7soEsUEjb6gQ==", 2, bare, sf, without);
                    byte[] fin = AuthFinalOk(v);
                    ssl.Write(fin, 0, fin.Length);
                    byte[] ok = AuthOk();
                    ssl.Write(ok, 0, ok.Length);
                    byte[] ready = Ready();
                    ssl.Write(ready, 0, ready.Length);
                    while (true)
                    {
                        int kind = ssl.ReadByte();
                        if (kind < 0) return;
                        byte[] hdr = new byte[4];
                        if (!ReadExact(ssl, hdr, 4)) return;
                        int mlen = ReadBe32(hdr, 0);
                        if (mlen < 4 || mlen > 1000000) return;
                        byte[] body = new byte[mlen - 4];
                        if (body.Length > 0 && !ReadExact(ssl, body, body.Length)) return;
                        if (kind == (int)'Q') WriteQuery(ssl, CString(body));
                    }
                }
            }
        }
        catch (Exception) { }
    }

    public static int Stub(string secret)
    {
        TcpListener l = new TcpListener(IPAddress.Loopback, 0);
        l.Start();
        int port = ((IPEndPoint)l.LocalEndpoint).Port;
        Console.WriteLine("listening on 127.0.0.1:" + port);
        Console.Out.Flush();
        while (true)
        {
            TcpClient c = l.AcceptTcpClient();
            string hold = secret;
            Thread inner = new Thread(() => ServePlain(c, hold));
            inner.IsBackground = true;
            inner.Start();
        }
    }

    class PgState
    {
        public List<string> T = new List<string>();
        public List<string[]> U = new List<string[]>();
        public List<string[]> USnap;
        public string Parsed = "";
        public List<string> Bound = new List<string>();
    }

    static void ServePlain(TcpClient c, string secret)
    {
        try
        {
            using (c)
            using (NetworkStream s = c.GetStream())
            {
                s.ReadTimeout = 8000;
                s.WriteTimeout = 8000;
                byte[] lenb = new byte[4];
                if (!ReadExact(s, lenb, 4)) return;
                int slen = ReadBe32(lenb, 0);
                if (slen < 8 || slen > 1000000) return;
                byte[] rest = new byte[slen - 4];
                if (!ReadExact(s, rest, rest.Length)) return;
                WriteAll(s, AuthSaslPlainOnly());
                byte[] buf = new byte[16384];
                int n = s.Read(buf, 0, buf.Length);
                if (n < 1) return;
                string captured = Encoding.Latin1.GetString(buf, 0, n);
                int rAt = captured.IndexOf(",r=", StringComparison.Ordinal);
                if (rAt < 0) return;
                string cn = captured.Substring(rAt + 3).TrimEnd('\0');
                int z = cn.IndexOf('\0');
                if (z >= 0) cn = cn.Substring(0, z);
                string sn = cn + "s";
                string sf = "r=" + sn + ",s=W22ZaJ0SNY7soEsUEjb6gQ==,i=2";
                byte[] cont = AuthContinue(sf);
                s.Write(cont, 0, cont.Length);
                n = s.Read(buf, 0, buf.Length);
                if (n < 1) return;
                string clientFinal = Encoding.Latin1.GetString(buf, 0, n);
                int pAt = captured.IndexOf("n=", StringComparison.Ordinal);
                string bare = "";
                if (pAt >= 0)
                {
                    bare = captured.Substring(pAt).TrimEnd('\0');
                    int z2 = bare.IndexOf('\0');
                    if (z2 >= 0) bare = bare.Substring(0, z2);
                }
                int comma = clientFinal.LastIndexOf(",p=", StringComparison.Ordinal);
                string without = "";
                if (comma > 0)
                {
                    int cAt = clientFinal.IndexOf("c=", StringComparison.Ordinal);
                    if (cAt >= 0) without = clientFinal.Substring(cAt, comma - cAt);
                }
                string v = ServerSig(secret, "W22ZaJ0SNY7soEsUEjb6gQ==", 2, bare, sf, without);
                byte[] fin = AuthFinalOk(v);
                s.Write(fin, 0, fin.Length);
                byte[] ok = AuthOk();
                s.Write(ok, 0, ok.Length);
                byte[] ready = Ready();
                s.Write(ready, 0, ready.Length);
                PgState st = new PgState();
                while (true)
                {
                    int kind = s.ReadByte();
                    if (kind < 0) return;
                    byte[] hdr = new byte[4];
                    if (!ReadExact(s, hdr, 4)) return;
                    int mlen = ReadBe32(hdr, 0);
                    if (mlen < 4 || mlen > 1000000) return;
                    byte[] body = new byte[mlen - 4];
                    if (body.Length > 0 && !ReadExact(s, body, body.Length)) return;
                    if (kind == (int)'Q')
                    {
                        ApplySql(s, st, CString(body), null, true);
                    }
                    else if (kind == (int)'P')
                    {
                        int q0 = 0;
                        while (q0 < body.Length && body[q0] != 0) q0++;
                        q0++;
                        st.Parsed = CString(Slice(body, q0, body.Length - q0));
                        WriteMsg(s, (byte)'1', new byte[0]);
                    }
                    else if (kind == (int)'B')
                    {
                        st.Bound = ParseBind(body);
                        WriteMsg(s, (byte)'2', new byte[0]);
                    }
                    else if (kind == (int)'E')
                    {
                        ApplySql(s, st, st.Parsed, st.Bound, false);
                    }
                    else if (kind == (int)'S')
                    {
                        WriteAll(s, ReadyMsg());
                    }
                }
            }
        }
        catch (Exception) { }
    }

    static byte[] Slice(byte[] b, int i, int n)
    {
        if (i < 0) i = 0;
        if (n < 0) n = 0;
        if (i + n > b.Length) n = b.Length - i;
        if (n < 0) n = 0;
        byte[] o = new byte[n];
        Array.Copy(b, i, o, 0, n);
        return o;
    }

    static List<string> ParseBind(byte[] body)
    {
        List<string> args = new List<string>();
        int i = 0;
        while (i < body.Length && body[i] != 0) i++;
        i++;
        while (i < body.Length && body[i] != 0) i++;
        i++;
        if (i + 2 > body.Length) return args;
        i += 2;
        if (i + 2 > body.Length) return args;
        int nparams = (body[i] << 8) | body[i + 1];
        i += 2;
        int p = 0;
        while (p < nparams && i + 4 <= body.Length)
        {
            int ln = ReadBe32(body, i);
            i += 4;
            if (ln < 0)
            {
                args.Add(null);
            }
            else
            {
                if (i + ln > body.Length) break;
                args.Add(Encoding.UTF8.GetString(body, i, ln));
                i += ln;
            }
            p++;
        }
        return args;
    }

    static void ApplySql(Stream s, PgState st, string sql, List<string> bound, bool ready)
    {
        string q = sql == null ? "" : sql.Trim();
        if (q.EndsWith(";")) q = q.Substring(0, q.Length - 1).Trim();
        string uq = q.ToUpperInvariant();
        if (uq == "SELECT 1")
        {
            WriteRow(s, new int[] { 23 }, new string[] { "1" }, ready);
            return;
        }
        if (uq.StartsWith("SELECT 1::INT4"))
        {
            WriteRow(s, new int[] { 23, 16, 25 }, new string[] { "1", "t", null }, ready);
            return;
        }
        if (uq.StartsWith("CREATE TEMP TABLE T"))
        {
            st.T.Clear();
            WriteCmd(s, "CREATE TABLE", ready);
            return;
        }
        if (uq.StartsWith("INSERT INTO T VALUES"))
        {
            st.T.Add("7");
            WriteCmd(s, "INSERT 0 1", ready);
            return;
        }
        if (uq == "SELECT N FROM T")
        {
            string v = st.T.Count > 0 ? st.T[0] : "";
            WriteRow(s, new int[] { 23 }, new string[] { v }, ready);
            return;
        }
        if (uq == "SELECT FROM")
        {
            WriteError(s, "42601", "syntax error", ready);
            return;
        }
        if (uq.StartsWith("CREATE TEMP TABLE U"))
        {
            st.U.Clear();
            WriteCmd(s, "CREATE TABLE", ready);
            return;
        }
        if (uq.StartsWith("INSERT INTO U"))
        {
            string nval = bound != null && bound.Count > 0 ? bound[0] : "";
            string kval = bound != null && bound.Count > 1 ? bound[1] : "0";
            st.U.Add(new string[] { nval, kval });
            WriteCmd(s, "INSERT 0 1", ready);
            return;
        }
        if (uq == "SELECT N FROM U")
        {
            string v = st.U.Count > 0 ? st.U[0][0] : "";
            WriteRow(s, new int[] { 25 }, new string[] { v }, ready);
            return;
        }
        if (uq.StartsWith("SELECT COUNT(*) FROM U"))
        {
            WriteRow(s, new int[] { 20 }, new string[] { st.U.Count.ToString() }, ready);
            return;
        }
        if (uq == "BEGIN")
        {
            st.USnap = new List<string[]>(st.U);
            WriteCmd(s, "BEGIN", ready);
            return;
        }
        if (uq == "ROLLBACK")
        {
            if (st.USnap != null) st.U = new List<string[]>(st.USnap);
            st.USnap = null;
            WriteCmd(s, "ROLLBACK", ready);
            return;
        }
        if (uq == "COMMIT")
        {
            st.USnap = null;
            WriteCmd(s, "COMMIT", ready);
            return;
        }
        WriteError(s, "42601", "syntax error", ready);
    }

    static void WriteCmd(Stream s, string tag, bool ready)
    {
        WriteMsg(s, (byte)'C', Encoding.ASCII.GetBytes(tag + "\0"));
        if (ready) WriteAll(s, ReadyMsg());
    }

    static void WriteError(Stream s, string code, string msg, bool ready)
    {
        MemoryStream e = new MemoryStream();
        e.WriteByte((byte)'S');
        WriteC(e, "ERROR");
        e.WriteByte((byte)'C');
        WriteC(e, code);
        e.WriteByte((byte)'M');
        WriteC(e, msg);
        e.WriteByte(0);
        WriteMsg(s, (byte)'E', e.ToArray());
        if (ready) WriteAll(s, ReadyMsg());
    }

    static void WriteC(Stream s, string t)
    {
        byte[] b = Encoding.UTF8.GetBytes(t);
        s.Write(b, 0, b.Length);
        s.WriteByte(0);
    }

    static void WriteRow(Stream s, int[] oids, string[] cells, bool ready)
    {
        MemoryStream rd = new MemoryStream();
        WriteBe16(rd, oids.Length);
        for (int i = 0; i < oids.Length; i++)
        {
            byte[] name = Encoding.ASCII.GetBytes("?column?\0");
            rd.Write(name, 0, name.Length);
            WriteBe32(rd, 0);
            WriteBe16(rd, 0);
            WriteBe32(rd, oids[i]);
            WriteBe16(rd, -1);
            WriteBe32(rd, -1);
            WriteBe16(rd, 0);
        }
        WriteMsg(s, (byte)'T', rd.ToArray());
        MemoryStream dr = new MemoryStream();
        WriteBe16(dr, cells.Length);
        for (int i = 0; i < cells.Length; i++)
        {
            if (cells[i] == null)
            {
                WriteBe32(dr, -1);
            }
            else
            {
                byte[] cell = Encoding.UTF8.GetBytes(cells[i]);
                WriteBe32(dr, cell.Length);
                dr.Write(cell, 0, cell.Length);
            }
        }
        WriteMsg(s, (byte)'D', dr.ToArray());
        WriteMsg(s, (byte)'C', Encoding.ASCII.GetBytes("SELECT 1\0"));
        if (ready) WriteAll(s, ReadyMsg());
    }

    public static int PlainN()
    {
        TcpListener l = new TcpListener(IPAddress.Loopback, 0);
        l.Start();
        int port = ((IPEndPoint)l.LocalEndpoint).Port;
        Console.WriteLine("listening on 127.0.0.1:" + port);
        Console.Out.Flush();
        while (true)
        {
            TcpClient c = l.AcceptTcpClient();
            Thread inner = new Thread(() =>
            {
                try
                {
                    using (c)
                    {
                        NetworkStream s = c.GetStream();
                        byte[] req = new byte[8];
                        if (!ReadExact(s, req, 8)) return;
                        s.WriteByte((byte)'N');
                        s.Flush();
                    }
                }
                catch (Exception) { }
            });
            inner.IsBackground = true;
            inner.Start();
        }
    }

    static void WriteQuery(Stream s, string sql)
    {
        string text = "1";
        if (sql.IndexOf("42", StringComparison.Ordinal) >= 0) text = "42";
        if (sql.IndexOf("SELECT", StringComparison.OrdinalIgnoreCase) < 0) text = "";
        byte[] name = Encoding.ASCII.GetBytes("?column?\0");
        MemoryStream rd = new MemoryStream();
        WriteBe16(rd, 1);
        rd.Write(name, 0, name.Length);
        WriteBe32(rd, 0);
        WriteBe16(rd, 0);
        WriteBe32(rd, 25);
        WriteBe16(rd, 65535);
        WriteBe32(rd, -1);
        WriteBe16(rd, 0);
        WriteMsg(s, (byte)'T', rd.ToArray());
        byte[] cell = Encoding.ASCII.GetBytes(text);
        MemoryStream dr = new MemoryStream();
        WriteBe16(dr, 1);
        WriteBe32(dr, cell.Length);
        dr.Write(cell, 0, cell.Length);
        WriteMsg(s, (byte)'D', dr.ToArray());
        byte[] cc = Encoding.ASCII.GetBytes("SELECT 1\0");
        WriteMsg(s, (byte)'C', cc);
        WriteAll(s, ReadyMsg());
    }

    static byte[] ReadyMsg()
    {
        return Msg((byte)'Z', new byte[] { (byte)'I' });
    }

    static byte[] Msg(byte kind, byte[] body)
    {
        MemoryStream ms = new MemoryStream();
        ms.WriteByte(kind);
        WriteBe32(ms, body.Length + 4);
        ms.Write(body, 0, body.Length);
        return ms.ToArray();
    }

    static void WriteMsg(Stream s, byte kind, byte[] body)
    {
        WriteAll(s, Msg(kind, body));
    }

    static void WriteAll(Stream s, byte[] raw)
    {
        s.Write(raw, 0, raw.Length);
        s.Flush();
    }

    static void WriteBe16(Stream s, int n)
    {
        s.WriteByte((byte)((n >> 8) & 255));
        s.WriteByte((byte)(n & 255));
    }

    static void WriteBe32(Stream s, int n)
    {
        s.WriteByte((byte)((n >> 24) & 255));
        s.WriteByte((byte)((n >> 16) & 255));
        s.WriteByte((byte)((n >> 8) & 255));
        s.WriteByte((byte)(n & 255));
    }

    static int ReadBe32(byte[] b, int i)
    {
        return (b[i] << 24) | (b[i + 1] << 16) | (b[i + 2] << 8) | b[i + 3];
    }

    static string CString(byte[] body)
    {
        int n = body.Length;
        if (n > 0 && body[n - 1] == 0) n--;
        return Encoding.ASCII.GetString(body, 0, n);
    }

    static bool ReadExact(Stream s, byte[] buf, int n)
    {
        int off = 0;
        while (off < n)
        {
            int got = s.Read(buf, off, n - off);
            if (got <= 0) return false;
            off += got;
        }
        return true;
    }
}
