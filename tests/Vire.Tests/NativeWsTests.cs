using System;
using System.IO;
using System.Net.Sockets;
using System.Security.Cryptography;
using System.Text;
using Xunit;

public class NativeWsTests
{
    [Fact]
    public void WsRuntimeIsStagedAndOptInWithListen()
    {
        string root = DualMode.FindRoot();
        string ws = File.ReadAllText(Path.Combine(root, "src", "rt-ws.vire"));
        string staged = File.ReadAllText(Path.Combine(root, "data", "src", "rt-ws.vire"));
        Assert.Equal(ws, staged);
        Assert.Contains("emitWsRuntime", ws);
        Assert.Contains("ws_dispatch", ws);
        Assert.Contains("rt_loop_tick", ws);
        Assert.Contains("rt_note_wait", ws);
        Assert.Contains("ws_clcode", ws);
        Assert.Contains("emitU32 with image, 65536", ws);
        Assert.DoesNotContain("VirtualProtect", ws);
        Assert.DoesNotContain("LoadLibraryA", ws);
        string native = File.ReadAllText(Path.Combine(root, "compile-native.vire"));
        Assert.Contains("use \"src/rt-ws.vire\"", native);
        Assert.Contains("needWs", native);
        Assert.Equal(5000000, Program.ProgramStepCap);
        Assert.Contains("33554432", File.ReadAllText(Path.Combine(root, "src", "rt.vire")));
    }

    [Fact]
    public void ListenGuestImageParksWebsocketHandshake()
    {
        string root = DualMode.FindRoot();
        string work = Path.Combine(root, "data", "native-ws", Guid.NewGuid().ToString("N"));
        Directory.CreateDirectory(work);
        try
        {
            File.Copy(Path.Combine(root, "tests", "native", "ws-echo.vire"), Path.Combine(work, "ws-echo.vire"));
            string srcRel = ("data/native-ws/" + Path.GetFileName(work) + "/ws-echo.vire").Replace('\\', '/');
            string hexRel = ("data/native-ws/" + Path.GetFileName(work) + "/ws-echo.hex").Replace('\\', '/');
            DualMode.Proc compiled = DualMode.RunVire(root, new string[] { "compile-native.vire", srcRel, hexRel }, root);
            Assert.True(compiled.Code == 0, DualMode.Norm(compiled.Out + " " + compiled.Err));
            Assert.Contains("compiled", DualMode.Norm(compiled.Out));
            string hex = File.ReadAllText(Path.Combine(root, hexRel.Replace('/', Path.DirectorySeparatorChar))).Trim();
            byte[] image = new byte[hex.Length / 2];
            for (int i = 0; i < image.Length; i++)
                image[i] = Convert.ToByte(hex.Substring(i * 2, 2), 16);
            if (OperatingSystem.IsLinux())
            {
                Assert.Equal(0x7f, image[0]);
                Assert.Equal((byte)'F', image[3]);
            }
            string ascii = Encoding.ASCII.GetString(image);
            Assert.Contains("Switching Protocols", ascii);
            Assert.Contains("258EAFA5-E914-47DA-95CA-C5AB0DC85B11", ascii);
            Assert.Contains("listening on 127.0.0.1:", ascii);
        }
        finally
        {
            try { Directory.Delete(work, true); } catch (IOException) { }
        }
    }

    [Fact]
    public void HostListenAcceptsRfc6455OnApiGoLivePaths()
    {
        string guest = File.ReadAllText(Path.Combine(DualMode.FindRoot(), "tests", "rebuild", "guests", "apigo-ws.vire"));
        using (ListenHost host = ListenHost.Start(guest))
        {
            string[] paths = { "/ws/kick", "/ws/chat", "/ws/live", "/chat", "/live", "/" };
            for (int i = 0; i < paths.Length; i++)
                Assert.True(VireWs.IsLivePath(paths[i]) || paths[i] == "/", paths[i]);
            HandshakeEcho(host.Port, "/ws/kick");
            HandshakeEcho(host.Port, "/ws/chat");
            HandshakeEcho(host.Port, "/live");
            AssertClose(host.Port, "/", Mask(1, Encoding.ASCII.GetBytes("no"), false, 0, false), 1002);
            AssertClose(host.Port, "/", Mask(1, Encoding.ASCII.GetBytes("x"), true, 1, false), 1002);
            AssertClose(host.Port, "/", Mask(9, Encoding.ASCII.GetBytes("p"), true, 0, false, false), 1002);
            AssertClose(host.Port, "/", Mask(1, Encoding.ASCII.GetBytes("tiny"), true, 0, true), 1009);
            AssertClose(host.Port, "/", Mask(1, Encoding.ASCII.GetBytes(new string('a', 65537)), true, 0, false), 1009);
        }
        Assert.Equal(5000000, Program.ProgramStepCap);
        Assert.Contains("33554432", File.ReadAllText(Path.Combine(DualMode.FindRoot(), "src", "rt.vire")));
        Assert.Contains("100000", File.ReadAllText(Path.Combine(DualMode.FindRoot(), "Vire.cs")).Substring(0, 4000));
    }

    static void HandshakeEcho(int port, string path)
    {
        using (TcpClient client = new TcpClient())
        {
            client.ReceiveTimeout = 4000;
            client.SendTimeout = 4000;
            client.Connect("127.0.0.1", port);
            NetworkStream stream = client.GetStream();
            string key = Convert.ToBase64String(Encoding.ASCII.GetBytes("0123456789abcdef"));
            byte[] req = Encoding.ASCII.GetBytes(
                "GET " + path + " HTTP/1.1\r\nHost: 127.0.0.1\r\nUpgrade: websocket\r\n"
                + "Connection: Upgrade\r\nSec-WebSocket-Key: " + key + "\r\n"
                + "Sec-WebSocket-Version: 13\r\n\r\n");
            stream.Write(req, 0, req.Length);
            string head = ReadHeaders(stream);
            Assert.Contains("101", head);
            string accept = Convert.ToBase64String(SHA1.HashData(Encoding.ASCII.GetBytes(key + "258EAFA5-E914-47DA-95CA-C5AB0DC85B11")));
            Assert.Contains(accept, head);
            byte[] frame = Mask(1, Encoding.ASCII.GetBytes("xyz"), true, 0, false);
            stream.Write(frame, 0, frame.Length);
            byte[] got = ReadN(stream, 5);
            Assert.Equal(0x81, got[0]);
            Assert.Equal(0x03, got[1]);
            Assert.Equal((byte)'x', got[2]);
            Assert.Equal((byte)'y', got[3]);
            Assert.Equal((byte)'z', got[4]);
        }
    }

    static void AssertClose(int port, string path, byte[] bad, int code)
    {
        using (TcpClient client = new TcpClient())
        {
            client.ReceiveTimeout = 4000;
            client.SendTimeout = 4000;
            client.Connect("127.0.0.1", port);
            NetworkStream stream = client.GetStream();
            string key = Convert.ToBase64String(Encoding.ASCII.GetBytes("0123456789abcdef"));
            byte[] req = Encoding.ASCII.GetBytes(
                "GET " + path + " HTTP/1.1\r\nHost: 127.0.0.1\r\nUpgrade: websocket\r\n"
                + "Connection: Upgrade\r\nSec-WebSocket-Key: " + key + "\r\n"
                + "Sec-WebSocket-Version: 13\r\n\r\n");
            stream.Write(req, 0, req.Length);
            string head = ReadHeaders(stream);
            Assert.Contains("101", head);
            stream.Write(bad, 0, bad.Length);
            byte[] got = ReadN(stream, 4);
            Assert.Equal(0x88, got[0]);
            int seen = (got[2] << 8) | got[3];
            Assert.Equal(code, seen);
        }
    }

    static byte[] ReadN(NetworkStream stream, int want)
    {
        byte[] got = new byte[want];
        int n = 0;
        while (n < want)
        {
            int r = stream.Read(got, n, want - n);
            Assert.True(r > 0);
            n += r;
        }
        return got;
    }

    static string ReadHeaders(NetworkStream stream)
    {
        byte[] buf = new byte[1024];
        int n = 0;
        while (n < buf.Length)
        {
            int r = stream.Read(buf, n, buf.Length - n);
            Assert.True(r > 0);
            n += r;
            string soFar = Encoding.ASCII.GetString(buf, 0, n);
            int end = soFar.IndexOf("\r\n\r\n", StringComparison.Ordinal);
            if (end >= 0) return soFar.Substring(0, end + 4);
        }
        throw new InvalidOperationException("headers not found");
    }

    static byte[] Mask(int opcode, byte[] payload, bool mask, int rsv, bool ext127, bool fin = true)
    {
        MemoryStream ms = new MemoryStream();
        int b0 = (fin ? 0x80 : 0) | ((rsv & 7) << 4) | (opcode & 0x0f);
        ms.WriteByte((byte)b0);
        int n = payload.Length;
        int maskbit = mask ? 0x80 : 0;
        if (ext127)
        {
            ms.WriteByte((byte)(maskbit | 127));
            byte[] len = BitConverter.GetBytes((ulong)n);
            if (BitConverter.IsLittleEndian) Array.Reverse(len);
            ms.Write(len, 0, 8);
        }
        else if (n < 126)
            ms.WriteByte((byte)(maskbit | n));
        else if (n < 65536)
        {
            ms.WriteByte((byte)(maskbit | 126));
            ms.WriteByte((byte)((n >> 8) & 0xff));
            ms.WriteByte((byte)(n & 0xff));
        }
        else
        {
            ms.WriteByte((byte)(maskbit | 127));
            byte[] len = BitConverter.GetBytes((ulong)n);
            if (BitConverter.IsLittleEndian) Array.Reverse(len);
            ms.Write(len, 0, 8);
        }
        byte[] body = payload;
        if (mask)
        {
            byte[] m = new byte[] { 0x37, 0xfa, 0x21, 0x3d };
            ms.Write(m, 0, 4);
            body = new byte[payload.Length];
            for (int i = 0; i < payload.Length; i++) body[i] = (byte)(payload[i] ^ m[i % 4]);
        }
        ms.Write(body, 0, body.Length);
        return ms.ToArray();
    }
}
