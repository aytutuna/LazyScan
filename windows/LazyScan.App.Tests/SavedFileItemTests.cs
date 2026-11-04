using System.Globalization;
using LazyScan.App.Services;
using Xunit;

namespace LazyScan.App.Tests;

public sealed class SavedFileItemTests
{
    [Fact]
    public void TypeTextIgnoresTheCulturesCasing()
    {
        var saved = CultureInfo.CurrentCulture;
        try
        {
            CultureInfo.CurrentCulture = CultureInfo.GetCultureInfo("tr-TR");
            var item = new SavedFileItem(new SavedFile(@"C:\scans\scan.gif", DateTime.Now, 1));
            Assert.Equal("GIF", item.TypeText);
        }
        finally
        {
            CultureInfo.CurrentCulture = saved;
        }
    }
}
