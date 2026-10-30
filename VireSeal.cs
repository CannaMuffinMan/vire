using System;
using System.IO;
using System.Security.Cryptography;
using System.Text;

static class VireSeal
{
    static readonly byte[] Magic = Encoding.ASCII.GetBytes("VIRE-VC2\0");
    const byte Version = 2;
    const int NonceSize = 12;
    const int TagSize = 16;
    const int KeySize = 32;
    const string NeedKey = "a seal key is required (set VIRE_SEAL_KEY or --seal-key-file)";

    static byte[] key;

    public static bool MissingKeyExit(string message)
    {
        return message != null && message == NeedKey;
    }

    public static void ClearKey()
    {
        if (key != null)
        {
            CryptographicOperations.ZeroMemory(key);
            key = null;
        }
    }

    public static void LoadFromEnvironment()
    {
        string raw = Environment.GetEnvironmentVariable("VIRE_SEAL_KEY");
        if (string.IsNullOrEmpty(raw)) return;
        byte[] decoded;
        try { decoded = Convert.FromBase64String(raw.Trim()); }
        catch (FormatException) { throw new VireError("seal key is invalid", 1); }
        UseKey(decoded);
    }

    public static void LoadFromFile(string path, string programFolder)
    {
        if (string.IsNullOrEmpty(path)) throw new VireError(NeedKey, 1);
        string full = Path.GetFullPath(path);
        if (!string.IsNullOrEmpty(programFolder) && VirePaths.InFolder(programFolder, full))
            throw new VireError("the seal key file must stay outside the program folder", 1);
        byte[] data;
        try { data = File.ReadAllBytes(full); }
        catch (IOException) { throw new VireError("could not read the seal key file", 1); }
        catch (UnauthorizedAccessException) { throw new VireError("could not read the seal key file", 1); }
        if (data.Length == KeySize)
        {
            UseKey(data);
            CryptographicOperations.ZeroMemory(data);
            return;
        }
        string text = Encoding.UTF8.GetString(data).Trim();
        CryptographicOperations.ZeroMemory(data);
        byte[] decoded;
        try { decoded = Convert.FromBase64String(text); }
        catch (FormatException) { throw new VireError("seal key is invalid", 1); }
        UseKey(decoded);
    }

    static void UseKey(byte[] material)
    {
        if (material == null || material.Length != KeySize)
            throw new VireError("seal key is invalid", 1);
        bool zero = true;
        for (int i = 0; i < material.Length; i++)
            if (material[i] != 0) zero = false;
        if (zero) throw new VireError("seal key is invalid", 1);
        ClearKey();
        key = new byte[KeySize];
        Buffer.BlockCopy(material, 0, key, 0, KeySize);
    }

    public static string Fingerprint()
    {
        RequireKey();
        using (SHA256 sha = SHA256.Create())
        {
            byte[] hash = sha.ComputeHash(key);
            return ToHex(hash).Substring(0, 8);
        }
    }

    public static int Keygen(string path)
    {
        if (string.IsNullOrEmpty(path))
        {
            Console.Error.WriteLine("usage: vire keygen --out <path>");
            return 2;
        }
        string full = Path.GetFullPath(path);
        byte[] material = RandomNumberGenerator.GetBytes(KeySize);
        try
        {
            string parent = Path.GetDirectoryName(full);
            if (parent != null && parent.Length > 0) Directory.CreateDirectory(parent);
            File.WriteAllBytes(full, material);
            TryOwnerOnly(full);
            UseKey(material);
            Console.WriteLine("seal key fingerprint " + Fingerprint());
            return 0;
        }
        finally
        {
            CryptographicOperations.ZeroMemory(material);
        }
    }

    static void TryOwnerOnly(string path)
    {
        if (!OperatingSystem.IsWindows())
            File.SetUnixFileMode(path, UnixFileMode.UserRead | UnixFileMode.UserWrite);
    }

    public static string HashText(string text)
    {
        using (SHA256 sha = SHA256.Create())
        {
            byte[] bytes = sha.ComputeHash(Encoding.UTF8.GetBytes(text ?? ""));
            return ToHex(bytes);
        }
    }

    public static string Seal(string text)
    {
        return FromBytes(SealBytes(Encoding.UTF8.GetBytes(text ?? "")));
    }

    public static string Open(string packed)
    {
        return Encoding.UTF8.GetString(OpenBytes(ToBytes(packed ?? "")));
    }

    public static byte[] SealBytes(byte[] plain)
    {
        RequireKey();
        byte[] nonce = RandomNumberGenerator.GetBytes(NonceSize);
        byte[] cipher = new byte[plain.Length];
        byte[] tag = new byte[TagSize];
        byte[] aad = Aad();
        using (AesGcm gcm = new AesGcm(key, TagSize))
            gcm.Encrypt(nonce, plain, cipher, tag, aad);
        byte[] packed = new byte[Magic.Length + 1 + NonceSize + cipher.Length + TagSize];
        int at = 0;
        Buffer.BlockCopy(Magic, 0, packed, at, Magic.Length); at += Magic.Length;
        packed[at++] = Version;
        Buffer.BlockCopy(nonce, 0, packed, at, nonce.Length); at += nonce.Length;
        Buffer.BlockCopy(cipher, 0, packed, at, cipher.Length); at += cipher.Length;
        Buffer.BlockCopy(tag, 0, packed, at, tag.Length);
        CryptographicOperations.ZeroMemory(nonce);
        return packed;
    }

    public static byte[] OpenBytes(byte[] packed)
    {
        RequireKey();
        if (packed == null || packed.Length < Magic.Length + 1 + NonceSize + TagSize)
            throw new VireError("sealed program is damaged", 1);
        if (LooksOld(packed))
            throw new VireError("this .vc uses the old seal; recompile it", 1);
        for (int i = 0; i < Magic.Length; i++)
            if (packed[i] != Magic[i]) throw new VireError("sealed program is damaged", 1);
        if (packed[Magic.Length] != Version)
            throw new VireError("sealed program is damaged", 1);
        int at = Magic.Length + 1;
        byte[] nonce = new byte[NonceSize];
        Buffer.BlockCopy(packed, at, nonce, 0, NonceSize); at += NonceSize;
        int cipherLen = packed.Length - at - TagSize;
        if (cipherLen < 0) throw new VireError("sealed program is damaged", 1);
        byte[] cipher = new byte[cipherLen];
        Buffer.BlockCopy(packed, at, cipher, 0, cipherLen); at += cipherLen;
        byte[] tag = new byte[TagSize];
        Buffer.BlockCopy(packed, at, tag, 0, TagSize);
        byte[] plain = new byte[cipherLen];
        try
        {
            using (AesGcm gcm = new AesGcm(key, TagSize))
                gcm.Decrypt(nonce, cipher, tag, plain, Aad());
        }
        catch (CryptographicException)
        {
            throw new VireError("sealed program is damaged", 1);
        }
        finally
        {
            CryptographicOperations.ZeroMemory(nonce);
        }
        return plain;
    }

    public static string PayloadSha256(byte[] packed)
    {
        byte[] plain = OpenBytes(packed);
        try { return HashText(Encoding.UTF8.GetString(plain)); }
        finally { CryptographicOperations.ZeroMemory(plain); }
    }

    static bool LooksOld(byte[] packed)
    {
        byte[] old = Encoding.ASCII.GetBytes("VIRE1");
        if (packed.Length < old.Length) return false;
        for (int i = 0; i < old.Length; i++)
            if (packed[i] != old[i]) return false;
        return true;
    }

    static byte[] Aad()
    {
        byte[] aad = new byte[Magic.Length + 1];
        Buffer.BlockCopy(Magic, 0, aad, 0, Magic.Length);
        aad[Magic.Length] = Version;
        return aad;
    }

    static void RequireKey()
    {
        if (key == null || key.Length != KeySize)
            throw new VireError(NeedKey, 1);
    }

    static string ToHex(byte[] bytes)
    {
        StringBuilder hex = new StringBuilder(bytes.Length * 2);
        for (int i = 0; i < bytes.Length; i++) hex.Append(bytes[i].ToString("x2"));
        return hex.ToString();
    }

    public static byte[] ToBytes(string text)
    {
        byte[] bytes = new byte[text.Length];
        for (int i = 0; i < text.Length; i++)
        {
            char ch = text[i];
            if (ch > 255) throw new VireError("sealed program is damaged", 1);
            bytes[i] = (byte)ch;
        }
        return bytes;
    }

    public static string FromBytes(byte[] bytes)
    {
        char[] chars = new char[bytes.Length];
        for (int i = 0; i < bytes.Length; i++) chars[i] = (char)bytes[i];
        return new string(chars);
    }

    public static void WritePacked(string path, string packed)
    {
        File.WriteAllBytes(path, ToBytes(packed));
    }
}
