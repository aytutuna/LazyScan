using System.Globalization;
using System.Runtime.CompilerServices;
using System.Text.Json;
using Xunit;

namespace LazyScan.Core.Tests;

public sealed class PdfProtectionTextTests
{
    // The Turkish rows of l10n/shared.json, as the resource table would hold them.
    private static Dictionary<string, string> TurkishTable([CallerFilePath] string source = "")
    {
        var catalog = Path.Combine(Path.GetDirectoryName(source)!, "..", "..", "l10n", "shared.json");
        using var doc = JsonDocument.Parse(File.ReadAllText(catalog));
        var table = new Dictionary<string, string>();
        foreach (var entry in doc.RootElement.EnumerateObject())
        {
            var tr = entry.Value.GetProperty("tr");
            if (tr.ValueKind == JsonValueKind.String) table[entry.Name] = tr.GetString()!;
            else foreach (var form in tr.EnumerateObject()) table[entry.Name + "|" + form.Name] = form.Value.GetString()!;
        }
        return table;
    }

    [Fact]
    public void EnglishIsTheDefault()
    {
        Assert.Equal("Set a PDF password", PdfProtection.DialogTitle);
        Assert.Equal("Not saved: no password was given for the protected PDF. The page is in the queue: save with a password, or turn the password off.",
            PdfProtection.KeptInQueueMessage(1));
        Assert.Equal("Not saved: no password was given for the protected PDF. The 3 pages are in the queue: save with a password, or turn the password off.",
            PdfProtection.KeptInQueueMessage(3));
    }

    [Fact]
    public void TurkishTexts() => InTurkish(() =>
    {
        Assert.Equal("Parola gerektir", PdfProtection.OptionLabel);
        Assert.Equal("PDF parolası belirleyin", PdfProtection.DialogTitle);
        Assert.Equal("PDF/A ile kullanılamaz", PdfProtection.NotWithArchivalReason);
        Assert.Equal("Kaydedilmedi: korumalı PDF için parola girilmedi.", PdfProtection.NotSavedMessage);
        Assert.Equal("Bazı uygulamalar bu ayarları yok sayar.", PdfProtection.PermissionsShortNote);
        foreach (var text in new[] { PdfProtection.OptionHint, PdfProtection.OptionHelp, PdfProtection.DialogMessage, PdfProtection.DialogHelp, PdfProtection.PermissionsNote })
        {
            Assert.False(text.StartsWith("PDFs ") || text.StartsWith("Most "));
        }
    });

    [Fact]
    public void TurkishKeptInQueueNounStaysSingular() => InTurkish(() =>
    {
        Assert.Equal("Kaydedilmedi: korumalı PDF için parola girilmedi. Sayfa kuyrukta: parolayla kaydedin ya da parola korumasını kapatın.", PdfProtection.KeptInQueueMessage(1));
        Assert.Equal("Kaydedilmedi: korumalı PDF için parola girilmedi. 3 sayfa kuyrukta: parolayla kaydedin ya da parola korumasını kapatın.", PdfProtection.KeptInQueueMessage(3));
        Assert.Contains("1.234 sayfa kuyrukta", PdfProtection.KeptInQueueMessage(1234));
    });

    [Fact]
    public void TurkishComesFromTheSatelliteResources()
    {
        var ui = CultureInfo.CurrentUICulture;
        try
        {
            CultureInfo.CurrentUICulture = CultureInfo.GetCultureInfo("tr-TR");
            Assert.Equal("PDF parolası belirleyin", PdfProtection.DialogTitle);
            Assert.Contains("3 sayfa kuyrukta", PdfProtection.KeptInQueueMessage(3));
        }
        finally { CultureInfo.CurrentUICulture = ui; }
    }

    private static void InTurkish(Action body)
    {
        var table = TurkishTable();
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
