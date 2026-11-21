using System;

static class Program
{
    static int Main(string[] args)
    {
        if (args.Length < 1)
        {
            Console.Error.WriteLine("usage: vire-proof <write-pem|write-pfx|https-health|tls10-fail|tls-echo|remainder-run|remainder-pair> ...");
            return 2;
        }
        try
        {
            string cmd = args[0];
            if (cmd == "write-pem") { ProofTls.WritePem(args[1], args[2]); return 0; }
            if (cmd == "write-pfx") { ProofTls.WritePfx(args[1], args[2], args.Length > 3 ? args[3] : ""); return 0; }
            if (cmd == "https-health") { Console.Write(ProofTls.HttpsHealth(int.Parse(args[1]), args[2])); return 0; }
            if (cmd == "tls10-fail") { ProofTls.Tls10MustFail(int.Parse(args[1])); return 0; }
            if (cmd == "tls-echo") return ProofTls.TlsEcho(args[1], args.Length > 2 ? args[2] : "");
            if (cmd == "remainder-run") return ProofRemainder.Run(int.Parse(args[1]), args[2], args[3], args[4]);
            if (cmd == "remainder-pair") return ProofRemainder.Pair(int.Parse(args[1]), int.Parse(args[2]), args[3], args[4]);
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
