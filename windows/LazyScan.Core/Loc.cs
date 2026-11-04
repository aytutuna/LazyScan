using System.Globalization;
using System.Resources;
using System.Text;

namespace LazyScan.Core;

// Port of Sources/LazyScanKit/Localization/L10n.swift. The English text is the key and the
// fallback: with no entry in Strings.<language>.resx the English comes back unchanged.

public static class Loc
{
    private static readonly ResourceManager Resources = new("LazyScan.Core.Strings", typeof(Loc).Assembly);

    // Stands in for the resource lookup in tests and in Troubleshooter.Report, which is always
    // English; flows with the async context, so parallel tests do not see each other's table.
    private static readonly AsyncLocal<IReadOnlyDictionary<string, string>?> Override = new();

    internal static IReadOnlyDictionary<string, string>? Table
    {
        get => Override.Value;
        set => Override.Value = value;
    }

    /// <summary>
    /// Runs <paramref name="body"/> with every text and number in English, for what goes into a
    /// support report.
    /// </summary>
    public static T English<T>(Func<T> body)
    {
        var saved = Override.Value;
        var culture = CultureInfo.CurrentCulture;
        var uiCulture = CultureInfo.CurrentUICulture;
        Override.Value = new Dictionary<string, string>();
        CultureInfo.CurrentCulture = CultureInfo.GetCultureInfo("en-US");
        CultureInfo.CurrentUICulture = CultureInfo.GetCultureInfo("en-US");
        try { return body(); }
        finally
        {
            Override.Value = saved;
            CultureInfo.CurrentCulture = culture;
            CultureInfo.CurrentUICulture = uiCulture;
        }
    }

    /// <summary>
    /// The text for <paramref name="english"/> in the UI language, with {0}, {1}... filled from
    /// <paramref name="args"/>. A trailing |context (as in "Scan|noun") tells translators which
    /// word is meant and is never shown in English.
    /// </summary>
    public static string T(string english, params object?[] args) =>
        Format(Lookup(english) ?? StripContext(english), args);

    /// <summary>
    /// <paramref name="one"/> when the language's plural rule says so for <paramref name="n"/>, else
    /// <paramref name="other"/>. {0} is n, written in the current number format, and
    /// <paramref name="args"/> follow from {1}.
    /// </summary>
    public static string Plural(int n, string one, string other, params object?[] args)
    {
        var category = PluralCategory(n, Language());
        var english = category == "one" ? one : other;
        var found = Lookup(one + "|" + category);
        return Format(found ?? StripContext(english), [n, .. args]);
    }

    // One rule per language, the CLDR cardinal rules. Add a language here when it gets a column
    // in the catalog; an unknown language uses the English rule.
    private static readonly Dictionary<string, Func<int, string>> PluralRules = new()
    {
        ["en"] = n => n == 1 ? "one" : "other",
        ["tr"] = n => n == 1 ? "one" : "other",
    };

    internal static string PluralCategory(int n, string language) =>
        (PluralRules.GetValueOrDefault(language) ?? PluralRules["en"])(n);

    private static string Language() => CultureInfo.CurrentUICulture.TwoLetterISOLanguageName;

    private static string? Lookup(string key)
    {
        if (Override.Value is { } table) return table.GetValueOrDefault(key);
        return Resources.GetString(key);
    }

    private static string StripContext(string text)
    {
        var bar = text.LastIndexOf('|');
        return bar < 0 ? text : text[..bar];
    }

    // One pass, so a value that itself contains "{1}" is left alone. A placeholder with no
    // argument stays as written. Numbers are written in the current culture's format.
    private static string Format(string text, object?[] args)
    {
        if (args.Length == 0 || !text.Contains('{')) return text;
        var result = new StringBuilder();
        var i = 0;
        while (i < text.Length)
        {
            var open = text.IndexOf('{', i);
            if (open < 0) break;
            result.Append(text, i, open - i);
            var close = text.IndexOf('}', open + 1);
            if (close > open + 1
                && int.TryParse(text.AsSpan(open + 1, close - open - 1), NumberStyles.None, CultureInfo.InvariantCulture, out var index)
                && index < args.Length)
            {
                result.Append(Describe(args[index]));
                i = close + 1;
            }
            else
            {
                result.Append('{');
                i = open + 1;
            }
        }
        return result.Append(text, i, text.Length - i).ToString();
    }

    // Halves round to even before formatting, as NumberFormatter does on Apple platforms.
    private static string Describe(object? arg) => arg switch
    {
        float f => Number(Math.Round((double)f, 3, MidpointRounding.ToEven)),
        double d => Number(Math.Round(d, 3, MidpointRounding.ToEven)),
        decimal m => Number(Math.Round(m, 3, MidpointRounding.ToEven)),
        sbyte or byte or short or ushort or int or uint or long or ulong or nint or nuint => Number(arg),
        _ => arg?.ToString() ?? "",
    };

    /// <summary>
    /// <paramref name="value"/> in the current number format, with between <paramref name="minDigits"/>
    /// and <paramref name="maxDigits"/> decimals.
    /// </summary>
    public static string Decimal(double value, int minDigits, int maxDigits) =>
        value.ToString("#,##0." + new string('0', minDigits) + new string('#', maxDigits - minDigits), CultureInfo.CurrentCulture);

    private static string Number(object value) =>
        ((IFormattable)value).ToString("#,##0.###", CultureInfo.CurrentCulture);
}
