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
    public void DecryptWrongKeyTruncatedPackingAndBadKeyLengthFailClosed()
    {
        string goodKey = "00112233445566778899aabbccddeeff00112233445566778899aabbccddeeff";
        string otherKey = "ffeeddccbbaa99887766554433221100ffeeddccbbaa99887766554433221100";
        byte[] key = VireCrypto.FromHex(goodKey, 1, 1);
        byte[] packed = VireCrypto.Seal(key, RandomNumberGenerator.GetBytes(12), Encoding.UTF8.GetBytes("secret"));
        string packedHex = VireCrypto.ToHex(packed);

        DualMode.DualRun wrong = DualMode.RunSource(
            "define main\n  decrypt with \"" + otherKey + "\", \"" + packedHex + "\"\nend\n",
            null);
        Assert.True(wrong.Matched, wrong.InterpErr + wrong.CompErr);
        Assert.Equal(1, wrong.InterpCode);
        Assert.Contains("could not decrypt that message", wrong.InterpErr);

        for (int n = 1; n <= 16; n++)
        {
            byte[] cut = new byte[packed.Length - n];
            Buffer.BlockCopy(packed, 0, cut, 0, cut.Length);
            try
            {
                VireCrypto.Open(key, cut, 1, 1);
                Assert.Fail("truncated packing must not decrypt");
            }
            catch (VireError err)
            {
                Assert.Contains("could not decrypt that message", err.Message);
            }
        }

        DualMode.DualRun shortTag = DualMode.RunSource(
            "define main\n  decrypt with \"" + goodKey + "\", \"" + packedHex.Substring(0, packedHex.Length - 2) + "\"\nend\n",
            null);
        Assert.True(shortTag.Matched, shortTag.InterpErr + shortTag.CompErr);
        Assert.Equal(1, shortTag.InterpCode);
        Assert.Contains("could not decrypt that message", shortTag.InterpErr);

        DualMode.DualRun key31 = DualMode.RunSource(
            "define main\n  encrypt with \"" + goodKey.Substring(0, 62) + "\", \"x\"\nend\n",
            null);
        Assert.True(key31.Matched, key31.InterpErr + key31.CompErr);
        Assert.Equal(1, key31.InterpCode);
        Assert.Contains("encrypt needs a 32-byte hex key", key31.InterpErr);

        DualMode.DualRun key33 = DualMode.RunSource(
            "define main\n  decrypt with \"" + goodKey + "00" + "\", \"" + packedHex + "\"\nend\n",
            null);
        Assert.True(key33.Matched, key33.InterpErr + key33.CompErr);
        Assert.Equal(1, key33.InterpCode);
        Assert.Contains("decrypt needs a 32-byte hex key", key33.InterpErr);
    }

    [Fact]
    public void EncryptUsesFreshNonceEachTimeInBothModes()
    {
        string key = "00112233445566778899aabbccddeeff00112233445566778899aabbccddeeff";
        HashSet<string> packed = new HashSet<string>();
        HashSet<string> nonces = new HashSet<string>();
        for (int i = 0; i < 8; i++)
        {
            object hex = VireCrypto.Builtin("encrypt", new List<object> { key, "hello vire" }, 1, 1);
            string text = (string)hex;
            Assert.True(packed.Add(text));
            Assert.True(nonces.Add(text.Substring(0, 24)));
        }

        DualMode.DualRun both = DualMode.RunSource(string.Join("\n", new string[]
        {
            "define main",
            "  let key be \"" + key + "\"",
            "  let a be encrypt with key, \"hello vire\"",
            "  let b be encrypt with key, \"hello vire\"",
            "  let c be encrypt with key, \"hello vire\"",
            "  let d be encrypt with key, \"hello vire\"",
            "  if a == b",
            "    say \"dup\"",
            "  else if a == c",
            "    say \"dup\"",
            "  else if a == d",
            "    say \"dup\"",
            "  else if b == c",
            "    say \"dup\"",
            "  else if b == d",
            "    say \"dup\"",
            "  else if c == d",
            "    say \"dup\"",
            "  else if (slice with a, 0, 24) == (slice with b, 0, 24)",
            "    say \"nonce\"",
            "  else if (slice with a, 0, 24) == (slice with c, 0, 24)",
            "    say \"nonce\"",
            "  else if (slice with a, 0, 24) == (slice with d, 0, 24)",
            "    say \"nonce\"",
            "  else if (slice with b, 0, 24) == (slice with c, 0, 24)",
            "    say \"nonce\"",
            "  else if (slice with b, 0, 24) == (slice with d, 0, 24)",
            "    say \"nonce\"",
            "  else if (slice with c, 0, 24) == (slice with d, 0, 24)",
            "    say \"nonce\"",
            "  else",
            "    say \"fresh\"",
            "  end",
            "end",
            ""
        }), null);
        Assert.True(both.Matched, both.InterpErr + both.CompErr + both.InterpOut + both.CompOut);
        Assert.Equal(0, both.InterpCode);
        Assert.Equal("fresh\n", DualMode.Norm(both.InterpOut));
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

        DualMode.DualRun closedText = DualMode.RunSource(string.Join("\n", new string[]
        {
            "define main",
            "  let schema be {\"kind\": \"map\", \"closed\": \"true\"}",
            "  parse with \"{}\", schema",
            "end",
            ""
        }), null);
        Assert.True(closedText.Matched, closedText.InterpErr + closedText.CompErr);
        Assert.Equal(1, closedText.InterpCode);
        Assert.Contains("json schema closed must be a bool", closedText.InterpErr);

        DualMode.DualRun keysList = DualMode.RunSource(string.Join("\n", new string[]
        {
            "define main",
            "  let schema be {\"kind\": \"map\", \"keys\": []}",
            "  parse with \"{}\", schema",
            "end",
            ""
        }), null);
        Assert.True(keysList.Matched, keysList.InterpErr + keysList.CompErr);
        Assert.Equal(1, keysList.InterpCode);
        Assert.Contains("json schema keys must be a map", keysList.InterpErr);

        DualMode.DualRun itemsList = DualMode.RunSource(string.Join("\n", new string[]
        {
            "define main",
            "  let schema be {\"kind\": \"list\", \"items\": []}",
            "  parse with \"[]\", schema",
            "end",
            ""
        }), null);
        Assert.True(itemsList.Matched, itemsList.InterpErr + itemsList.CompErr);
        Assert.Equal(1, itemsList.InterpCode);
        Assert.Contains("json schema items must be a map", itemsList.InterpErr);

        DualMode.DualRun unknown = DualMode.RunSource(string.Join("\n", new string[]
        {
            "define main",
            "  let schema be {\"kind\": \"map\", \"requried\": [\"a\"]}",
            "  parse with \"{}\", schema",
            "end",
            ""
        }), null);
        Assert.True(unknown.Matched, unknown.InterpErr + unknown.CompErr);
        Assert.Equal(1, unknown.InterpCode);
        Assert.Contains("json schema has an unknown field", unknown.InterpErr);
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

        DualMode.DualRun dup = DualMode.RunSource(string.Join("\n", new string[]
        {
            "define main",
            "  let q be \"\\\"\"",
            "  parse with (join with [\"{\", q, \"a\", q, \":1,\", q, \"a\", q, \":2}\"], \"\")",
            "end",
            ""
        }), null);
        Assert.True(dup.Matched, dup.InterpErr + dup.CompErr);
        Assert.Equal(1, dup.InterpCode);
        Assert.Contains("json has a duplicate key", dup.InterpErr);

        try
        {
            Json.Read("{\"a\":1,\"a\":2}", 1);
            Assert.Fail("duplicate json keys must be refused");
        }
        catch (VireError err)
        {
            Assert.Contains("json has a duplicate key", err.Message);
        }

        try
        {
            Json.Read(new string('x', Json.MaxChars + 1), 1);
            Assert.Fail("oversized json must be refused");
        }
        catch (VireError err)
        {
            Assert.Contains("json is too large", err.Message);
        }

        StringBuilder items = new StringBuilder();
        items.Append('[');
        for (int i = 0; i < Json.MaxItems + 2; i++)
        {
            if (i > 0) items.Append(',');
            items.Append('0');
        }
        items.Append(']');
        try
        {
            Json.Read(items.ToString(), 1);
            Assert.Fail("oversized json list must be refused");
        }
        catch (VireError err)
        {
            Assert.Contains("json is too large", err.Message);
        }

        object nest = new Dictionary<string, object> { { "kind", "text" } };
        for (int i = 0; i < Json.MaxDepth + 2; i++)
            nest = new Dictionary<string, object> { { "kind", "list" }, { "items", nest } };
        try
        {
            Json.Check(new List<object>(), nest, 1);
            Assert.Fail("oversized schema depth must be refused");
        }
        catch (VireError err)
        {
            Assert.Contains("json is nested too deeply", err.Message);
        }

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

    [Fact]
    public void CryptoKeyBuffersAreZeroedAfterUse()
    {
        byte[] key = new byte[] { 1, 2, 3, 4 };
        int n = VireCrypto.WithZeroedKey(key, k =>
        {
            Assert.Equal(1, k[0]);
            return k.Length;
        });
        Assert.Equal(4, n);
        for (int i = 0; i < key.Length; i++) Assert.Equal(0, key[i]);

        byte[] throwing = new byte[] { 9, 8, 7 };
        try
        {
            VireCrypto.WithZeroedKey<int>(throwing, k => throw new VireError("boom", 1, 1));
            Assert.Fail("key use must throw");
        }
        catch (VireError)
        {
            for (int i = 0; i < throwing.Length; i++) Assert.Equal(0, throwing[i]);
        }
    }

    [Fact]
    public void SharedSchemaDagAndCyclicSchemaFinishFastInBothModes()
    {
        System.Diagnostics.Stopwatch clock = System.Diagnostics.Stopwatch.StartNew();
        DualMode.DualRun dag = DualMode.RunSource(string.Join("\n", new string[]
        {
            "define main",
            "  let s be {\"kind\": \"map\", \"closed\": false}",
            "  let i be 1",
            "  while i <= 64",
            "    let s be {\"kind\": \"map\", \"closed\": false, \"keys\": {\"a\": s, \"b\": s}}",
            "    let i be i + 1",
            "  end",
            "  parse with \"{}\", s",
            "  say \"ok\"",
            "end",
            ""
        }), null);
        Assert.True(clock.ElapsedMilliseconds < 5000, "shared schema dag must finish fast, took " + clock.ElapsedMilliseconds);
        Assert.True(dag.Matched, dag.InterpErr + dag.CompErr + dag.InterpOut + dag.CompOut);
        Assert.Equal(0, dag.InterpCode);
        Assert.Equal("ok\n", DualMode.Norm(dag.InterpOut));

        clock.Restart();
        DualMode.DualRun cycle = DualMode.RunSource(string.Join("\n", new string[]
        {
            "define main",
            "  let keys be {}",
            "  let s be {\"kind\": \"map\", \"closed\": false, \"keys\": keys}",
            "  put s into keys at \"a\"",
            "  parse with \"{}\", s",
            "  say \"lived\"",
            "end",
            ""
        }), null);
        Assert.True(clock.ElapsedMilliseconds < 5000, "cyclic schema must finish fast, took " + clock.ElapsedMilliseconds);
        Assert.True(cycle.Matched, cycle.InterpErr + cycle.CompErr);
        Assert.Equal(1, cycle.InterpCode);
        Assert.Contains("json schema has a cycle", cycle.InterpErr);
        Assert.DoesNotContain("lived", DualMode.Norm(cycle.InterpOut));
    }

    [Fact]
    public void LargeValueAgainstBigNeedListHitsBudgetFastInBothModes()
    {
        StringBuilder row = new StringBuilder();
        row.Append('{');
        for (int k = 1; k <= 500; k++)
        {
            if (k > 1) row.Append(',');
            row.Append('"').Append(k).Append("\":1");
        }
        row.Append('}');
        StringBuilder json = new StringBuilder();
        json.Append('[');
        for (int i = 0; i < 40; i++)
        {
            if (i > 0) json.Append(',');
            json.Append(row);
        }
        json.Append(']');
        System.Diagnostics.Stopwatch clock = System.Diagnostics.Stopwatch.StartNew();
        DualMode.DualRun both = DualMode.RunSource(string.Join("\n", new string[]
        {
            "define main",
            "  let want be []",
            "  let i be 1",
            "  while i <= 500",
            "    push with want, (text with i)",
            "    let i be i + 1",
            "  end",
            "  let schema be {\"kind\": \"list\", \"items\": {\"kind\": \"map\", \"closed\": false, \"need\": want}}",
            "  parse with \"" + json.ToString().Replace("\"", "\\\"") + "\", schema",
            "  say \"lived\"",
            "end",
            ""
        }), null, "12000");
        Assert.True(clock.ElapsedMilliseconds < 5000, "big need list must fail closed quickly, took " + clock.ElapsedMilliseconds);
        Assert.True(both.Matched, both.InterpErr + both.CompErr);
        Assert.Equal(1, both.InterpCode);
        Assert.True(
            both.InterpErr.Contains("program ran too long") || both.InterpErr.Contains("request ran too long"),
            both.InterpErr);
        Assert.DoesNotContain("lived", DualMode.Norm(both.InterpOut));
    }

    [Fact]
    public void BadHexCharacterZerosThePartialKeyBuffer()
    {
        byte[] buf = new byte[] { 0xaa, 0xbb, 0xcc };
        try
        {
            VireCrypto.DecodeHex("00zz00", buf, 1, 1);
            Assert.Fail("damaged hex must throw");
        }
        catch (VireError err)
        {
            Assert.Contains("hex text is damaged", err.Message);
            for (int i = 0; i < buf.Length; i++) Assert.Equal(0, buf[i]);
        }
    }

    [Fact]
    public void LongNeedNamesFailClosedQuicklyInBothModes()
    {
        System.Diagnostics.Stopwatch clock = System.Diagnostics.Stopwatch.StartNew();
        DualMode.DualRun both = DualMode.RunSource(string.Join("\n", new string[]
        {
            "define main",
            "  let n be \"\"",
            "  let i be 1",
            "  while i <= 1025",
            "    let n be n + \"a\"",
            "    let i be i + 1",
            "  end",
            "  let want be []",
            "  let j be 1",
            "  while j <= 200",
            "    push with want, n",
            "    let j be j + 1",
            "  end",
            "  parse with \"{}\", {\"kind\": \"map\", \"closed\": false, \"need\": want}",
            "  say \"lived\"",
            "end",
            ""
        }), null);
        Assert.True(clock.ElapsedMilliseconds < 5000, "long need names must fail closed quickly, took " + clock.ElapsedMilliseconds);
        Assert.True(both.Matched, both.InterpErr + both.CompErr);
        Assert.Equal(1, both.InterpCode);
        Assert.Contains("json schema need name is too long", both.InterpErr);
        Assert.DoesNotContain("lived", DualMode.Norm(both.InterpOut));

        string huge = new string('b', 2000);
        List<object> need = new List<object>();
        for (int i = 0; i < 20000; i++) need.Add(huge);
        Dictionary<string, object> schema = new Dictionary<string, object>
        {
            { "kind", "map" },
            { "closed", false },
            { "need", need }
        };
        Budget budget = new Budget();
        budget.ApplyStepLimit(1000000);
        clock.Restart();
        try
        {
            Json.Check(new Dictionary<string, object>(), schema, 1, budget);
            Assert.Fail("oversized need names must be refused");
        }
        catch (VireError err)
        {
            Assert.True(clock.ElapsedMilliseconds < 5000, "hashed long need names must fail quickly, took " + clock.ElapsedMilliseconds);
            Assert.Contains("json schema need name is too long", err.Message);
        }
    }

    [Fact]
    public void ParseDoesNotRewriteCallerNeedListInBothModes()
    {
        DualMode.DualRun both = DualMode.RunSource(string.Join("\n", new string[]
        {
            "define main",
            "  let schema be {\"kind\": \"map\", \"closed\": false, \"need\": [\"a\", \"a\", \"b\"]}",
            "  parse with (json with {\"a\": 1, \"b\": 2}), schema",
            "  say length with (schema at \"need\")",
            "end",
            ""
        }), null);
        Assert.True(both.Matched, both.InterpErr + both.CompErr + both.InterpOut);
        Assert.Equal(0, both.InterpCode);
        Assert.Equal("3\n", DualMode.Norm(both.InterpOut));

        List<object> need = new List<object> { "a", "a", "b" };
        Dictionary<string, object> schema = new Dictionary<string, object>
        {
            { "kind", "map" },
            { "closed", false },
            { "need", need }
        };
        Dictionary<string, object> value = new Dictionary<string, object> { { "a", 1 }, { "b", 2 } };
        Json.Check(value, schema, 1);
        Assert.Same(need, schema["need"]);
        Assert.Equal(3, need.Count);
        Assert.Equal("a", (string)need[0]);
        Assert.Equal("a", (string)need[1]);
        Assert.Equal("b", (string)need[2]);
    }
}
