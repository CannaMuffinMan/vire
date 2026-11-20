using System;
using System.IO;
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
}
