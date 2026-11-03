using System.Text.RegularExpressions;

namespace LazyScan.Core;

// Port of Sources/LazyScanKit/Core/StatusLine.swift: the status line's short text. Both apps
// show at most six words of their status sentence, facts only, and keep the whole sentence as the
// line's accessible name.
//
// The six words are counted on the English text of each piece, whatever the language, so every
// language shows the same facts and the views only truncate what still does not fit. The settings
// notes are matched from their catalog entries, so they work in any language. The message heads
// (Added, Saved, Found, the one-sided mark, "Ready for “", "Page queue cleared", "Reading the text
// of page", "Sent ") are still matched in English: their messages ("Saved {0}", "Saved {0}: {1}",
// "Saved {0}{1}", "Ready for “{0}”.", "Page queue cleared.", "Reading the text of page {0}…", the
// "Sent the ..." keys) must not get translations until the app hands StatusLine structured input
// instead of a sentence.

/// <summary>
/// The status line's visible text: at most <see cref="MaxWords"/> words, facts only. The full
/// sentence stays the status line's accessible name, so screen readers hear all of it.
/// </summary>
public static class StatusLine
{
    public const int MaxWords = 6;

    private static readonly Regex WordToken = new(@"[\p{L}\p{N}]", RegexOptions.Compiled);

    /// <summary>Words as the text spec counts them: whitespace-separated tokens with a letter or digit.</summary>
    public static int Words(string text) =>
        text.Split((char[]?)null, StringSplitOptions.RemoveEmptyEntries).Count(t => WordToken.IsMatch(t));

    /// <summary>A piece of the line with its word count in English.</summary>
    private readonly record struct Piece(string Text, int Words);

    /// <summary><paramref name="render"/>'s text in the current language, counted as the English text it stands for.</summary>
    private static Piece MakePiece(Func<string> render)
    {
        var saved = Loc.Table;
        Loc.Table = new Dictionary<string, string>();
        int english;
        try { english = Words(render()); }
        finally { Loc.Table = saved; }
        return new(render(), english);
    }

    /// <summary>
    /// A warning's short form, and the form that follows another fact on the line ("Ready — Demo ·
    /// feeder used"). Written out for each, so a language can start the second one the way it needs to.
    /// </summary>
    private readonly record struct Warning(Piece Short, Piece Inline);

    /// <summary>
    /// The pattern for the catalog sentence <paramref name="english"/> as the current language words
    /// it, with each {n} replaced by <c>groups[n]</c>.
    /// </summary>
    private static string Pattern(string english, params string[] groups)
    {
        string result = Regex.Escape(Loc.T(english));
        for (int i = 0; i < groups.Length; i++) result = result.Replace($@"\{{{i}}}", groups[i]);
        return result;
    }

    /// <summary>
    /// The sentences <see cref="SettingsAdapter"/> adds when a setting had to change for the scanner,
    /// each with its short form (made from the match, for the number it captures): a warning stays
    /// visible, not only in the accessible name. Built per call: the patterns follow the language.
    /// </summary>
    private static (Regex Note, Func<Match, Warning> Warn)[] SettingsNotes()
    {
        string papers = $"(?:{string.Join("|", Enum.GetValues<PaperSize>().Select(p => Regex.Escape(p.Label())))})";
        Func<Match, Warning> paper = _ => new(MakePiece(() => Loc.T("Paper size Automatic")), MakePiece(() => Loc.T("paper size Automatic|after another fact")));
        return
        [
            (new(Pattern("This scanner has no flatbed, so the document feeder is used.")),
             _ => new(MakePiece(() => Loc.T("Feeder used")), MakePiece(() => Loc.T("feeder used|after another fact")))),
            (new(Pattern("This scanner has no document feeder, so the flatbed is used.")),
             _ => new(MakePiece(() => Loc.T("Flatbed used")), MakePiece(() => Loc.T("flatbed used|after another fact")))),
            (new(Pattern("This scanner's feeder scans one side at a time, so you'll turn the stack over by hand.")),
             _ => new(MakePiece(() => Loc.T("Two-sided by hand")), MakePiece(() => Loc.T("two-sided by hand|after another fact")))),
            (new(Pattern("{0} paper does not fit this scanner's feeder, so the paper size is Automatic.", papers)), paper),
            (new(Pattern("{0} paper does not fit this scanner's glass, so the paper size is Automatic.", papers)), paper),
            (new(Pattern("This scanner does not offer {0} dpi, so {1} dpi is used.", @"\d+", @"(\d+)")),
             m =>
             {
                 var text = MakePiece(() => Loc.T("{0} dpi used", m.Groups[1].Value));
                 return new(text, text);
             }),
        ];
    }

    /// <summary>A two-sided scan came back with one side of each sheet.</summary>
    private const string OneSidedMark = "the scanner did not scan both sides";

    /// <param name="message">The app's status sentence.</param>
    /// <param name="deviceName">The connected scanner, for "Ready — Demo Scanner" after a task is picked.</param>
    /// <remarks>
    /// A setting changed for the scanner, or a two-sided scan that came back one-sided, keeps a short
    /// warning on the line ("Ready — Demo · feeder used", "3 pages added · one side only"); when the
    /// line can't hold both, the warnings win.
    /// </remarks>
    public static string Short(string message, string? deviceName = null)
    {
        string text = message.Trim();
        if (text.Length == 0) return "";
        var (warnings, notesAt) = FindWarnings(text);
        var head = notesAt > 0 ? Head(text[..notesAt].Trim(), deviceName) : new Piece("", 0);
        return Compose(head, warnings);
    }

    /// <summary>
    /// <paramref name="head"/> with the short warnings found in <paramref name="message"/>, the same
    /// way <see cref="Short"/> adds them: "Saved · 600 dpi used", or the warnings alone when the line
    /// can't hold both; just <paramref name="head"/> when there are none.
    /// </summary>
    public static string WithWarnings(string head, string message) => Compose(new(head, Words(head)), WarningsIn(message));

    /// <summary>
    /// The short warnings in <paramref name="message"/>, in the order they come: a setting changed for
    /// the scanner ("600 dpi used"), a two-sided scan that came back one-sided ("One side only").
    /// </summary>
    public static IReadOnlyList<string> Warnings(string message) => WarningsIn(message).Select(w => w.Short.Text).ToList();

    private static IReadOnlyList<Warning> WarningsIn(string message) => FindWarnings(message.Trim()).Warnings;

    /// <summary>
    /// What the status line shows while the app is idle: nothing while a review shows its own title
    /// (<paramref name="reviewShown"/>), "Saved" with any warning while the saved files' bar shows
    /// (<paramref name="savedShown"/>, for a message about a save), else <see cref="Short"/>.
    /// </summary>
    public static string Shown(string message, string? deviceName, bool reviewShown, bool savedShown)
    {
        if (reviewShown) return "";
        if (savedShown && message.TrimStart().StartsWith("Saved", StringComparison.Ordinal)) return Compose(MakePiece(() => Loc.T("Saved")), WarningsIn(message));
        return Short(message, deviceName);
    }

    /// <summary>The warnings in <paramref name="text"/>, and where the first settings note starts (the text's length when none does).</summary>
    private static (List<Warning> Warnings, int NotesAt) FindWarnings(string text)
    {
        // The notes are appended after the message: the message is what comes before the first one.
        var warnings = new List<(int At, Warning Warning)>();
        int notesAt = text.Length;
        foreach (var (note, warn) in SettingsNotes())
        {
            foreach (Match m in note.Matches(text))
            {
                warnings.Add((m.Index, warn(m)));
                notesAt = Math.Min(notesAt, m.Index);
            }
        }
        int oneSided = text.IndexOf(OneSidedMark, StringComparison.Ordinal);
        if (oneSided >= 0) warnings.Add((oneSided, new(MakePiece(() => Loc.T("One side only")), MakePiece(() => Loc.T("one side only|after another fact")))));
        return (warnings.OrderBy(w => w.At).Select(w => w.Warning).ToList(), notesAt);
    }

    /// <summary>The head, then the warnings while they fit; when the line can't hold both, the warnings win.</summary>
    private static string Compose(Piece head, IReadOnlyList<Warning> warnings)
    {
        if (warnings.Count == 0) return head.Text;
        if (head.Text.Length > 0 && head.Words + warnings.Sum(w => w.Inline.Words) <= MaxWords)
        {
            return string.Join(" · ", warnings.Select(w => w.Inline.Text).Prepend(head.Text));
        }
        // Not room for the message too: the warnings alone, as many as fit, then how many more.
        string shown = warnings[0].Short.Text;
        int shownWords = warnings[0].Short.Words;
        int i = 1;
        while (i < warnings.Count)
        {
            // While more would follow, keep a word free for "+N".
            if (shownWords + warnings[i].Inline.Words > MaxWords - (i < warnings.Count - 1 ? 1 : 0)) break;
            shown += " · " + warnings[i].Inline.Text;
            shownWords += warnings[i].Inline.Words;
            i++;
        }
        return i < warnings.Count ? shown + " " + Loc.T("+{0}", warnings.Count - i) : shown;
    }

    /// <summary>The short form of the message itself (without the notes after it).</summary>
    private static Piece Head(string text, string? deviceName)
    {
        if (text.Length == 0) return new("", 0);
        if (text.StartsWith("Ready for “", StringComparison.Ordinal))
        {
            return deviceName is { Length: > 0 } name ? MakePiece(() => Loc.T("Ready — {0}", name)) : MakePiece(() => Loc.T("Ready"));
        }
        if (Regex.Match(text, @"^Added (\d[\d,.\u00A0\u202F]*) (?:page|pages)\b") is { Success: true } added)
        {
            int count = Count(added.Groups[1]);
            var head = count == 1 && Regex.Match(text, @"— (\d[\d,.\u00A0\u202F]*) in queue") is { Success: true } queue
                ? MakePiece(() => Loc.T("Page {0} added", Count(queue.Groups[1])))
                : MakePiece(() => Loc.Plural(count, "{0} page added", "{0} pages added"));
            if (Regex.Match(text, @"(\d[\d,.\u00A0\u202F]*) looks? blank") is { Success: true } blank)
            {
                head = Append(head, MakePiece(() => Loc.Plural(Count(blank.Groups[1]), "{0} blank", "{0} blank")));
            }
            if (Regex.Match(text, @"(\d[\d,.\u00A0\u202F]*) spreads? split into pages") is { Success: true } spreads)
            {
                head = Append(head, MakePiece(() => Loc.Plural(Count(spreads.Groups[1]), "{0} spread split", "{0} spreads split")));
            }
            return head;
        }
        if (Regex.Match(text, @"^(?:Cancelled — )?Saved (\d[\d,.\u00A0\u202F]*) (photos?|receipts?|documents?|files?|PDFs?|copies)\b",
                        RegexOptions.IgnoreCase) is { Success: true } savedMany)
        {
            return SavedHead(Count(savedMany.Groups[1]), savedMany.Groups[2].Value.ToLowerInvariant());
        }
        if (text.StartsWith("Saved ", StringComparison.Ordinal)) return MakePiece(() => Loc.T("Saved"));
        if (Regex.Match(text, @"^Found (\d[\d,.\u00A0\u202F]*) (photos?|receipts?)\b") is { Success: true } found)
        {
            int count = Count(found.Groups[1]);
            return found.Groups[2].Value.StartsWith("photo", StringComparison.Ordinal)
                ? MakePiece(() => Loc.Plural(count, "Found {0} photo", "Found {0} photos"))
                : MakePiece(() => Loc.Plural(count, "Found {0} receipt", "Found {0} receipts"));
        }
        if (text.StartsWith("Page queue cleared", StringComparison.Ordinal)) return MakePiece(() => Loc.T("Queue cleared"));
        if (Regex.Match(text, @"^Reading the text of page (\d[\d,.\u00A0\u202F]*)(?: of (\d[\d,.\u00A0\u202F]*))?…") is { Success: true } reading)
        {
            return reading.Groups[2].Success
                ? MakePiece(() => Loc.T("Reading page {0} of {1}…", Count(reading.Groups[1]), Count(reading.Groups[2])))
                : MakePiece(() => Loc.T("Reading page {0}…", Count(reading.Groups[1])));
        }
        if (Regex.Match(text, @"^Adding (\d[\d,.\u00A0\u202F]*) pages? to .+…$") is { Success: true } adding)
        {
            return MakePiece(() => Loc.Plural(Count(adding.Groups[1]), "Adding {0} page…", "Adding {0} pages…"));
        }
        if (text.StartsWith("Sent ", StringComparison.Ordinal)) return MakePiece(() => Loc.T("Sent to the printer"));

        // Anything else: its first sentence, then what comes before a dash or a colon, then its whole facts.
        string first = FirstSentence(text);
        if (Words(first) <= MaxWords) return new(first, Words(first));
        foreach (string mark in new[] { " — ", ": ", ", " })
        {
            int at = first.IndexOf(mark, StringComparison.Ordinal);
            if (at > 0 && Words(first[..at]) <= MaxWords) return new(first[..at], Words(first[..at]));
        }
        // Facts joined by " · " ("9 pages · 3 documents · 2 separator pages skipped"): the whole facts that fit.
        var facts = first.Split(" · ");
        if (facts.Length > 1 && Words(facts[0]) <= MaxWords)
        {
            string shown = facts[0];
            for (int i = 1; i < facts.Length && Words($"{shown} · {facts[i]}") <= MaxWords; i++)
            {
                shown = $"{shown} · {facts[i]}";
            }
            return new(shown, Words(shown));
        }
        var tokens = first.Split(' ', StringSplitOptions.RemoveEmptyEntries);
        var kept = new List<string>();
        int words = 0;
        foreach (var token in tokens)
        {
            if (WordToken.IsMatch(token) && ++words > MaxWords) break;
            kept.Add(token);
        }
        return new(string.Join(' ', kept).TrimEnd(',', ':', ';', '.', ' ') + "…", Math.Min(words, MaxWords));
    }

    private static int Count(Group digits) => int.Parse(new string(digits.Value.Where(char.IsDigit).ToArray()), System.Globalization.CultureInfo.InvariantCulture);

    /// <summary>"Saved 3 photos" for the kind of file <paramref name="noun"/> names (lower case, as the message has it).</summary>
    private static Piece SavedHead(int count, string noun) => noun switch
    {
        _ when noun.StartsWith("photo", StringComparison.Ordinal) => MakePiece(() => Loc.Plural(count, "Saved {0} photo", "Saved {0} photos")),
        _ when noun.StartsWith("receipt", StringComparison.Ordinal) => MakePiece(() => Loc.Plural(count, "Saved {0} receipt", "Saved {0} receipts")),
        _ when noun.StartsWith("document", StringComparison.Ordinal) => MakePiece(() => Loc.Plural(count, "Saved {0} document", "Saved {0} documents")),
        _ when noun.StartsWith("file", StringComparison.Ordinal) => MakePiece(() => Loc.Plural(count, "Saved {0} file", "Saved {0} files")),
        _ when noun.StartsWith("pdf", StringComparison.Ordinal) => MakePiece(() => Loc.Plural(count, "Saved {0} PDF", "Saved {0} PDFs")),
        _ => MakePiece(() => Loc.Plural(count, "Saved {0} copy", "Saved {0} copies")),
    };

    /// <summary>"6 pages added · 1 blank", while the words stay within the limit.</summary>
    private static Piece Append(Piece head, Piece part) =>
        head.Words + part.Words <= MaxWords ? new($"{head.Text} · {part.Text}", head.Words + part.Words) : head;

    /// <summary>The first sentence without its full stop ("…" is kept: it says work is under way).</summary>
    private static string FirstSentence(string text)
    {
        for (int i = 0; i < text.Length - 2; i++)
        {
            if (text[i] is '.' or '!' or '?' && text[i + 1] == ' ' && (char.IsUpper(text[i + 2]) || char.IsDigit(text[i + 2])))
            {
                return text[..i];
            }
        }
        return text.EndsWith('.') && !text.EndsWith("…", StringComparison.Ordinal) ? text[..^1] : text;
    }
}
