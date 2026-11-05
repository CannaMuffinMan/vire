using System;
using System.IO;
using System.Security.Cryptography;
using System.Text;
using Xunit;

public class SealTests
{
    static string TestKeyB64()
    {
        byte[] key = new byte[32];
        for (int i = 0; i < key.Length; i++) key[i] = (byte)(i + 3);
        return Convert.ToBase64String(key);
    }

    static void WithKey(string b64, Action body)
    {
        string previous = Environment.GetEnvironmentVariable("VIRE_SEAL_KEY");
        Environment.SetEnvironmentVariable("VIRE_SEAL_KEY", b64);
        VireSeal.ClearKey();
        try
        {
            if (!string.IsNullOrEmpty(b64)) VireSeal.LoadFromEnvironment();
            body();
        }
        finally
        {
            VireSeal.ClearKey();
            Environment.SetEnvironmentVariable("VIRE_SEAL_KEY", previous);
        }
    }

    [Fact]
    public void RoundTripAndNonceDiffer()
    {
        WithKey(TestKeyB64(), () =>
        {
            byte[] a = VireSeal.SealBytes(Encoding.UTF8.GetBytes("hello"));
            byte[] b = VireSeal.SealBytes(Encoding.UTF8.GetBytes("hello"));
            Assert.NotEqual(Convert.ToBase64String(a), Convert.ToBase64String(b));
            Assert.Equal("hello", Encoding.UTF8.GetString(VireSeal.OpenBytes(a)));
            Assert.Equal("hello", Encoding.UTF8.GetString(VireSeal.OpenBytes(b)));
        });
    }

    [Fact]
    public void FlipAnyByteIsRefused()
    {
        WithKey(TestKeyB64(), () =>
        {
            byte[] packed = VireSeal.SealBytes(Encoding.UTF8.GetBytes("payload"));
            for (int i = 0; i < packed.Length; i++)
            {
                byte[] copy = (byte[])packed.Clone();
                copy[i] ^= 0xff;
                Assert.Throws<VireError>(() => VireSeal.OpenBytes(copy));
            }
        });
    }

    [Fact]
    public void WrongKeyIsRefused()
    {
        byte[] packed = null;
        WithKey(TestKeyB64(), () => { packed = VireSeal.SealBytes(Encoding.UTF8.GetBytes("secret-text")); });
        byte[] other = new byte[32];
        for (int i = 0; i < other.Length; i++) other[i] = (byte)(200 - i);
        WithKey(Convert.ToBase64String(other), () =>
        {
            Assert.Throws<VireError>(() => VireSeal.OpenBytes(packed));
        });
    }

    [Fact]
    public void MissingKeyExits2WithoutLeakingMaterial()
    {
        string previous = Environment.GetEnvironmentVariable("VIRE_SEAL_KEY");
        Environment.SetEnvironmentVariable("VIRE_SEAL_KEY", null);
        VireSeal.ClearKey();
        TextWriter oldOut = Console.Out;
        TextWriter oldErr = Console.Error;
        StringWriter stdout = new StringWriter();
        StringWriter stderr = new StringWriter();
        Console.SetOut(stdout);
        Console.SetError(stderr);
        try
        {
            string dir = Path.Combine(Path.GetTempPath(), "vire-nokey-" + Guid.NewGuid().ToString("n"));
            Directory.CreateDirectory(dir);
            string program = Path.Combine(dir, "s.vire");
            File.WriteAllText(program, "define main\n  say (seal with \"x\")\nend\n");
            int code = Program.Execute(new string[] { program });
            try { Directory.Delete(dir, true); } catch (IOException) { }
            Assert.Equal(2, code);
            string all = stdout.ToString() + stderr.ToString();
            Assert.Contains("a seal key is required", all);
            Assert.DoesNotContain(TestKeyB64(), all);
        }
        finally
        {
            Console.SetOut(oldOut);
            Console.SetError(oldErr);
            Environment.SetEnvironmentVariable("VIRE_SEAL_KEY", previous);
        }
    }

    [Fact]
    public void PayloadWriteDumpsUnsealedBytes()
    {
        WithKey(TestKeyB64(), () =>
        {
            string dir = Path.Combine(Path.GetTempPath(), "vire-payload-" + Guid.NewGuid().ToString("n"));
            Directory.CreateDirectory(dir);
            try
            {
                byte[] packed = VireSeal.SealBytes(Encoding.UTF8.GetBytes("compiler-bytes"));
                string vc = Path.Combine(dir, "stage.vc");
                string dest = Path.Combine(dir, "stage.bin");
                File.WriteAllBytes(vc, packed);
                int code = Program.Execute(new string[] { "payload-write", vc, dest });
                Assert.Equal(0, code);
                Assert.Equal("compiler-bytes", Encoding.UTF8.GetString(File.ReadAllBytes(dest)));
            }
            finally
            {
                try { Directory.Delete(dir, true); } catch (IOException) { }
            }
        });
    }

    [Fact]
    public void OldXorSealIsRefused()
    {
        WithKey(TestKeyB64(), () =>
        {
            string root = FindRoot();
            byte[] old = File.ReadAllBytes(Path.Combine(root, "tests", "fixtures", "old-xor.vc"));
            VireError err = Assert.Throws<VireError>(() => VireSeal.OpenBytes(old));
            Assert.Contains("old seal", err.Message);
        });
    }

    [Fact]
    public void KeygenWritesOwnerOnlyAndPrintsFingerprint()
    {
        string path = Path.Combine(Path.GetTempPath(), "vire-key-" + Guid.NewGuid().ToString("n"));
        TextWriter oldOut = Console.Out;
        StringWriter stdout = new StringWriter();
        Console.SetOut(stdout);
        try
        {
            int code = VireSeal.Keygen(path);
            Assert.Equal(0, code);
            byte[] written = File.ReadAllBytes(path);
            Assert.Equal(32, written.Length);
            Assert.Contains("seal key fingerprint ", stdout.ToString());
            Assert.Equal(8, stdout.ToString().Trim().Substring("seal key fingerprint ".Length).Length);
            Assert.DoesNotContain(Convert.ToBase64String(written), stdout.ToString());
            if (!OperatingSystem.IsWindows())
            {
                UnixFileMode mode = File.GetUnixFileMode(path);
                Assert.Equal(UnixFileMode.UserRead | UnixFileMode.UserWrite, mode);
            }
            CryptographicOperations.ZeroMemory(written);
        }
        finally
        {
            Console.SetOut(oldOut);
            try { File.Delete(path); } catch (IOException) { }
        }
    }

    [Fact]
    public void KeygenRefusesDeviceAndStreamPathsWithoutPrintingKey()
    {
        string dir = Path.Combine(Path.GetTempPath(), "vire-keydev-" + Guid.NewGuid().ToString("n"));
        Directory.CreateDirectory(dir);
        string device = Path.Combine(dir, "CONOUT$");
        string stream = Path.Combine(dir, "key.bin:secret");
        TextWriter oldOut = Console.Out;
        TextWriter oldErr = Console.Error;
        StringWriter stdout = new StringWriter();
        StringWriter stderr = new StringWriter();
        Console.SetOut(stdout);
        Console.SetError(stderr);
        try
        {
            int code = VireSeal.Keygen(device);
            Assert.Equal(2, code);
            Assert.False(File.Exists(device));
            int streamCode = VireSeal.Keygen(stream);
            Assert.Equal(2, streamCode);
            string all = stdout.ToString() + stderr.ToString();
            Assert.Contains("not allowed", all);
            Assert.DoesNotContain("fingerprint", all);
            Assert.True(all.IndexOf('=') < 0);
        }
        finally
        {
            Console.SetOut(oldOut);
            Console.SetError(oldErr);
            try { Directory.Delete(dir, true); } catch (IOException) { }
        }
    }

    [Fact]
    public void KeyFileSymlinkIntoProgramFolderIsRefused()
    {
        string dir = Path.Combine(Path.GetTempPath(), "vire-keylink-" + Guid.NewGuid().ToString("n"));
        string outside = Path.Combine(Path.GetTempPath(), "vire-keyout-" + Guid.NewGuid().ToString("n"));
        Directory.CreateDirectory(dir);
        Directory.CreateDirectory(outside);
        string inside = Path.Combine(dir, "hidden.key");
        File.WriteAllBytes(inside, new byte[32]);
        string link = Path.Combine(outside, "key.link");
        try
        {
            try { File.CreateSymbolicLink(link, inside); }
            catch (Exception ex)
            {
                Console.WriteLine("key symlink test skipped: " + ex.GetType().Name);
                return;
            }
            VireError err = Assert.Throws<VireError>(() => VireSeal.LoadFromFile(link, dir));
            Assert.Contains("outside the program folder", err.Message);
        }
        finally
        {
            VireSeal.ClearKey();
            try { Directory.Delete(dir, true); } catch (IOException) { }
            try { Directory.Delete(outside, true); } catch (IOException) { }
        }
    }

    static string FindRoot()
    {
        string dir = AppContext.BaseDirectory;
        for (int i = 0; i < 8; i++)
        {
            if (File.Exists(Path.Combine(dir, "vire.csproj"))) return dir;
            DirectoryInfo parent = Directory.GetParent(dir);
            if (parent == null) break;
            dir = parent.FullName;
        }
        throw new InvalidOperationException("could not find the vire repo root");
    }
}
