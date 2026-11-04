using System.Text.RegularExpressions;

namespace LazyScan.Core;

// Port of Sources/LazyScanKit/Core/StatusLine.swift: the status line's short text. Both apps
// show at most six words of their status sentence, facts only, and keep the whole sentence as the
// line's accessible name.
//
// The producers of a status hand over what the line needs next to the sentence (StatusDetail:
// the kind of message and the warnings), so nothing here reads the sentence's language. The six
// words are counted on the English text of each piece, whatever the language, so every language
// shows the same facts and the views only truncate what still does not fit.

/// <summary>A kind of file a status counts.</summary>
public enum FileKind
{
    Photo,
    Receipt,
    Pdf,
}

/// <summary>What a status says about the message itself, for the short line.</summary>
public abstract record StatusHead
{
    /// <summary>A task was picked: "Ready — Demo Scanner" (the scanner connected) or "Ready".</summary>
    public sealed record ReadyForTask : StatusHead;

    /// <summary>
    /// Pages joined the queue; <paramref name="Queue"/> is the queue's length (null when the message
    /// gives none), <paramref name="Blank"/> and <paramref name="Split"/> the blank pages and the
    /// spreads split among them.
    /// </summary>
    public sealed record PagesAdded(int Count, int? Queue, int Blank, int Split) : StatusHead;

    /// <summary>A save, whatever it wrote: "Saved".</summary>
    public sealed record Saved : StatusHead;

    /// <summary>A save of <paramref name="Count"/> files of one kind: "Saved 3 photos".</summary>
    public sealed record SavedFiles(int Count, FileKind Kind) : StatusHead;

    /// <summary>A review's find: "Found 3 photos".</summary>
    public sealed record Found(int Count, FileKind Kind) : StatusHead;

    public sealed record QueueCleared : StatusHead;

    public sealed record ReadingPage(int Page, int? Of) : StatusHead;

    public sealed record AddingPages(int Count) : StatusHead;

    public sealed record SentToPrinter : StatusHead;

    /// <summary>The message is about a save.</summary>
    internal bool IsSave => this is Saved or SavedFiles;
}

/// <summary>A short warning a status keeps on the line.</summary>
public abstract record StatusWarning
{
    public sealed record FeederUsed : StatusWarning;

    public sealed record FlatbedUsed : StatusWarning;

    public sealed record TwoSidedByHand : StatusWarning;

    public sealed record PaperAutomatic : StatusWarning;

    public sealed record DpiUsed(int Dpi) : StatusWarning;

    /// <summary>A two-sided scan came back with one side of each sheet.</summary>
    public sealed record OneSideOnly : StatusWarning;
}

/// <summary>
/// What goes with a status sentence for the short line: the kind of message, the warnings in the
/// order they come, and for a message with no kind the sentence without the settings notes after it.
/// </summary>
public sealed record StatusDetail(StatusHead? Head = null, IReadOnlyList<StatusWarning>? Warnings = null, string? Body = null);

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

    private static Warning WarningOf(StatusWarning warning)
    {
        switch (warning)
        {
            case StatusWarning.FeederUsed:
                return new(MakePiece(() => Loc.T("Feeder used")), MakePiece(() => Loc.T("feeder used|after another fact")));
            case StatusWarning.FlatbedUsed:
                return new(MakePiece(() => Loc.T("Flatbed used")), MakePiece(() => Loc.T("flatbed used|after another fact")));
            case StatusWarning.TwoSidedByHand:
                return new(MakePiece(() => Loc.T("Two-sided by hand")), MakePiece(() => Loc.T("two-sided by hand|after another fact")));
            case StatusWarning.PaperAutomatic:
                return new(MakePiece(() => Loc.T("Paper size Automatic")), MakePiece(() => Loc.T("paper size Automatic|after another fact")));
            case StatusWarning.DpiUsed dpi:
                var text = MakePiece(() => Loc.T("{0} dpi used", dpi.Dpi.ToString(System.Globalization.CultureInfo.InvariantCulture)));
                return new(text, text);
            default:
                return new(MakePiece(() => Loc.T("One side only")), MakePiece(() => Loc.T("one side only|after another fact")));
        }
    }

    private static List<Warning> WarningsOf(StatusDetail detail) => (detail.Warnings ?? []).Select(WarningOf).ToList();

    /// <param name="message">The app's status sentence.</param>
    /// <param name="detail">What its producer says about it.</param>
    /// <param name="deviceName">The connected scanner, for "Ready — Demo Scanner" after a task is picked.</param>
    /// <remarks>
    /// A setting changed for the scanner, or a two-sided scan that came back one-sided, keeps a short
    /// warning on the line ("Ready — Demo · feeder used", "3 pages added · one side only"); when the
    /// line can't hold both, the warnings win.
    /// </remarks>
    public static string Short(string message, StatusDetail? detail = null, string? deviceName = null)
    {
        detail ??= new StatusDetail();
        if (message.Trim().Length == 0) return "";
        return Compose(Head((detail.Body ?? message).Trim(), detail.Head, deviceName), WarningsOf(detail));
    }

    /// <summary>
    /// The short warnings of <paramref name="detail"/>, in the order they come: a setting changed for
    /// the scanner ("600 dpi used"), a two-sided scan that came back one-sided ("One side only").
    /// </summary>
    public static IReadOnlyList<string> Warnings(StatusDetail detail) => WarningsOf(detail).Select(w => w.Short.Text).ToList();

    /// <summary>
    /// What the status line shows while the app is idle: nothing while a review shows its own title
    /// (<paramref name="reviewShown"/>), "Saved" with any warning while the saved files' bar shows
    /// (<paramref name="savedShown"/>, for a message about a save), else <see cref="Short"/>.
    /// </summary>
    public static string Shown(string message, StatusDetail detail, string? deviceName, bool reviewShown, bool savedShown)
    {
        if (reviewShown) return "";
        if (savedShown && detail.Head?.IsSave == true) return Compose(MakePiece(() => Loc.T("Saved")), WarningsOf(detail));
        return Short(message, detail, deviceName);
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
    private static Piece Head(string text, StatusHead? head, string? deviceName)
    {
        switch (head)
        {
            case StatusHead.ReadyForTask:
                return deviceName is { Length: > 0 } name ? MakePiece(() => Loc.T("Ready — {0}", name)) : MakePiece(() => Loc.T("Ready"));
            case StatusHead.PagesAdded added:
                var shown = added.Count == 1 && added.Queue is int queue
                    ? MakePiece(() => Loc.T("Page {0} added", queue))
                    : MakePiece(() => Loc.Plural(added.Count, "{0} page added", "{0} pages added"));
                if (added.Blank > 0) shown = Append(shown, MakePiece(() => Loc.Plural(added.Blank, "{0} blank", "{0} blank")));
                if (added.Split > 0) shown = Append(shown, MakePiece(() => Loc.Plural(added.Split, "{0} spread split", "{0} spreads split")));
                return shown;
            case StatusHead.Saved:
                return MakePiece(() => Loc.T("Saved"));
            case StatusHead.SavedFiles saved:
                return saved.Kind switch
                {
                    FileKind.Photo => MakePiece(() => Loc.Plural(saved.Count, "Saved {0} photo", "Saved {0} photos")),
                    FileKind.Receipt => MakePiece(() => Loc.Plural(saved.Count, "Saved {0} receipt", "Saved {0} receipts")),
                    _ => MakePiece(() => Loc.Plural(saved.Count, "Saved {0} PDF", "Saved {0} PDFs")),
                };
            case StatusHead.Found found:
                return found.Kind == FileKind.Receipt
                    ? MakePiece(() => Loc.Plural(found.Count, "Found {0} receipt", "Found {0} receipts"))
                    : MakePiece(() => Loc.Plural(found.Count, "Found {0} photo", "Found {0} photos"));
            case StatusHead.QueueCleared:
                return MakePiece(() => Loc.T("Queue cleared"));
            case StatusHead.ReadingPage reading:
                return reading.Of is int total
                    ? MakePiece(() => Loc.T("Reading page {0} of {1}…", reading.Page, total))
                    : MakePiece(() => Loc.T("Reading page {0}…", reading.Page));
            case StatusHead.AddingPages adding:
                return MakePiece(() => Loc.Plural(adding.Count, "Adding {0} page…", "Adding {0} pages…"));
            case StatusHead.SentToPrinter:
                return MakePiece(() => Loc.T("Sent to the printer"));
            default:
                return Generic(text);
        }
    }

    /// <summary>A message with no kind: its first sentence, then what comes before a dash or a colon, then its whole facts.</summary>
    private static Piece Generic(string text)
    {
        if (text.Length == 0) return new("", 0);
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

    /// <summary>"6 pages added · 1 blank", while the words stay within the limit.</summary>
    private static Piece Append(Piece head, Piece part) =>
        head.Words + part.Words <= MaxWords ? new($"{head.Text} · {part.Text}", head.Words + part.Words) : head;

    /// <summary>The first sentence without its full stop ("…" is kept: it says work is under way).</summary>
    private static string FirstSentence(string text)
    {
        for (int i = 0; i < text.Length; i++)
        {
            if (text[i] is '\u3002' or '\uFF01' or '\uFF1F')
            {
                return text[..i];
            }
            if (i + 2 < text.Length && text[i] is '.' or '!' or '?' or '\u061F' or '\u0964' && text[i + 1] == ' '
                && (char.IsLetter(text[i + 2]) && !char.IsLower(text[i + 2]) || char.IsDigit(text[i + 2])))
            {
                return text[..i];
            }
        }
        return text.EndsWith('.') && !text.EndsWith("…", StringComparison.Ordinal) ? text[..^1] : text;
    }
}
