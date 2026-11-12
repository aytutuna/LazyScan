namespace LazyScan.App.Services;

/// <summary>
/// Which Windows OCR recognizers read a page, decided from the installed language packs alone so it
/// can be tested without any.
/// </summary>
internal static class OcrLanguagePlan
{
    /// <summary>An installed recognizer: its language tag and writing system (ISO 15924, "Latn").</summary>
    internal readonly record struct Pack(string Tag, string Script);

    /// <summary>The installed tag the chosen one names, or null for Automatic or a pack that is gone.</summary>
    public static string? Chosen(string? chosen, IReadOnlyList<Pack> installed)
    {
        if (string.IsNullOrEmpty(chosen)) return null;
        foreach (var pack in installed)
        {
            if (string.Equals(pack.Tag, chosen, StringComparison.OrdinalIgnoreCase)) return pack.Tag;
        }
        return null;
    }

    /// <summary>
    /// The recognizers Automatic compares: the profile language's first, then the other Latin-script
    /// packs, at most <paramref name="max"/>. One entry or none means there is nothing to compare.
    /// </summary>
    public static List<string> Automatic(string? profileTag, IReadOnlyList<Pack> installed, int max)
    {
        var tags = new List<string>();
        var profile = installed.Where(p => profileTag is not null && Same(p.Tag, profileTag)).ToList();
        if (profile.Count > 0)
        {
            if (profile[0].Script != "Latn") return [profile[0].Tag];
            tags.Add(profile[0].Tag);
        }
        foreach (var pack in installed)
        {
            if (tags.Count >= max) break;
            if (pack.Script != "Latn" || tags.Any(t => Same(t, pack.Tag))) continue;
            tags.Add(pack.Tag);
        }
        return tags;
    }

    private static bool Same(string a, string b) => string.Equals(a, b, StringComparison.OrdinalIgnoreCase);
}
