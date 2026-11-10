using System;
using System.Globalization;
using System.IO;
using Xunit;

public class NativePeEmitTests
{
    [Fact]
    public void HostCompileOfInternCharsEmits32MbAndInternTable()
    {
        string root = DualMode.FindRoot();
        string work = Path.Combine(root, "data", "native-pe-emit", Guid.NewGuid().ToString("N"));
        Directory.CreateDirectory(work);
        try
        {
            File.Copy(
                Path.Combine(root, "tests", "native", "intern-chars.vire"),
                Path.Combine(work, "intern-chars.vire"));
            string srcRel = ("data/native-pe-emit/" + Path.GetFileName(work) + "/intern-chars.vire").Replace('\\', '/');
            string hexRel = ("data/native-pe-emit/" + Path.GetFileName(work) + "/intern-chars.hex").Replace('\\', '/');
            DualMode.Proc compiled = DualMode.RunVire(root, new string[] { "compile-native.vire", srcRel, hexRel }, root);
            Assert.Equal(0, compiled.Code);
            Assert.Contains("compiled", DualMode.Norm(compiled.Out));
            string hex = File.ReadAllText(Path.Combine(root, hexRel.Replace('/', Path.DirectorySeparatorChar))).Trim();
            byte[] pe = new byte[hex.Length / 2];
            for (int i = 0; i < pe.Length; i++)
                pe[i] = byte.Parse(hex.Substring(i * 2, 2), NumberStyles.HexNumber, CultureInfo.InvariantCulture);
            int e = BitConverter.ToInt32(pe, 0x3c);
            int oh = e + 24;
            Assert.Equal(0x20b, BitConverter.ToUInt16(pe, oh));
            Assert.Equal((ushort)3, BitConverter.ToUInt16(pe, e + 6));
            Assert.NotEqual(0u, BitConverter.ToUInt32(pe, e + 8));
            Assert.NotEqual(0u, BitConverter.ToUInt32(pe, oh + 64));
            Assert.Equal(1048576UL, BitConverter.ToUInt64(pe, oh + 0x48));
            Assert.Equal(1048576UL, BitConverter.ToUInt64(pe, oh + 0x58));
            Assert.Equal((ushort)0x8120, BitConverter.ToUInt16(pe, oh + 70));
            uint textChars = BitConverter.ToUInt32(pe, 432 + 36);
            uint dataChars = BitConverter.ToUInt32(pe, 472 + 36);
            Assert.Equal(0x60000020u, textChars);
            Assert.Equal(0xC0000040u, dataChars);
            Assert.Equal(0, (int)(textChars & 0x80000000));
            Assert.True(IndexOf(pe, new byte[] { 0xBA, 0x00, 0x00, 0x00, 0x02 }) >= 0);
            Assert.True(IndexOf(pe, new byte[] { 0xBA, 0x00, 0x00, 0x00, 0x10 }) < 0);
            Assert.True(IndexOf(pe, new byte[] { 0x49, 0x8D, 0x87, 0x00, 0x10, 0x00, 0x00 }) < 0);
            Assert.True(IndexOf(pe, new byte[] { 0x49, 0x8D, 0x97, 0x00, 0x10, 0x00, 0x00 }) < 0);
            Assert.True(IndexOf(pe, new byte[] { 0x4D, 0x89, 0xFA }) < 0);
            Assert.True(IndexOf(pe, new byte[] { 0x81, 0xF9, 0x80, 0x00, 0x00, 0x00 }) >= 0);
            Assert.True(IndexOf(pe, new byte[] { 0x4C, 0x8B, 0x15 }) >= 0);
            int intern = IndexOf(pe, new byte[] { 1, 0, 0, 0, 0, 0, 0, 0, (byte)'A', 0, 0, 0, 0, 0, 0, 0 });
            Assert.True(intern >= 0);
        }
        finally
        {
            try { Directory.Delete(work, true); } catch (IOException) { }
        }
    }

    static int IndexOf(byte[] hay, byte[] needle)
    {
        for (int i = 0; i <= hay.Length - needle.Length; i++)
        {
            int j = 0;
            while (j < needle.Length && hay[i + j] == needle[j]) j++;
            if (j == needle.Length) return i;
        }
        return -1;
    }
}
