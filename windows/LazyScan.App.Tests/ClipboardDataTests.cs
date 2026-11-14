using System.IO;
using System.Windows;
using LazyScan.App.Services;
using LazyScan.Core;
using Xunit;

namespace LazyScan.App.Tests;

public sealed class ClipboardDataTests
{
    private static void AssertExcluded(DataObject data)
    {
        foreach (string format in WindowsFileActions.HistoryExclusionFormats)
        {
            Assert.True(data.GetDataPresent(format), format);
            var stream = Assert.IsAssignableFrom<MemoryStream>(data.GetData(format));
            Assert.Equal(new byte[4], stream.ToArray());
        }
    }

    [Fact]
    public void CopiedTextStaysOutOfHistoryAndStillPastes()
    {
        var data = WindowsFileActions.TextData("hello");
        AssertExcluded(data);
        Assert.Equal("hello", data.GetData(DataFormats.UnicodeText));
    }

    [Fact]
    public void CopiedFilesStayOutOfHistoryAndStillPaste()
    {
        var data = WindowsFileActions.ClipboardData(new ClipboardContent(new[] { @"C:\scans\a.pdf" }, null), _ => null);
        AssertExcluded(data);
        Assert.Equal(new[] { @"C:\scans\a.pdf" }, data.GetFileDropList().Cast<string>());
    }
}
