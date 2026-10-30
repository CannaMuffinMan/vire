using System;
using System.Net;
using System.Net.Sockets;

static class PortGuard
{
    static readonly int[] Banned = { 7099, 8778, 7071, 7072, 17841 };

    public static int GetFreeLoopbackPort()
    {
        for (int attempt = 0; attempt < 8; attempt++)
        {
            TcpListener listener = new TcpListener(IPAddress.Loopback, 0);
            listener.Start();
            int port = ((IPEndPoint)listener.LocalEndpoint).Port;
            listener.Stop();
            if (!IsBanned(port)) return port;
        }
        throw new InvalidOperationException("could not get an allowed loopback port");
    }

    public static void AssertAllowedPort(int port)
    {
        if (IsBanned(port)) throw new InvalidOperationException("port " + port + " is reserved");
    }

    static bool IsBanned(int port)
    {
        for (int i = 0; i < Banned.Length; i++)
            if (Banned[i] == port) return true;
        return false;
    }
}
