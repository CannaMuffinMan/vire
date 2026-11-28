using System;

static class Program
{
    static int Main(string[] args)
    {
        if (args.Length < 1)
        {
            Console.Error.WriteLine("usage: vire-proof <write-pem|write-pfx|write-pfx-expired|https-health|tls10-fail|tls-echo|pg-tls-stub|pg-tls-n|pg-stub|redis-tls-stub|remainder-run|remainder-pair|dns-stub|http-upok|http-echo|ws-upstream|ws-prove> ...");
            return 2;
        }
        try
        {
            string cmd = args[0];
            if (cmd == "write-pem") { ProofTls.WritePem(args[1], args[2]); return 0; }
            if (cmd == "write-pfx") { ProofTls.WritePfx(args[1], args[2], args.Length > 3 ? args[3] : "", false, args.Length > 4 ? args[4] : "sha256"); return 0; }
            if (cmd == "write-pfx-expired") { ProofTls.WritePfx(args[1], args[2], args.Length > 3 ? args[3] : "", true, args.Length > 4 ? args[4] : "sha256"); return 0; }
            if (cmd == "https-health") { Console.Write(ProofTls.HttpsHealth(int.Parse(args[1]), args[2])); return 0; }
            if (cmd == "tls10-fail") { ProofTls.Tls10MustFail(int.Parse(args[1])); return 0; }
            if (cmd == "tls-echo") return ProofTls.TlsEcho(args[1], args.Length > 2 ? args[2] : "");
            if (cmd == "pg-tls-stub") return ProofPg.TlsStub(args[1], args.Length > 2 ? args[2] : "", args.Length > 3 ? args[3] : "honest");
            if (cmd == "pg-tls-n") return ProofPg.PlainN();
            if (cmd == "pg-stub") return ProofPg.Stub(args.Length > 1 ? args[1] : "x");
            if (cmd == "redis-tls-stub") return ProofRedis.TlsStub(args[1], args[2], args[3], args.Length > 4 ? args[4] : "");
            if (cmd == "remainder-run") return ProofRemainder.Run(int.Parse(args[1]), args[2], args[3], args[4]);
            if (cmd == "remainder-pair") return ProofRemainder.Pair(int.Parse(args[1]), int.Parse(args[2]), args[3], args[4]);
            if (cmd == "dns-stub") return ProofNet.DnsStub(args[1]);
            if (cmd == "http-upok") return ProofNet.HttpUpOk();
            if (cmd == "http-echo") return ProofNet.HttpEcho();
            if (cmd == "ws-upstream") return ProofNet.WsUpstream();
            if (cmd == "ws-prove") return ProofNet.WsProve(int.Parse(args[1]));
            Console.Error.WriteLine("unknown command " + cmd);
            return 2;
        }
        catch (Exception ex)
        {
            Console.Error.WriteLine(ex.GetType().Name + ": " + ex.Message);
            return 1;
        }
    }
}
