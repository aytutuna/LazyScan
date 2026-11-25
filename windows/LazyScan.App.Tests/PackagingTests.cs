using System.IO;
using LazyScan.App.Services;
using Microsoft.Win32;
using Xunit;

namespace LazyScan.App.Tests;

// AppInfo reads Packaging.IsPackaged once, so it must not run while a test here sets it
[Collection("Packaging")]
public sealed class PackagingTests : IDisposable
{
    private readonly string _keyPath = @"Software\LazyScan.Tests-" + Guid.NewGuid().ToString("N");

    public void Dispose()
    {
        Packaging.IsPackaged = false;
        Registry.CurrentUser.DeleteSubKeyTree(_keyPath, throwOnMissingSubKey: false);
    }

    [Fact]
    public void ThePackageCallAnswersTooSmallABufferOnlyInsideAPackage()
    {
        Assert.True(Packaging.IsPackageResult(122));
        Assert.False(Packaging.IsPackageResult(15700)); // APPMODEL_ERROR_NO_PACKAGE
        Assert.False(Packaging.IsPackageResult(0));
    }

    [Fact]
    public void TheTestHostIsNotPackaged() => Assert.False(Packaging.IsPackaged);

    [Fact]
    public void TheArmPackageAsksForWindows11AndTheX64OneForWindows10()
    {
        string folder = Path.Combine(AppContext.BaseDirectory, "Store");
        var manifest = System.Xml.Linq.XDocument.Load(Path.Combine(folder, "Package.appxmanifest"));
        var family = manifest.Descendants().Single(e => e.Name.LocalName == "TargetDeviceFamily");
        string template = (string)family.Attribute("MinVersion")!;
        string script = File.ReadAllText(Path.Combine(folder, "make_msix.ps1"));
        var table = System.Text.RegularExpressions.Regex.Match(script, @"\$minVersions = @\{ x64 = '([\d.]+)'; arm64 = '([\d.]+)' \}");

        Assert.True(table.Success, "make_msix.ps1 has no table of minimum versions");
        Assert.Equal("10.0.19041.0", table.Groups[1].Value);
        Assert.Equal("10.0.22000.0", table.Groups[2].Value);
        // The script swaps the template's value for the architecture's, so the manifest must carry the x64 one.
        Assert.Equal(table.Groups[1].Value, template);
        Assert.Contains($"Replace('MinVersion=\"{template}\"'", script);
    }

    [Fact]
    public void APackagedAppWritesNothingToTheClasses()
    {
        using var classes = Registry.CurrentUser.CreateSubKey(_keyPath);
        Packaging.IsPackaged = true;
        FileAssociation.RegisterForCurrentUser(classes, @"C:\Lazy Scan\LazyScan.exe");
        Assert.Empty(classes.GetSubKeyNames());
    }
}
