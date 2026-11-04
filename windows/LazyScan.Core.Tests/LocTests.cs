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
    public void PluralContextMarkerStaysInTheKey()
    {
        Assert.Equal("Delete 1 page?", Loc.Plural(1, "Delete {0} page?|all", "Delete all {0} pages?"));
        InTurkish(new() { ["Delete {0} page?|all|one"] = "Sayfa silinsin mi?" }, () =>
            Assert.Equal("Sayfa silinsin mi?", Loc.Plural(1, "Delete {0} page?|all", "Delete all {0} pages?")));
    }

    [Fact]
    public void PluralExtraArguments() =>
        Assert.Equal("2 pages in Inbox", Loc.Plural(2, "{0} page in {1}", "{0} pages in {1}", "Inbox"));

    [Theory]
    [InlineData("ar")]
    [InlineData("he")]
    public void RightToLeftIsolatesPlaceholders(string language)
    {
        var saved = CultureInfo.CurrentUICulture;
        try
        {
            CultureInfo.CurrentUICulture = CultureInfo.GetCultureInfo(language);
            Loc.Table = new Dictionary<string, string> { ["Open {0}"] = "{0} x" };
            Assert.Equal("\u2068Scan.pdf\u2069 x", Loc.T("Open {0}", "Scan.pdf"));
            Loc.Table = new Dictionary<string, string>();
            // Swift may write the count in Arabic-Indic digits here; Loc follows CurrentCulture, en-US in tests.
            Assert.Equal("\u20683\u2069 pages, \u2068A4\u2069",
                Loc.Plural(3, "{0} page, {1}", "{0} pages, {1}", "A4"));
        }
        finally
        {
            Loc.Table = null;
            CultureInfo.CurrentUICulture = saved;
        }
    }

    [Fact]
    public void LeftToRightIsNotIsolated() =>
        InTurkish(new() { ["Open {0}"] = "{0} dosyasını aç" }, () =>
            Assert.Equal("Scan.pdf dosyasını aç", Loc.T("Open {0}", "Scan.pdf")));

    [Fact]
    public void PluralCategories()
    {
        Assert.Equal("one", PluralRules.Category(1, "en"));
        Assert.Equal("other", PluralRules.Category(2, "en"));
        Assert.Equal("one", PluralRules.Category(1, "tr"));
        Assert.Equal("other", PluralRules.Category(0, "tr"));
        Assert.Equal("one", PluralRules.Category(1, "xx"));
    }

    public static IEnumerable<object[]> PluralSamples()
    {
        using var json = System.Text.Json.JsonDocument.Parse(File.ReadAllText(Path.Combine(AppContext.BaseDirectory, "plural.json")));
        foreach (var language in json.RootElement.EnumerateObject().Where(p => p.Name != "cldr"))
        {
            foreach (var category in language.Value.EnumerateObject())
            {
                var samples = category.Value.TryGetProperty("integer", out var integer) ? integer.GetString()! : "";
                foreach (var sample in samples.Split(','))
                {
                    var text = sample.Trim();
                    if (text.Length == 0 || text == "…" || text.Contains('.') || text.Contains('e')) continue;
                    var bounds = text.Split('~').Select(Scaled).ToArray();
                    for (var n = bounds[0]; n <= bounds[^1]; n++)
                        yield return [language.Name, n, category.Name];
                }
            }
        }

        static int Scaled(string part)
        {
            var bits = part.Split('c');
            return int.Parse(bits[0]) * (int)Math.Pow(10, bits.Length > 1 ? int.Parse(bits[1]) : 0);
        }
    }

    [Theory]
    [MemberData(nameof(PluralSamples))]
    public void PluralRuleMatchesTheCldrSamples(string language, int n, string category) =>
        Assert.Equal(category, PluralRules.Category(n, language));

    [Fact]
    public void UnknownLanguageUsesTheEnglishRule()
    {
        Assert.False(PluralRules.HasRule("xx"));
        Assert.Equal("one", PluralRules.Category(1, "xx"));
        Assert.Equal("other", PluralRules.Category(2, "xx"));
    }

    [Fact]
    public void PluralWalksTheCultureParents()
    {
        var saved = CultureInfo.CurrentUICulture;
        try
        {
            CultureInfo.CurrentUICulture = CultureInfo.GetCultureInfo("zh-HK");
            Loc.Table = new Dictionary<string, string> { ["{0} file|other"] = "{0} wen" };
            Assert.Equal("1 wen", Loc.Plural(1, "{0} file", "{0} files"));
        }
        finally
        {
            Loc.Table = null;
            CultureInfo.CurrentUICulture = saved;
        }
    }

    [Theory]
    [InlineData("ru-RU", 1, "1 file")]
    [InlineData("ru-RU", 21, "21 files")]
    [InlineData("ja-JP", 1, "1 file")]
    [InlineData("ja-JP", 5, "5 files")]
    public void PluralWithoutRowsUsesTheEnglishRule(string culture, int n, string expected)
    {
        var saved = CultureInfo.CurrentUICulture;
        try
        {
            CultureInfo.CurrentUICulture = CultureInfo.GetCultureInfo(culture);
            Loc.Table = new Dictionary<string, string>();
            Assert.Equal(expected, Loc.Plural(n, "{0} file", "{0} files"));
        }
        finally
        {
            Loc.Table = null;
            CultureInfo.CurrentUICulture = saved;
        }
    }

    [Fact]
    public void PluralFallsBackToTheOtherRow()
    {
        var saved = CultureInfo.CurrentUICulture;
        try
        {
            CultureInfo.CurrentUICulture = CultureInfo.GetCultureInfo("fr-FR");
            Loc.Table = new Dictionary<string, string>
            {
                ["{0} file|one"] = "{0} fichier",
                ["{0} file|other"] = "{0} fichiers",
            };
            Assert.Equal("1 fichier", Loc.Plural(1, "{0} file", "{0} files"));
            Assert.EndsWith(" fichiers", Loc.Plural(1000000, "{0} file", "{0} files"));
        }
        finally
        {
            Loc.Table = null;
            CultureInfo.CurrentUICulture = saved;
        }
    }

    [Fact]
    public void DecimalFollowsTheCulture()
    {
        Assert.Equal("2.0", Loc.Decimal(2, 1, 1));
        Assert.Equal("8.5", Loc.Decimal(8.5, 0, 2));
        Assert.Equal("5", Loc.Decimal(5, 0, 2));
        InTurkish(null, () =>
        {
            Assert.Equal("2,4", Loc.Decimal(2.4, 1, 1));
            Assert.Equal("8,27", Loc.Decimal(8.27, 0, 2));
        });
    }

    [Fact]
    public void XamlTextResolvesInTurkish() => InTurkish(null, () =>
    {
        Assert.Equal("Kaydet", Loc.T("Save"));
        Assert.Equal("İptal", Loc.T("Cancel"));
        Assert.Equal("Parola", Loc.T("Password"));
        Assert.Equal("Parolayı yeniden girin", Loc.T("Confirm|password field"));
        Assert.Equal("Yazdırmaya izin ver", Loc.T("Allow printing"));
        Assert.Equal("Kopyalamaya izin ver", Loc.T("Allow copying"));
        Assert.Equal("Metin ve görüntülerin kopyalanmasına izin ver", Loc.T("Allow copying text and images"));
    });

    [Fact]
    public void PlainNumbersAreNotGrouped()
    {
        InTurkish(null, () =>
        {
            Assert.Equal("1200", Loc.Plain(1200));
            Assert.Equal("1200 dpi", Loc.T("{0} dpi", Loc.Plain(1200)));
            Assert.Equal("1.200", Loc.T("{0}", 1200));
        });
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
