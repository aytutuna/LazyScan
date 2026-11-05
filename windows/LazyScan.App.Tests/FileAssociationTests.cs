using LazyScan.App.Services;
using Microsoft.Win32;
using Xunit;

namespace LazyScan.App.Tests;

// The .lsdoc association and the lazyscan: scheme are written under a key of the tests' own in
// HKCU\Software, removed again afterwards; the user's real Software\Classes is never touched.

public sealed class FileAssociationTests : IDisposable
{
    private readonly string _keyPath = @"Software\LazyScan.Tests-" + Guid.NewGuid().ToString("N");

    public void Dispose() => Registry.CurrentUser.DeleteSubKeyTree(_keyPath, throwOnMissingSubKey: false);

    private const string Exe = @"C:\Program Files\Lazy Scan\LazyScan.exe";

    [Fact]
    public void Entries_PointTheExtensionAndTheSchemeAtTheApp()
    {
        Assert.Equal(
            [
                (".lsdoc", "", "LazyScan.Package"),
                ("LazyScan.Package", "", "Lazy Scan document"),
                (@"LazyScan.Package\DefaultIcon", "", "\"C:\\Program Files\\Lazy Scan\\LazyScan.exe\",0"),
                (@"LazyScan.Package\shell\open\command", "", "\"C:\\Program Files\\Lazy Scan\\LazyScan.exe\" \"%1\""),
                ("lazyscan", "", "URL:Lazy Scan"),
                ("lazyscan", "URL Protocol", ""),
                (@"lazyscan\DefaultIcon", "", "\"C:\\Program Files\\Lazy Scan\\LazyScan.exe\",0"),
                (@"lazyscan\shell\open\command", "", "\"C:\\Program Files\\Lazy Scan\\LazyScan.exe\" \"%1\""),
            ],
            FileAssociation.Entries(Exe));
    }

    [Fact]
    public void Register_WritesOnceAndFollowsTheExe()
    {
        using var classes = Registry.CurrentUser.CreateSubKey(_keyPath);
        Assert.True(FileAssociation.Register(classes, Exe));
        foreach (var (name, valueName, value) in FileAssociation.Entries(Exe))
        {
            using var key = classes.OpenSubKey(name);
            Assert.Equal(value, key?.GetValue(valueName));
        }
        // A second start changes nothing; a moved exe is followed.
        Assert.False(FileAssociation.Register(classes, Exe));
        Assert.True(FileAssociation.Register(classes, @"D:\Apps\LazyScan.exe"));
        foreach (string key in new[] { @"LazyScan.Package\shell\open\command", @"lazyscan\shell\open\command" })
        {
            using var command = classes.OpenSubKey(key);
            Assert.Equal("\"D:\\Apps\\LazyScan.exe\" \"%1\"", command?.GetValue(""));
        }
    }

    [Fact]
    public void IsAddress_IsTheSchemeInAnyCase()
    {
        Assert.True(FileAssociation.IsAddress("lazyscan:"));
        Assert.True(FileAssociation.IsAddress("LazyScan://pair?v=1"));
        Assert.True(FileAssociation.IsAddress("  lazyscan:x"));
        Assert.False(FileAssociation.IsAddress(@"C:\Scans\lazyscan:.lsdoc"));
        Assert.False(FileAssociation.IsAddress("lazyprint:open"));
    }
}
