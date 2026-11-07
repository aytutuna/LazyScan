using LazyScan.App.Services;
using Microsoft.Win32;
using Xunit;

namespace LazyScan.App.Tests;

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
    public void APackagedAppWritesNothingToTheClasses()
    {
        using var classes = Registry.CurrentUser.CreateSubKey(_keyPath);
        Packaging.IsPackaged = true;
        FileAssociation.RegisterForCurrentUser(classes, @"C:\Lazy Scan\LazyScan.exe");
        Assert.Empty(classes.GetSubKeyNames());
    }
}
