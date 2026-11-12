using Xunit;

namespace LazyScan.App.Tests;

public sealed class AppInfoTests
{
    [Fact]
    public void DiagnosticsLine_StartsWithVersionWindowsBuildAndArchitecture()
    {
        Assert.False(AppInfo.IsPackaged);
        Assert.NotEmpty(AppInfo.Version);
        string line = AppInfo.DiagnosticsLine;
        Assert.StartsWith($"Lazy Scan {AppInfo.Version} (Not packaged), Windows {Environment.OSVersion.Version.ToString(3)}, ", line);
        Assert.Matches("(x64|x86|arm64)$", line);
    }
}
