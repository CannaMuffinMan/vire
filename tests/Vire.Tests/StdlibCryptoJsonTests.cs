using System;
using System.Collections.Generic;
using System.Security.Cryptography;
using System.Text;
using Xunit;

public class StdlibCryptoJsonTests
{
    const string Rfc4231Case1Key = "0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b";
    const string Rfc4231Case1Mac = "b0344c61d8db38535ca8afceaf0bf12b881dc200c9833da726e9376c2e32cff7";
    const string Rfc4231Case2Key = "4a656665";
    const string Rfc4231Case2Mac = "5bdcc146bf60754e6a042426089575c75a003f089d2739839dec58b964ec3843";
    const string Rfc4231Case3Key = "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa";
    const string Rfc4231Case3MacFull = "773ea91e36800e46854db8ebd09181a72959098b3ef8c122d9635514ced565fe";

    const string NistZeroKey = "0000000000000000000000000000000000000000000000000000000000000000";
    const string NistZeroNonce = "000000000000000000000000";
    const string NistEmptyTag = "530f8afbc74536b9a963b4f1c4cb738b";
    const string NistBlockPlain = "00000000000000000000000000000000";
    const string NistBlockCipher = "cea7403d4d606b6e074ec5d3baf39d18";
    const string NistBlockTag = "d0d1c8a799996bf0265b98b5d48ab919";

    [Fact]
    public void HmacRfc4231KnownAnswersMatchInBothModes()
    {
        DualMode.DualRun one = DualMode.RunSource(
            "define main\n  say hmac with \"" + Rfc4231Case1Key + "\", \"Hi There\"\nend\n", null);
        Assert.True(one.Matched, one.InterpErr + one.CompErr + one.InterpOut + one.CompOut);
        Assert.Equal(0, one.InterpCode);
        Assert.Equal(Rfc4231Case1Mac + "\n", DualMode.Norm(one.InterpOut));

        DualMode.DualRun two = DualMode.RunSource(
            "define main\n  say hmac with \"" + Rfc4231Case2Key + "\", \"what do ya want for nothing?\"\nend\n", null);
        Assert.True(two.Matched, two.InterpErr + two.CompErr);
        Assert.Equal(Rfc4231Case2Mac + "\n", DualMode.Norm(two.InterpOut));

        byte[] dd = new byte[50];
        for (int i = 0; i < dd.Length; i++) dd[i] = 0xdd;
        Assert.Equal(Rfc4231Case3MacFull, VireCrypto.HmacHex(VireCrypto.FromHex(Rfc4231Case3Key, 1, 1), dd));
        Assert.Equal(Rfc4231Case1Mac, VireCrypto.HmacHex(VireCrypto.FromHex(Rfc4231Case1Key, 1, 1), Encoding.UTF8.GetBytes("Hi There")));
    }

    [Fact]
    public void AesGcmNistKnownAnswersDecrypt()
    {
        byte[] key = VireCrypto.FromHex(NistZeroKey, 1, 1);
        byte[] emptyPacked = VireCrypto.FromHex(NistZeroNonce + NistEmptyTag, 1, 1);
        byte[] empty = VireCrypto.Open(key, emptyPacked, 1, 1);
        Assert.Empty(empty);

        byte[] blockPacked = VireCrypto.FromHex(NistZeroNonce + NistBlockCipher + NistBlockTag, 1, 1);
        byte[] block = VireCrypto.Open(key, blockPacked, 1, 1);
        Assert.Equal(NistBlockPlain, VireCrypto.ToHex(block));

        byte[] resealed = VireCrypto.Seal(key, VireCrypto.FromHex(NistZeroNonce, 1, 1), VireCrypto.FromHex(NistBlockPlain, 1, 1));
        Assert.Equal(NistZeroNonce + NistBlockCipher + NistBlockTag, VireCrypto.ToHex(resealed));
    }

    [Fact]
    public void EncryptDecryptRoundtripMatchesInBothModes()
    {
        string key = "00112233445566778899aabbccddeeff00112233445566778899aabbccddeeff";
        DualMode.DualRun both = DualMode.RunSource(
            "define main\n  let packed be encrypt with \"" + key + "\", \"hello vire\"\n  say decrypt with \"" + key + "\", packed\nend\n",
            null);
        Assert.True(both.Matched, both.InterpOut + both.CompOut + both.InterpErr + both.CompErr);
        Assert.Equal(0, both.InterpCode);
        Assert.Equal("hello vire\n", DualMode.Norm(both.InterpOut));
    }

    [Fact]
    public void TamperedCiphertextFailsClosedSeeded()
    {
        byte[] key = VireCrypto.FromHex("00112233445566778899aabbccddeeff00112233445566778899aabbccddeeff", 1, 1);
        byte[] nonce = RandomNumberGenerator.GetBytes(12);
        byte[] packed = VireCrypto.Seal(key, nonce, Encoding.UTF8.GetBytes("secret"));
        Random rng = new Random(20261030);
        int hits = 0;
        for (int i = 0; i < 64; i++)
        {
            byte[] dirty = (byte[])packed.Clone();
            dirty[rng.Next(dirty.Length)] ^= (byte)(1 + rng.Next(255));
            try
            {
                VireCrypto.Open(key, dirty, 1, 1);
            }
            catch (VireError err)
            {
                Assert.Contains("could not decrypt", err.Message);
                hits++;
            }
        }
        Assert.Equal(64, hits);

        string hex = VireCrypto.ToHex(packed);
        char[] chars = hex.ToCharArray();
        chars[hex.Length - 2] = chars[hex.Length - 2] == '0' ? '1' : '0';
        DualMode.DualRun both = DualMode.RunSource(
            "define main\n  decrypt with \"00112233445566778899aabbccddeeff00112233445566778899aabbccddeeff\", \"" + new string(chars) + "\"\nend\n",
            null);
        Assert.True(both.Matched, both.InterpErr + both.CompErr);
        Assert.Equal(1, both.InterpCode);
        Assert.Contains("could not decrypt that message", both.InterpErr);
    }

    [Fact]
    public void RandomAndTokenAreBoundedHexAndUrl()
    {
        DualMode.DualRun rnd = DualMode.RunSource("define main\n  say length with (random with 16)\nend\n", null);
        Assert.True(rnd.Matched, rnd.InterpOut + rnd.CompOut + rnd.InterpErr);
        Assert.Equal("32\n", DualMode.Norm(rnd.InterpOut));

        DualMode.DualRun tok = DualMode.RunSource("define main\n  say length with (token with 16)\nend\n", null);
        Assert.True(tok.Matched, tok.InterpErr + tok.CompErr);
        Assert.Equal("22\n", DualMode.Norm(tok.InterpOut));
    }

    [Fact]
    public void SamebytesIsConstantTimeCompareInBothModes()
    {
        DualMode.DualRun both = DualMode.RunSource(
            "define main\n  say samebytes with \"abc\", \"abc\"\n  say samebytes with \"abc\", \"abd\"\n  say samebytes with \"ab\", \"abc\"\nend\n",
            null);
        Assert.True(both.Matched, both.InterpOut + both.CompOut + both.InterpErr);
        Assert.Equal("true\nfalse\nfalse\n", DualMode.Norm(both.InterpOut));
    }

    [Fact]
    public void ParseSchemaRejectsWrongMissingAndExtra()
    {
        DualMode.DualRun good = DualMode.RunSource(string.Join("\n", new string[]
        {
            "define main",
            "  let schema be {\"kind\": \"map\", \"closed\": true, \"need\": [\"title\"], \"keys\": {\"title\": {\"kind\": \"text\"}, \"done\": {\"kind\": \"bool\"}}}",
            "  let value be parse with (json with {\"title\": \"hi\", \"done\": true}), schema",
            "  say value at \"title\"",
            "end",
            ""
        }), null);
        Assert.True(good.Matched, good.InterpOut + good.CompOut + good.InterpErr + good.CompErr);
        Assert.Equal(0, good.InterpCode);
        Assert.Equal("hi\n", DualMode.Norm(good.InterpOut));

        DualMode.DualRun extra = DualMode.RunSource(string.Join("\n", new string[]
        {
            "define main",
            "  let schema be {\"kind\": \"map\", \"closed\": true, \"need\": [\"title\"], \"keys\": {\"title\": {\"kind\": \"text\"}}}",
            "  parse with (json with {\"title\": \"hi\", \"nope\": 1}), schema",
            "end",
            ""
        }), null);
        Assert.True(extra.Matched, extra.InterpErr + extra.CompErr);
        Assert.Equal(1, extra.InterpCode);
        Assert.Contains("json has an extra key", extra.InterpErr);

        DualMode.DualRun missing = DualMode.RunSource(string.Join("\n", new string[]
        {
            "define main",
            "  let schema be {\"kind\": \"map\", \"closed\": true, \"need\": [\"title\"], \"keys\": {\"title\": {\"kind\": \"text\"}}}",
            "  parse with \"{}\", schema",
            "end",
            ""
        }), null);
        Assert.True(missing.Matched, missing.InterpErr);
        Assert.Equal(1, missing.InterpCode);
        Assert.Contains("json is missing a required key", missing.InterpErr);

        DualMode.DualRun wrong = DualMode.RunSource(string.Join("\n", new string[]
        {
            "define main",
            "  let schema be {\"kind\": \"map\", \"closed\": false, \"keys\": {\"title\": {\"kind\": \"text\"}}}",
            "  parse with (json with {\"title\": 9}), schema",
            "end",
            ""
        }), null);
        Assert.True(wrong.Matched, wrong.InterpErr);
        Assert.Equal(1, wrong.InterpCode);
        Assert.Contains("json has the wrong type", wrong.InterpErr);
    }

    [Fact]
    public void ParseLimitsAndSeededFuzzFailClosed()
    {
        DualMode.DualRun deep = DualMode.RunSource(
            "define main\n  parse with \"" + new string('[', 300) + new string(']', 300) + "\"\nend\n",
            null);
        Assert.True(deep.Matched, deep.InterpErr + deep.CompErr);
        Assert.Equal(1, deep.InterpCode);
        Assert.Contains("json is nested too deeply", deep.InterpErr);

        Random rng = new Random(20261030);
        int closed = 0;
        for (int i = 0; i < 80; i++)
        {
            string junk = Mutate(rng);
            try
            {
                Json.Read(junk, 1);
                closed++;
            }
            catch (VireError)
            {
                closed++;
            }
        }
        Assert.Equal(80, closed);
    }

    static string Mutate(Random rng)
    {
        string[] seeds = { "{}", "[]", "true", "null", "1", "\"hi\"", "{\"a\":[1,2,true]}" };
        char[] chars = seeds[rng.Next(seeds.Length)].ToCharArray();
        int n = 1 + rng.Next(8);
        List<char> body = new List<char>(chars);
        for (int i = 0; i < n; i++)
        {
            int op = rng.Next(4);
            if (body.Count == 0) body.Add((char)(32 + rng.Next(90)));
            else if (op == 0) body[rng.Next(body.Count)] = (char)(32 + rng.Next(90));
            else if (op == 1) body.Insert(rng.Next(body.Count + 1), (char)(32 + rng.Next(90)));
            else if (op == 2) body.RemoveAt(rng.Next(body.Count));
            else body.Add((char)rng.Next(128));
        }
        return new string(body.ToArray());
    }
}
