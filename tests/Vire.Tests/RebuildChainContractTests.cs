using System.IO;
using System.Security.Cryptography;
using System.Text;
using System.Text.Json;
using Xunit;

public class RebuildChainContractTests
{
    [Fact]
    public void RecordedChainContractsMatchGuestAndFixtures()
    {
        string root = DualMode.FindRoot();
        string guest = File.ReadAllText(Path.Combine(root, "guest-chain.vire"));
        string fail = File.ReadAllText(Path.Combine(root, "tests", "rebuild", "fail-before-chain.vire"));
        string api = File.ReadAllText(Path.Combine(root, "api", "fcgcpa.vire"));
        Assert.Contains("previousHash", guest);
        Assert.Contains("chain full", guest);
        Assert.Contains("chain invalid", guest);
        Assert.Contains("524288", guest);
        Assert.Contains("hash with (json with row)", api);
        Assert.Contains("path == \"/chain\"", guest);
        Assert.Contains("path == \"/block\"", guest);
        Assert.Contains("method == \"POST\"", guest);
        Assert.Contains("bad block", guest);
        Assert.DoesNotContain("fixture-one", fail);
        Assert.DoesNotContain("makeProof", fail);

        string head = File.ReadAllText(Path.Combine(root, "data", "rebuild", "chain", "head.json")).Trim();
        string seg = File.ReadAllText(Path.Combine(root, "data", "rebuild", "chain", "000001.json")).Trim();
        string blocks = File.ReadAllText(Path.Combine(root, "data", "rebuild", "chain", "blocks.json"));
        Assert.False(blocks.EndsWith("\n"));
        Assert.Contains("a9df21e6e7672bdb9cea28047aa39ba0fa96d54ae0791a9bab30078f5a2d4fad", head);
        Assert.Contains("a9df21e6e7672bdb9cea28047aa39ba0fa96d54ae0791a9bab30078f5a2d4fad", seg);
        Assert.Contains("a9df21e6e7672bdb9cea28047aa39ba0fa96d54ae0791a9bab30078f5a2d4fad", blocks);
        Assert.DoesNotContain("forevercouchgang", head);
        Assert.DoesNotContain("forevercouchgang", seg);

        string genesisRow = "[0,\"0\",\"\"]";
        string genesisHash = Sha256Hex(genesisRow);
        Assert.Equal("a9df21e6e7672bdb9cea28047aa39ba0fa96d54ae0791a9bab30078f5a2d4fad", genesisHash);

        string json = File.ReadAllText(Path.Combine(root, "tests", "rebuild", "contracts", "fcg-chain.json"));
        using JsonDocument doc = JsonDocument.Parse(json);
        int n = 0;
        foreach (JsonElement c in doc.RootElement.GetProperty("cases").EnumerateArray())
        {
            n++;
            string name = c.GetProperty("name").GetString();
            int status = c.GetProperty("status").GetInt32();
            string body = c.GetProperty("body").GetString();
            if (name == "get_chain_genesis")
            {
                Assert.Equal(200, status);
                Assert.Contains(genesisHash, body);
            }
            if (name.StartsWith("post_block") && name != "post_block_accept_fixture_one" && name != "post_block_previousHash_ok")
                Assert.Equal(400, status);
            if (name == "post_block_accept_fixture_one" || name == "post_block_previousHash_ok")
            {
                Assert.Equal(200, status);
                string wantProof = Sha256Hex("[1,\"" + genesisHash + "\",\"fixture-one\"]");
                Assert.Contains(wantProof, body);
            }
        }
        Assert.True(n >= 9);
        Assert.True(File.Exists(Path.Combine(root, "tools", "rebuild-chain-diff.sh")));
        Assert.True(File.Exists(Path.Combine(root, "tools", "rebuild-chain-tamper.sh")));
        Assert.True(File.Exists(Path.Combine(root, "tools", "rebuild-chain-remainder.py")));
        Assert.True(File.Exists(Path.Combine(root, "tools", "rebuild-fcgcpa-windows.ps1")));
        Assert.True(File.Exists(Path.Combine(root, "tests", "rebuild", "fail-before-chain-remainder.vire")));
        Assert.True(File.Exists(Path.Combine(root, "tests", "rebuild", "contracts", "fcg-chain-remainder.json")));
    }

    static string Sha256Hex(string text)
    {
        byte[] bytes = SHA256.HashData(Encoding.UTF8.GetBytes(text));
        StringBuilder sb = new StringBuilder(bytes.Length * 2);
        for (int i = 0; i < bytes.Length; i++) sb.Append(bytes[i].ToString("x2"));
        return sb.ToString();
    }
}
