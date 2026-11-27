using System;
using System.Collections.Generic;
using System.IO;
using System.Net.Sockets;
using System.Security.Cryptography;
using System.Text;
using System.Text.Json;
using System.Threading;

static class ProofRemainder
{
    static readonly Dictionary<string, string> Hdr = new Dictionary<string, string>
    {
        { "content-type", "application/json" },
        { "connection", "close" },
        { "x-content-type-options", "nosniff" },
        { "cache-control", "no-store" }
    };

    static string Js(object value)
    {
        return JsonSerializer.Serialize(value);
    }

    static string ProofOf(int index, string previous, string text)
    {
        string row = "[" + index + "," + Js(previous) + "," + Js(text) + "]";
        return Convert.ToHexString(SHA256.HashData(Encoding.UTF8.GetBytes(row))).ToLowerInvariant();
    }

    static string BlockJson(int index, string previous, string text)
    {
        string proof = ProofOf(index, previous, text);
        return "{\"index\":" + index + ",\"previous\":" + Js(previous) + ",\"proof\":" + Js(proof) + ",\"text\":" + Js(text) + "}";
    }

    static int ExtraLen(int index, string previous, string text)
    {
        return Encoding.UTF8.GetByteCount(BlockJson(index, previous, text));
    }

    static (int Status, Dictionary<string, string> Headers, string Body) HttpReq(int port, string method, string path, string bodySend, int timeout = 30)
    {
        byte[] payload = bodySend == null ? Array.Empty<byte>() : Encoding.UTF8.GetBytes(bodySend);
        StringBuilder lines = new StringBuilder();
        lines.Append(method).Append(' ').Append(path).Append(" HTTP/1.1\r\nHost: 127.0.0.1\r\nConnection: close\r\n");
        if (method == "POST")
        {
            lines.Append("Content-Type: application/json\r\nContent-Length: ").Append(payload.Length).Append("\r\n");
            string tok = Environment.GetEnvironmentVariable("FCG_BLOCK_TOKEN");
            if (!string.IsNullOrEmpty(tok) && tok.Length >= 16)
                lines.Append("Authorization: Bearer ").Append(tok).Append("\r\n");
        }
        lines.Append("\r\n");
        byte[] head = Encoding.ASCII.GetBytes(lines.ToString());
        byte[] req = new byte[head.Length + payload.Length];
        Buffer.BlockCopy(head, 0, req, 0, head.Length);
        if (payload.Length > 0) Buffer.BlockCopy(payload, 0, req, head.Length, payload.Length);
        Exception last = null;
        for (int attempt = 0; attempt < 8; attempt++)
        {
            try
            {
                using (TcpClient tcp = new TcpClient())
                {
                    tcp.ReceiveTimeout = timeout * 1000;
                    tcp.SendTimeout = timeout * 1000;
                    tcp.Connect("127.0.0.1", port);
                    NetworkStream stream = tcp.GetStream();
                    stream.Write(req, 0, req.Length);
                    MemoryStream ms = new MemoryStream();
                    byte[] buf = new byte[65536];
                    try
                    {
                        int n;
                        while ((n = stream.Read(buf, 0, buf.Length)) > 0) ms.Write(buf, 0, n);
                    }
                    catch (IOException) { }
                    catch (SocketException) { }
                    byte[] raw = ms.ToArray();
                    string text = Encoding.UTF8.GetString(raw);
                    int split = text.IndexOf("\r\n\r\n", StringComparison.Ordinal);
                    int add = 4;
                    if (split < 0)
                    {
                        split = text.IndexOf("\n\n", StringComparison.Ordinal);
                        add = 2;
                    }
                    if (split < 0)
                    {
                        Console.Error.WriteLine("remainder_http_raw " + text.Replace("\r", "\\r").Replace("\n", "\\n"));
                        return (0, new Dictionary<string, string>(), text);
                    }
                    string headText = text.Substring(0, split);
                    string body = text.Substring(split + add);
                    string[] hl = headText.Split(new string[] { "\r\n", "\n" }, StringSplitOptions.None);
                    int status = int.Parse(hl[0].Split(' ')[1]);
                    Dictionary<string, string> headers = new Dictionary<string, string>();
                    for (int i = 1; i < hl.Length; i++)
                    {
                        int c = hl[i].IndexOf(':');
                        if (c < 0) continue;
                        headers[hl[i].Substring(0, c).Trim().ToLowerInvariant()] = hl[i].Substring(c + 1).Trim();
                    }
                    return (status, headers, body);
                }
            }
            catch (SocketException ex)
            {
                last = ex;
                Thread.Sleep(40 * (attempt + 1));
            }
        }
        throw last ?? new IOException("remainder connect failed");
    }

    static readonly UTF8Encoding Utf8 = new UTF8Encoding(false);

    static void WriteUtf8(string path, string text)
    {
        File.WriteAllBytes(path, Utf8.GetBytes(text ?? ""));
    }

    static void RestoreGenesis(string fixSrc, string fixDst)
    {
        for (int i = 0; i < 12; i++)
        {
            try
            {
                if (Directory.Exists(fixDst)) Directory.Delete(fixDst, true);
                break;
            }
            catch (IOException)
            {
                Thread.Sleep(40);
            }
        }
        Directory.CreateDirectory(fixDst);
        foreach (string name in new string[] { "head.json", "000001.json", "blocks.json" })
        {
            string src = Path.Combine(fixSrc, name);
            if (File.Exists(src)) File.Copy(src, Path.Combine(fixDst, name), true);
        }
        if (File.Exists("data/chain.json")) File.Delete("data/chain.json");
    }

    static void WriteSeg(string dir, int n, string link, List<string> blocks)
    {
        StringBuilder sb = new StringBuilder();
        sb.Append("{\"link\":").Append(Js(link)).Append(",\"blocks\":[");
        for (int i = 0; i < blocks.Count; i++)
        {
            if (i > 0) sb.Append(',');
            sb.Append(blocks[i]);
        }
        sb.Append("]}");
        WriteUtf8(Path.Combine(dir, n.ToString("000000") + ".json"), sb.ToString());
    }

    static void WriteHead(string dir, int segment, int index, string proof)
    {
        WriteUtf8(Path.Combine(dir, "head.json"),
            "{\"segment\":" + segment + ",\"index\":" + index + ",\"proof\":" + Js(proof) + "}");
    }

    static (int Index, string Proof, string Chunk) BuildNearRotate(string dir)
    {
        string genesis = BlockJson(0, "0", "");
        List<string> blocks = new List<string> { genesis };
        string previous = ProofOf(0, "0", "");
        int index = 1;
        string chunk = new string('a', 4000);
        string link = "0";
        while (true)
        {
            int extra = ExtraLen(index, previous, chunk);
            WriteSeg(dir, 1, link, blocks);
            int raw = (int)new FileInfo(Path.Combine(dir, "000001.json")).Length;
            if (raw + extra + 2 > 524288) break;
            string b = BlockJson(index, previous, chunk);
            blocks.Add(b);
            previous = ProofOf(index, previous, chunk);
            index++;
        }
        WriteSeg(dir, 1, link, blocks);
        WriteHead(dir, 1, index - 1, previous);
        return (index - 1, previous, chunk);
    }

    static void BuildFull64(string dir)
    {
        string previous = "0";
        int index = 0;
        for (int seg = 1; seg <= 64; seg++)
        {
            string link = previous;
            List<string> blocks = new List<string>();
            if (seg < 64)
            {
                string b = BlockJson(index, previous, "s" + seg);
                blocks.Add(b);
                previous = ProofOf(index, previous, "s" + seg);
                index++;
            }
            else
            {
                while (true)
                {
                    string text = new string('z', 4000);
                    int extra = ExtraLen(index, previous, text);
                    int raw = Encoding.UTF8.GetByteCount("{\"link\":" + Js(link) + ",\"blocks\":[" + string.Join(",", blocks) + "]}");
                    if (blocks.Count > 0 && raw + extra + 2 > 524288) break;
                    string b = BlockJson(index, previous, text);
                    blocks.Add(b);
                    previous = ProofOf(index, previous, text);
                    index++;
                    int raw2 = Encoding.UTF8.GetByteCount("{\"link\":" + Js(link) + ",\"blocks\":[" + string.Join(",", blocks) + "]}");
                    if (raw2 >= 524288) break;
                }
            }
            WriteSeg(dir, seg, link, blocks);
        }
        WriteHead(dir, 64, index - 1, previous);
    }

    static void CheckHeaders(Dictionary<string, string> headers, string name, List<string> mismatches)
    {
        foreach (KeyValuePair<string, string> kv in Hdr)
        {
            string g;
            if (!headers.TryGetValue(kv.Key, out g)) g = "";
            if (!string.Equals(g, kv.Value, StringComparison.OrdinalIgnoreCase))
                mismatches.Add(name + " header " + kv.Key + " got " + g + " want " + kv.Value);
        }
    }

    public static int Run(int port, string fixSrc, string fixDst, string mode)
    {
        List<string> mismatches = new List<string>();
        RestoreGenesis(fixSrc, fixDst);
        var first = HttpReq(port, "POST", "/block", "{\"text\":\"keep\"}");
        string seg = Path.Combine(fixDst, "000001.json");
        string raw = File.Exists(seg) ? File.ReadAllText(seg) : "";
        if (mode != "fail-before")
        {
            if (first.Status != 200) mismatches.Add("tamper setup post got " + first.Status + " " + first.Body);
            if (!raw.Contains("keep")) mismatches.Add("tamper setup missing keep in segment");
            else WriteUtf8(seg, raw.Replace("keep", "tamper"));
        }
        else if (raw.Contains("keep")) WriteUtf8(seg, raw.Replace("keep", "tamper"));
        else if (File.Exists(seg)) WriteUtf8(seg, raw.Replace("\"text\":\"\"", "\"text\":\"tamper\"", StringComparison.Ordinal));
        var tamp = HttpReq(port, "POST", "/block", "{\"text\":\"more\"}");
        string want = "{\"ok\":false,\"status\":503,\"error\":\"chain invalid\"}";
        if (mode == "fail-before")
        {
            if (tamp.Status == 503 && tamp.Body == want) mismatches.Add("FAIL_BEFORE tamper unexpectedly matched 503");
        }
        else
        {
            if (tamp.Status != 503 || tamp.Body != want) mismatches.Add("post_block_tamper_503 got " + tamp.Status + " " + tamp.Body);
            CheckHeaders(tamp.Headers, "post_block_tamper_503", mismatches);
            var ch = HttpReq(port, "GET", "/chain", null);
            if (ch.Status != 503 || ch.Body != want) mismatches.Add("get_chain_tamper_503 got " + ch.Status + " " + ch.Body);
            CheckHeaders(ch.Headers, "get_chain_tamper_503", mismatches);
        }
        Console.WriteLine("case tamper POST status " + tamp.Status + " body " + tamp.Body);

        if (mode != "fail-before")
        {
            RestoreGenesis(fixSrc, fixDst);
            BuildFull64(fixDst);
            string overflow = new string('z', 4000);
            var full = HttpReq(port, "POST", "/block", "{\"text\":" + Js(overflow) + "}");
            string want507 = "{\"ok\":false,\"status\":507,\"error\":\"chain full\"}";
            if (full.Status != 507 || full.Body != want507) mismatches.Add("post_block_full_507 got " + full.Status + " " + full.Body);
            CheckHeaders(full.Headers, "post_block_full_507", mismatches);
            Console.WriteLine("case 507 status " + full.Status + " body " + full.Body);
        }

        RestoreGenesis(fixSrc, fixDst);
        var last = BuildNearRotate(fixDst);
        var rot = HttpReq(port, "POST", "/block", "{\"text\":" + Js(last.Chunk) + "}");
        if (mode == "fail-before")
        {
            if (File.Exists(Path.Combine(fixDst, "000002.json")) && rot.Status == 200)
                mismatches.Add("FAIL_BEFORE rotate unexpectedly created 000002.json");
        }
        else
        {
            if (rot.Status != 200) mismatches.Add("post_block_rotate_512k status " + rot.Status + " " + rot.Body);
            if (!File.Exists(Path.Combine(fixDst, "000002.json"))) mismatches.Add("post_block_rotate_512k missing 000002.json");
            foreach (string p in Directory.GetFiles(fixDst, "*.json"))
            {
                string name = Path.GetFileName(p);
                if (name == "head.json" || name == "blocks.json") continue;
                if (new FileInfo(p).Length > 524288) mismatches.Add(name + " is " + new FileInfo(p).Length);
            }
            int wantIndex = last.Index + 1;
            string wantProof = ProofOf(wantIndex, last.Proof, last.Chunk);
            string wantBody = "{\"ok\":true,\"accepted\":true,\"index\":" + wantIndex + ",\"proof\":" + Js(wantProof) + "}";
            if (rot.Body != wantBody) mismatches.Add("post_block_rotate_512k body got " + rot.Body + " want " + wantBody);
            CheckHeaders(rot.Headers, "post_block_rotate_512k", mismatches);
        }
        Console.WriteLine("case rotate status " + rot.Status + " body " + (rot.Body.Length > 120 ? rot.Body.Substring(0, 120) : rot.Body));

        if (mode == "fail-before")
        {
            if (mismatches.Count > 0)
            {
                Console.WriteLine("REMAINDER_FAIL_BEFORE_UNEXPECTED");
                foreach (string m in mismatches) Console.WriteLine(m);
                return 4;
            }
            Console.WriteLine("REMAINDER_FAIL_BEFORE_MISMATCH");
            return 2;
        }

        if (Directory.Exists(fixDst)) Directory.Delete(fixDst, true);
        Directory.CreateDirectory(fixDst);
        string old = "[{\"index\":0,\"previousHash\":\"0\",\"text\":\"\"},{\"index\":1,\"previousHash\":" + Js(ProofOf(0, "0", "")) + ",\"text\":\"migrated\"}]";
        Directory.CreateDirectory("data");
        WriteUtf8("data/chain.json", old);
        var mig = HttpReq(port, "GET", "/chain", null);
        string b0 = BlockJson(0, "0", "");
        string b1 = BlockJson(1, ProofOf(0, "0", ""), "migrated");
        string wantMig = "[" + b0 + "," + b1 + "]";
        if (mig.Status != 200 || mig.Body != wantMig) mismatches.Add("get_chain_migrate_old got " + mig.Status + " " + mig.Body + " want " + wantMig);
        CheckHeaders(mig.Headers, "get_chain_migrate_old", mismatches);
        if (!File.Exists(Path.Combine(fixDst, "000001.json"))) mismatches.Add("migrate missing 000001.json");
        if (!File.Exists(Path.Combine(fixDst, "head.json"))) mismatches.Add("migrate missing head.json");
        Console.WriteLine("case migrate status " + mig.Status + " body " + (mig.Body.Length > 160 ? mig.Body.Substring(0, 160) : mig.Body));

        RestoreGenesis(fixSrc, fixDst);
        int npost = 8;
        object[] results = new object[npost];
        Thread[] threads = new Thread[npost];
        for (int i = 0; i < npost; i++)
        {
            int idx = i;
            threads[i] = new Thread(() =>
            {
                try { results[idx] = HttpReq(port, "POST", "/block", "{\"text\":\"c" + idx + "\"}", 60); }
                catch (Exception ex) { results[idx] = ex; }
            });
            threads[i].Start();
        }
        foreach (Thread t in threads) t.Join(60000);
        List<int> indexes = new List<int>();
        for (int i = 0; i < npost; i++)
        {
            if (results[i] == null || results[i] is Exception)
            {
                mismatches.Add("concurrent post " + i + " failed " + results[i]);
                continue;
            }
            var r = ((int Status, Dictionary<string, string> Headers, string Body))results[i];
            if (r.Status != 200)
            {
                mismatches.Add("concurrent post " + i + " status " + r.Status + " " + r.Body);
                continue;
            }
            int at = r.Body.IndexOf("\"index\":", StringComparison.Ordinal);
            int end = at + 8;
            while (end < r.Body.Length && char.IsDigit(r.Body[end])) end++;
            indexes.Add(int.Parse(r.Body.Substring(at + 8, end - at - 8)));
        }
        indexes.Sort();
        List<int> wantIdx = new List<int>();
        for (int i = 1; i <= npost; i++) wantIdx.Add(i);
        if (string.Join(",", indexes) != string.Join(",", wantIdx))
            mismatches.Add("concurrent indexes " + string.Join(",", indexes));
        var chain = HttpReq(port, "GET", "/chain", null);
        if (chain.Status != 200) mismatches.Add("concurrent GET /chain " + chain.Status + " " + chain.Body);
        else
        {
            using (JsonDocument doc = JsonDocument.Parse(chain.Body))
            {
                if (doc.RootElement.GetArrayLength() != npost + 1)
                    mismatches.Add("concurrent chain len " + doc.RootElement.GetArrayLength());
            }
        }
        Console.WriteLine("case concurrent indexes " + string.Join(",", indexes));
        if (mismatches.Count > 0)
        {
            Console.WriteLine("REMAINDER_MISMATCH");
            foreach (string m in mismatches) Console.WriteLine(m);
            return 2;
        }
        Console.WriteLine("REMAINDER_MATCH");
        return 0;
    }

    public static int Pair(int hostPort, int nativePort, string fixSrc, string fixDst)
    {
        List<string> mismatches = new List<string>();
        RestoreGenesis(fixSrc, fixDst);
        BuildFull64(fixDst);
        string overflow = new string('z', 4000);
        var hs = HttpReq(hostPort, "POST", "/block", "{\"text\":" + Js(overflow) + "}");
        RestoreGenesis(fixSrc, fixDst);
        BuildFull64(fixDst);
        var ns = HttpReq(nativePort, "POST", "/block", "{\"text\":" + Js(overflow) + "}");
        if (hs.Status != ns.Status || hs.Body != ns.Body) mismatches.Add("507 host " + hs.Status + " " + hs.Body + " native " + ns.Status + " " + ns.Body);
        else Console.WriteLine("pair remainder 507 host " + hs.Status + " native " + ns.Status);

        RestoreGenesis(fixSrc, fixDst);
        var last = BuildNearRotate(fixDst);
        hs = HttpReq(hostPort, "POST", "/block", "{\"text\":" + Js(last.Chunk) + "}");
        RestoreGenesis(fixSrc, fixDst);
        BuildNearRotate(fixDst);
        ns = HttpReq(nativePort, "POST", "/block", "{\"text\":" + Js(last.Chunk) + "}");
        if (hs.Status != ns.Status || hs.Body != ns.Body) mismatches.Add("rotate host " + hs.Status + " " + hs.Body + " native " + ns.Status + " " + ns.Body);
        else Console.WriteLine("pair remainder rotate host " + hs.Status + " native " + ns.Status);

        Action mig = () =>
        {
            if (Directory.Exists(fixDst)) Directory.Delete(fixDst, true);
            Directory.CreateDirectory(fixDst);
            string old = "[{\"index\":0,\"previousHash\":\"0\",\"text\":\"\"},{\"index\":1,\"previousHash\":" + Js(ProofOf(0, "0", "")) + ",\"text\":\"migrated\"}]";
            WriteUtf8("data/chain.json", old);
        };
        mig();
        hs = HttpReq(hostPort, "GET", "/chain", null);
        mig();
        ns = HttpReq(nativePort, "GET", "/chain", null);
        if (hs.Status != ns.Status || hs.Body != ns.Body) mismatches.Add("migrate host " + hs.Status + " " + hs.Body + " native " + ns.Status + " " + ns.Body);
        else Console.WriteLine("pair remainder migrate host " + hs.Status + " native " + ns.Status);

        RestoreGenesis(fixSrc, fixDst);
        HttpReq(hostPort, "POST", "/block", "{\"text\":\"keep\"}");
        string raw = File.ReadAllText(Path.Combine(fixDst, "000001.json"));
        WriteUtf8(Path.Combine(fixDst, "000001.json"), raw.Replace("keep", "tamper"));
        hs = HttpReq(hostPort, "POST", "/block", "{\"text\":\"more\"}");
        RestoreGenesis(fixSrc, fixDst);
        HttpReq(nativePort, "POST", "/block", "{\"text\":\"keep\"}");
        raw = File.ReadAllText(Path.Combine(fixDst, "000001.json"));
        WriteUtf8(Path.Combine(fixDst, "000001.json"), raw.Replace("keep", "tamper"));
        ns = HttpReq(nativePort, "POST", "/block", "{\"text\":\"more\"}");
        if (hs.Status != ns.Status || hs.Body != ns.Body) mismatches.Add("tamper host " + hs.Status + " " + hs.Body + " native " + ns.Status + " " + ns.Body);
        else Console.WriteLine("pair remainder tamper host " + hs.Status + " native " + ns.Status);

        if (mismatches.Count > 0)
        {
            Console.WriteLine("HOST_NATIVE_REMAINDER_MISMATCH");
            foreach (string m in mismatches) Console.WriteLine(m);
            return 3;
        }
        Console.WriteLine("HOST_NATIVE_REMAINDER_MATCH");
        return 0;
    }
}
