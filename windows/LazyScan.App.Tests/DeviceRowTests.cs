using LazyScan.Core;
using Xunit;

namespace LazyScan.App.Tests;

public class DeviceRowTests
{
    private static DeviceRow Row()
    {
        var info = new ScannerInfo("wia:1", "Brother DCP-L2550", "USB");
        return new DeviceRow(info, new DeviceGroup("k", info, [info]), null);
    }

    [Fact]
    public void ConnectedRow_HasNoStateLine_AndKeepsItsName()
    {
        var row = Row();
        Assert.Equal("", row.StateLine);
        Assert.Equal("Brother DCP-L2550", row.StateName);
    }

    [Fact]
    public void ConnectingAndFailedRows_SayWhatIsHappening()
    {
        var row = Row();
        row.ConnectionState = DeviceConnectionState.Connecting;
        Assert.Equal("Connecting…", row.StateLine);
        Assert.Equal("Brother DCP-L2550, Connecting…", row.StateName);
        row.ConnectionState = DeviceConnectionState.Failed;
        Assert.Equal("Not connected - Click to retry", row.StateLine);
        Assert.Equal("Brother DCP-L2550, Not connected - Click to retry", row.StateName);
        Assert.Equal("Retry connecting to Brother DCP-L2550", row.RetryName);
    }
}
