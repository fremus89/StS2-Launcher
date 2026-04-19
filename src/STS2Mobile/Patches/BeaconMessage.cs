using System.Text;

namespace STS2Mobile.Patches;

// LAN discovery beacon message format.
//
// Wire format (UTF-8 text, '|'-separated):
//   STS2LAN|<hostname>|<port>
//
// Pure parsing is extracted into its own type so it can be unit-tested
// without a UDP socket. The listener loop in LanMultiplayerPatcher hands
// raw datagrams to Parse() and reacts to the Ok / reason surface.
public readonly record struct BeaconMessage(string Hostname, int Port)
{
    public const string Prefix = "STS2LAN";

    public static bool TryParse(byte[] data, out BeaconMessage message)
    {
        message = default;
        if (data == null || data.Length == 0)
            return false;

        string text;
        try
        {
            text = Encoding.UTF8.GetString(data);
        }
        catch
        {
            return false;
        }

        var parts = text.Split('|');
        if (parts.Length < 3 || parts[0] != Prefix)
            return false;

        var hostname = parts[1];
        if (string.IsNullOrEmpty(hostname))
            return false;

        if (!int.TryParse(parts[2], out int port))
            return false;
        if (port <= 0 || port > 65535)
            return false;

        message = new BeaconMessage(hostname, port);
        return true;
    }
}
