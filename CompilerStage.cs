using System.IO;

static class CompilerStage
{
    public static readonly string[] Files =
    {
        "compile-native.vire",
        "src/asm.vire",
        "src/pe.vire",
        "src/rt.vire",
        "src/rt-more.vire",
        "src/rt-net.vire",
        "src/rt-ws.vire",
        "src/rt-dns.vire",
        "src/elf.vire",
        "src/rt-linux.vire",
        "src/rt-tls.vire",
        "src/rt-tls-pe.vire",
        "src/rt-tls-pe-blob.txt",
        "src/rt-tls-pe-pins.txt",
        "src/rt-tls-pe-fixes.txt",
        "src/rt-crypto.vire",
        "src/rt-net-blob.txt",
        "src/rt-net-pins.txt",
        "src/rt-net-fixes.txt",
        "src/rt-net-json-blob.txt",
        "src/rt-net-json-pins.txt",
        "src/rt-net-json-fixes.txt",
        "src/rt-net-r4-blob.txt",
        "src/rt-net-r4-pins.txt",
        "src/rt-net-r4-fixes.txt"
    };

    public static void CopyToData(string root)
    {
        Directory.CreateDirectory(Path.Combine(root, "data", "src"));
        for (int i = 0; i < Files.Length; i++)
        {
            string rel = Files[i].Replace('/', Path.DirectorySeparatorChar);
            string from = Path.Combine(root, rel);
            string toRel = Files[i] == "compile-native.vire"
                ? Path.Combine("data", "compile-native.vire")
                : Path.Combine("data", rel);
            string to = Path.Combine(root, toRel);
            Directory.CreateDirectory(Path.GetDirectoryName(to));
            File.Copy(from, to, true);
        }
    }
}
