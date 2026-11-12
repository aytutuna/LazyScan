using System.Text.Json;
using LazyScan.Core;
using Xunit;

namespace LazyScan.Core.Tests;

public class DestinationPathTests
{
    private static string Documents => Environment.GetFolderPath(Environment.SpecialFolder.MyDocuments);

    [Fact]
    public void FreshSettings_StoreNothing_AndResolveToDocuments()
    {
        var s = new ScanSettings();
        Assert.Equal("", s.DestinationPath);
        Assert.Equal(Path.Combine(Documents, "Lazy Scan"), s.ResolveDestination());
    }

    [Fact]
    public void PickedFolder_IsKept()
    {
        var s = new ScanSettings { DestinationPath = @"D:\Archive\Scans" };
        Assert.Equal(@"D:\Archive\Scans", s.DestinationPath);
        Assert.Equal(@"D:\Archive\Scans", s.ResolveDestination());
    }

    [Fact]
    public void StoredOldDefault_ReadsBackAsEmpty()
    {
        string oldDefault = Path.Combine(Documents, "Lazy Scan");
        string dir = Directory.CreateTempSubdirectory().FullName;
        try
        {
            File.WriteAllText(StoreFiles.SettingsPath(dir), JsonSerializer.Serialize(new { DestinationPath = oldDefault }));
            Assert.Equal("", SettingsStore.Load(dir)!.DestinationPath);
        }
        finally { Directory.Delete(dir, true); }

        var profile = new ScanSettings
        {
            DestinationPath = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.UserProfile), "Documents", "Lazy Scan"),
        };
        Assert.Equal("", profile.DestinationPath);
    }
}
