using LazyScan.Core;
using Xunit;

namespace LazyScan.Core.Tests;

// Twin of Tests/LazyScanTests/LazyPrintUrlTests.swift.
public class LazyPrintUrlTests
{
    [Fact]
    public void Build_EncodesThePathWhole()
    {
        Assert.Equal("lazyprint:open?file=C%3A%5CScans%5Cscan.pdf", LazyPrintUrl.Build([@"C:\Scans\scan.pdf"]));
    }

    [Fact]
    public void Build_RepeatsFileForEachPathInOrder()
    {
        Assert.Equal("lazyprint:open?file=C%3A%5Ca.pdf&file=C%3A%5Cb.png&file=D%3A%5Cc.jpg",
                     LazyPrintUrl.Build([@"C:\a.pdf", @"C:\b.png", @"D:\c.jpg"]));
    }

    [Fact]
    public void Build_EncodesSpacesAndSeparators()
    {
        Assert.Equal("lazyprint:open?file=C%3A%5CMy%20Scans%5Ca%26b%3Dc%2B1%23.pdf",
                     LazyPrintUrl.Build([@"C:\My Scans\a&b=c+1#.pdf"]));
    }

    [Fact]
    public void Build_EncodesNonAsciiAsUtf8()
    {
        Assert.Equal("lazyprint:open?file=C%3A%5CBelgeler%5C%C5%9Fi%C4%9Fli%20%C3%A7ay.pdf",
                     LazyPrintUrl.Build([@"C:\Belgeler\şiğli çay.pdf"]));
    }

    [Fact]
    public void Build_ReadsBackToTheSamePaths()
    {
        string[] paths = [@"C:\My Scans\a&b=c+1#.pdf", @"C:\Belgeler\şiğli çay.pdf"];
        var back = LazyPrintUrl.Build(paths).Split('?')[1].Split('&').Select(pair => Uri.UnescapeDataString(pair["file=".Length..]));
        Assert.Equal(paths, back);
    }
}
