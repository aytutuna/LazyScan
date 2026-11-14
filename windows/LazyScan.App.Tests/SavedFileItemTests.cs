using System.Globalization;
using System.Windows.Automation.Peers;
using System.Windows.Automation.Provider;
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

    [Fact]
    public void AutomationNameIsNameTypeAndDate()
    {
        var modified = new DateTime(2026, 11, 12, 9, 30, 0);
        var item = new SavedFileItem(new SavedFile(@"C:\scans\Receipt.pdf", modified, 1));
        Assert.Equal($"Receipt.pdf, PDF, {modified:g}", item.AutomationName);
    }

    [Fact]
    public void CardPeerReportsWhetherTheFileIsSelected()
    {
        Exception? failure = null;
        var thread = new Thread(() =>
        {
            try
            {
                var item = new SavedFileItem(new SavedFile(@"C:\scans\Receipt.pdf", DateTime.Now, 1));
                var card = new SavedCard { DataContext = item };
                var peer = UIElementAutomationPeer.CreatePeerForElement(card);
                var selection = (ISelectionItemProvider)peer.GetPattern(PatternInterface.SelectionItem)!;
                Assert.False(selection.IsSelected);
                item.IsSelected = true;
                Assert.True(selection.IsSelected);
            }
            catch (Exception e) { failure = e; }
        });
        thread.SetApartmentState(ApartmentState.STA);
        thread.Start();
        thread.Join();
        if (failure is not null) System.Runtime.ExceptionServices.ExceptionDispatchInfo.Throw(failure);
    }
}
