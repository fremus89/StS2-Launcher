using System.Text;
using STS2Mobile.Patches;
using Xunit;

namespace STS2Mobile.Tests;

public class BeaconMessageTests
{
    private static byte[] Bytes(string s) => Encoding.UTF8.GetBytes(s);

    [Fact]
    public void Valid_message_parses()
    {
        var ok = BeaconMessage.TryParse(Bytes("STS2LAN|LivingRoomPC|33771"), out var beacon);

        Assert.True(ok);
        Assert.Equal("LivingRoomPC", beacon.Hostname);
        Assert.Equal(33771, beacon.Port);
    }

    [Fact]
    public void Wrong_prefix_rejected()
    {
        var ok = BeaconMessage.TryParse(Bytes("NOTSTS|host|33771"), out _);

        Assert.False(ok);
    }

    [Fact]
    public void Too_few_fields_rejected()
    {
        var ok = BeaconMessage.TryParse(Bytes("STS2LAN|host"), out _);

        Assert.False(ok);
    }

    [Fact]
    public void Empty_hostname_rejected()
    {
        var ok = BeaconMessage.TryParse(Bytes("STS2LAN||33771"), out _);

        Assert.False(ok);
    }

    [Fact]
    public void Non_numeric_port_rejected()
    {
        var ok = BeaconMessage.TryParse(Bytes("STS2LAN|host|thirty-three"), out _);

        Assert.False(ok);
    }

    [Theory]
    [InlineData("0")]
    [InlineData("-1")]
    [InlineData("65536")]
    [InlineData("999999")]
    public void Out_of_range_port_rejected(string port)
    {
        var ok = BeaconMessage.TryParse(Bytes($"STS2LAN|host|{port}"), out _);

        Assert.False(ok);
    }

    [Fact]
    public void Null_bytes_rejected()
    {
        var ok = BeaconMessage.TryParse(null, out _);

        Assert.False(ok);
    }

    [Fact]
    public void Empty_bytes_rejected()
    {
        var ok = BeaconMessage.TryParse(new byte[0], out _);

        Assert.False(ok);
    }

    [Fact]
    public void Extra_fields_accepted_for_forward_compatibility()
    {
        var ok = BeaconMessage.TryParse(
            Bytes("STS2LAN|host|33771|future|extensions"),
            out var beacon
        );

        Assert.True(ok);
        Assert.Equal("host", beacon.Hostname);
        Assert.Equal(33771, beacon.Port);
    }
}
