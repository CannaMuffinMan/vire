using System;
using System.Security.Cryptography;
using System.Text;

static class VireCrypto
{
    public const int MaxPlain = 1000000;
    public const int MaxRandom = 4096;
    public const int MinToken = 16;
    public const int MaxToken = 64;
    public const int KeySize = 32;
    public const int NonceSize = 12;
    public const int TagSize = 16;
    public const int MaxHmacKey = 256;

    public static object Builtin(string name, System.Collections.Generic.List<object> args, int line, int col)
    {
        if (name == "random")
        {
            Need(args, 1, name, line, col);
            int n = Count(args[0], 1, MaxRandom, "random needs a whole number from 1 to 4096", line, col);
            return ToHex(RandomNumberGenerator.GetBytes(n));
        }
        if (name == "token")
        {
            Need(args, 1, name, line, col);
            int n = Count(args[0], MinToken, MaxToken, "token needs a whole number from 16 to 64", line, col);
            return ToUrl(RandomNumberGenerator.GetBytes(n));
        }
        if (name == "hmac")
        {
            Need(args, 2, name, line, col);
            byte[] key = HexBytes(args[0], 1, MaxHmacKey, "hmac key must be hex", line, col);
            return WithZeroedKey(key, k =>
            {
                string message = args[1] as string;
                if (message == null) throw new VireError("hmac needs text", line, col);
                if (message.Length > MaxPlain) throw new VireError("text is too large", line, col);
                using (HMACSHA256 hmac = new HMACSHA256(k))
                    return (object)ToHex(hmac.ComputeHash(Encoding.UTF8.GetBytes(message)));
            });
        }
        if (name == "samebytes")
        {
            Need(args, 2, name, line, col);
            string left = args[0] as string;
            string right = args[1] as string;
            if (left == null || right == null) throw new VireError("samebytes needs two texts", line, col);
            byte[] a = Encoding.UTF8.GetBytes(left);
            byte[] b = Encoding.UTF8.GetBytes(right);
            if (a.Length != b.Length)
            {
                CryptographicOperations.FixedTimeEquals(a, a);
                return false;
            }
            return CryptographicOperations.FixedTimeEquals(a, b);
        }
        if (name == "encrypt")
        {
            Need(args, 2, name, line, col);
            byte[] key = HexBytes(args[0], KeySize, KeySize, "encrypt needs a 32-byte hex key", line, col);
            return WithZeroedKey(key, k =>
            {
                string plainText = args[1] as string;
                if (plainText == null) throw new VireError("encrypt needs text", line, col);
                byte[] plain = Encoding.UTF8.GetBytes(plainText);
                if (plain.Length > MaxPlain) throw new VireError("text is too large", line, col);
                byte[] nonce = RandomNumberGenerator.GetBytes(NonceSize);
                try
                {
                    byte[] packed = Seal(k, nonce, plain);
                    return (object)ToHex(packed);
                }
                finally
                {
                    CryptographicOperations.ZeroMemory(plain);
                    CryptographicOperations.ZeroMemory(nonce);
                }
            });
        }
        if (name == "decrypt")
        {
            Need(args, 2, name, line, col);
            byte[] key = HexBytes(args[0], KeySize, KeySize, "decrypt needs a 32-byte hex key", line, col);
            return WithZeroedKey(key, k =>
            {
                byte[] packed = HexBytes(args[1], NonceSize + TagSize, NonceSize + TagSize + MaxPlain, "decrypt needs packed hex", line, col);
                byte[] plain = Open(k, packed, line, col);
                try { return (object)Encoding.UTF8.GetString(plain); }
                finally { CryptographicOperations.ZeroMemory(plain); }
            });
        }
        throw new VireError("there is no definition named " + name, line, col);
    }

    public static bool IsName(string name)
    {
        return name == "random" || name == "token" || name == "hmac" || name == "samebytes" || name == "encrypt" || name == "decrypt";
    }

    public static byte[] Seal(byte[] key, byte[] nonce, byte[] plain)
    {
        if (key == null || key.Length != KeySize) throw new VireError("encrypt needs a 32-byte hex key", 1);
        if (nonce == null || nonce.Length != NonceSize) throw new VireError("nonce must be 12 bytes", 1);
        if (plain == null) plain = Array.Empty<byte>();
        if (plain.Length > MaxPlain) throw new VireError("text is too large", 1);
        byte[] cipher = new byte[plain.Length];
        byte[] tag = new byte[TagSize];
        using (AesGcm gcm = new AesGcm(key, TagSize))
            gcm.Encrypt(nonce, plain, cipher, tag);
        byte[] packed = new byte[NonceSize + cipher.Length + TagSize];
        Buffer.BlockCopy(nonce, 0, packed, 0, NonceSize);
        Buffer.BlockCopy(cipher, 0, packed, NonceSize, cipher.Length);
        Buffer.BlockCopy(tag, 0, packed, NonceSize + cipher.Length, TagSize);
        return packed;
    }

    public static byte[] Open(byte[] key, byte[] packed, int line, int col)
    {
        if (key == null || key.Length != KeySize) throw new VireError("decrypt needs a 32-byte hex key", line, col);
        if (packed == null || packed.Length < NonceSize + TagSize)
            throw new VireError("could not decrypt that message", line, col);
        int cipherLen = packed.Length - NonceSize - TagSize;
        if (cipherLen < 0 || cipherLen > MaxPlain) throw new VireError("could not decrypt that message", line, col);
        byte[] nonce = new byte[NonceSize];
        byte[] cipher = new byte[cipherLen];
        byte[] tag = new byte[TagSize];
        byte[] plain = new byte[cipherLen];
        Buffer.BlockCopy(packed, 0, nonce, 0, NonceSize);
        Buffer.BlockCopy(packed, NonceSize, cipher, 0, cipherLen);
        Buffer.BlockCopy(packed, NonceSize + cipherLen, tag, 0, TagSize);
        try
        {
            using (AesGcm gcm = new AesGcm(key, TagSize))
                gcm.Decrypt(nonce, cipher, tag, plain);
            return plain;
        }
        catch (CryptographicException)
        {
            CryptographicOperations.ZeroMemory(plain);
            throw new VireError("could not decrypt that message", line, col);
        }
        finally
        {
            CryptographicOperations.ZeroMemory(nonce);
        }
    }

    public static string HmacHex(byte[] key, byte[] message)
    {
        using (HMACSHA256 hmac = new HMACSHA256(key))
            return ToHex(hmac.ComputeHash(message));
    }

    public static string ToHex(byte[] bytes)
    {
        StringBuilder text = new StringBuilder(bytes.Length * 2);
        for (int i = 0; i < bytes.Length; i++)
            text.Append(bytes[i].ToString("x2"));
        return text.ToString();
    }

    public static byte[] FromHex(string text, int line, int col)
    {
        if (text == null || (text.Length & 1) != 0) throw new VireError("hex text is damaged", line, col);
        byte[] bytes = new byte[text.Length / 2];
        for (int i = 0; i < bytes.Length; i++)
        {
            int hi = Nibble(text[i * 2], line, col);
            int lo = Nibble(text[i * 2 + 1], line, col);
            bytes[i] = (byte)((hi << 4) | lo);
        }
        return bytes;
    }

    public static T WithZeroedKey<T>(byte[] key, Func<byte[], T> body)
    {
        try { return body(key); }
        finally { CryptographicOperations.ZeroMemory(key); }
    }

    static byte[] HexBytes(object value, int min, int max, string message, int line, int col)
    {
        string text = value as string;
        if (text == null) throw new VireError(message, line, col);
        byte[] bytes = FromHex(text, line, col);
        if (bytes.Length < min || bytes.Length > max) throw new VireError(message, line, col);
        return bytes;
    }

    static int Nibble(char ch, int line, int col)
    {
        if (ch >= '0' && ch <= '9') return ch - '0';
        if (ch >= 'a' && ch <= 'f') return ch - 'a' + 10;
        if (ch >= 'A' && ch <= 'F') return ch - 'A' + 10;
        throw new VireError("hex text is damaged", line, col);
    }

    static string ToUrl(byte[] bytes)
    {
        return Convert.ToBase64String(bytes).Replace('+', '-').Replace('/', '_').TrimEnd('=');
    }

    static void Need(System.Collections.Generic.List<object> args, int need, string name, int line, int col)
    {
        if (args.Count != need) throw new VireError(name + " takes " + need + " values, got " + args.Count, line, col);
    }

    static int Count(object value, int min, int max, string message, int line, int col)
    {
        int n;
        if (value is int) n = (int)value;
        else if (value is double)
        {
            double real = (double)value;
            if (real != Math.Floor(real) || real < int.MinValue || real > int.MaxValue)
                throw new VireError(message, line, col);
            n = (int)real;
        }
        else throw new VireError(message, line, col);
        if (n < min || n > max) throw new VireError(message, line, col);
        return n;
    }
}
