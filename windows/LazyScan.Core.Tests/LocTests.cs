using Xunit;
using System.Globalization;

namespace LazyScan.Core.Tests;

public sealed class LocTests
{
    [Fact]
    public void NoTableReturnsEnglish() => Assert.Equal("Save as PDF", Loc.T("Save as PDF"));

    [Fact]
    public void PlaceholdersAreFilled()
    {
        Assert.Equal("ab of 5", Loc.T("{1} of {0}", 5, "ab"));
        Assert.Equal("x and x", Loc.T("{0} and {0}", "x"));
    }

    [Fact]
    public void UnmatchedPlaceholderStaysAndValuesAreNotReplaced() =>
        Assert.Equal("{1} {2} { }", Loc.T("{0} {2} { }", "{1}"));

    [Fact]
    public void ContextMarkerIsStrippedInEnglish()
    {
        Assert.Equal("Scan", Loc.T("Scan|noun"));
        Assert.Equal("Scan", Loc.T("Scan|verb"));
    }

    [Fact]
    public void ContextMarkerSelectsTheTranslation() =>
        InTurkish(new() { ["Scan|noun"] = "Tarama", ["Scan|verb"] = "Tara" }, () =>
        {
            Assert.Equal("Tarama", Loc.T("Scan|noun"));
            Assert.Equal("Tara", Loc.T("Scan|verb"));
        });

    [Fact]
    public void TableReplacesTheLookupAndFillsPlaceholders()
    {
        InTurkish(new() { ["Open {0}"] = "{0} dosyasını aç" }, () =>
        {
            Assert.Equal("a.pdf dosyasını aç", Loc.T("Open {0}", "a.pdf"));
            Assert.Equal("Not in the table", Loc.T("Not in the table"));
        });
        Assert.Equal("Open a.pdf", Loc.T("Open {0}", "a.pdf"));
    }

    [Fact]
    public async Task TableIsPerAsyncContext()
    {
        using var tableSet = new SemaphoreSlim(0);
        using var checkedElsewhere = new SemaphoreSlim(0);
        var holder = Task.Run(() => InTurkish(new() { ["Save"] = "Kaydet" }, () =>
        {
            Assert.Equal("Kaydet", Loc.T("Save"));
            tableSet.Release();
            checkedElsewhere.Wait();
        }));
        await tableSet.WaitAsync();
        Assert.Equal("Save", Loc.T("Save"));
        checkedElsewhere.Release();
        await holder;
    }

    [Fact]
    public void ResourceLookupFallsBackToEnglishInTurkish() =>
        InTurkish(null, () =>
        {
            Assert.Equal("Save as PDF", Loc.T("Save as PDF"));
            Assert.Equal("Scan", Loc.T("Scan|noun"));
            Assert.Equal("2 files", Loc.Plural(2, "{0} file", "{0} files"));
        });

    [Fact]
    public void HalvesRoundToEvenAndNativeIntsGroup() =>
        InTurkish(new(), () =>
        {
            Assert.Equal("2,062", Loc.T("{0}", 2.0625));
            Assert.Equal("12.345", Loc.T("{0}", (nint)12345));
        });

    [Fact]
    public void NumbersUseTheCultureFormat() =>
        InTurkish(new(), () =>
        {
            Assert.Equal("1,5 mm", Loc.T("{0} mm", 1.5));
            Assert.Equal("1.234", Loc.T("{0}", 1234));
            Assert.Equal("1234", Loc.T("{0}", "1234"));
        });

    [Fact]
    public void EnglishPlural()
    {
        Assert.Equal("1 scan", Loc.Plural(1, "{0} scan", "{0} scans"));
        Assert.Equal("0 scans", Loc.Plural(0, "{0} scan", "{0} scans"));
        Assert.Equal("3 scans", Loc.Plural(3, "{0} scan", "{0} scans"));
    }

    [Fact]
    public void TurkishPluralUsesItsOwnRows() =>
        InTurkish(new()
        {
            ["Delete {0} page?|one"] = "Sayfa silinsin mi?",
            ["Delete {0} page?|other"] = "{0} sayfa silinsin mi?",
        }, () =>
        {
            Assert.Equal("Sayfa silinsin mi?", Loc.Plural(1, "Delete {0} page?", "Delete {0} pages?"));
            Assert.Equal("1.234 sayfa silinsin mi?", Loc.Plural(1234, "Delete {0} page?", "Delete {0} pages?"));
        });

    [Fact]
    public void ScanCountInTurkishKeepsTheNounSingular() =>
        InTurkish(null, () =>
        {
            Assert.Equal("1 tarama", Loc.Plural(1, "{0} scan", "{0} scans"));
            Assert.Equal("1.234 tarama", Loc.Plural(1234, "{0} scan", "{0} scans"));
        });

    [Fact]
    public void PluralExtraArguments() =>
        Assert.Equal("2 pages in Inbox", Loc.Plural(2, "{0} page in {1}", "{0} pages in {1}", "Inbox"));

    [Fact]
    public void PluralRules()
    {
        Assert.Equal("one", Loc.PluralCategory(1, "en"));
        Assert.Equal("other", Loc.PluralCategory(2, "en"));
        Assert.Equal("one", Loc.PluralCategory(1, "tr"));
        Assert.Equal("other", Loc.PluralCategory(0, "tr"));
        Assert.Equal("one", Loc.PluralCategory(1, "xx"));
    }

    [Fact]
    public void TurkishCasingKeepsTheDottedI()
    {
        var tr = CultureInfo.GetCultureInfo("tr-TR");
        Assert.Equal("İSTANBUL", "istanbul".ToUpper(tr));
        Assert.Equal("ıspanak", "ISPANAK".ToLower(tr));
    }

    private static void InTurkish(Dictionary<string, string>? table, Action body)
    {
        var culture = CultureInfo.CurrentCulture;
        var ui = CultureInfo.CurrentUICulture;
        try
        {
            CultureInfo.CurrentCulture = CultureInfo.CurrentUICulture = CultureInfo.GetCultureInfo("tr-TR");
            Loc.Table = table;
            body();
        }
        finally
        {
            Loc.Table = null;
            CultureInfo.CurrentCulture = culture;
            CultureInfo.CurrentUICulture = ui;
        }
    }
}
