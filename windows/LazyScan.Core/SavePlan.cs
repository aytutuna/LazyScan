namespace LazyScan.Core;

// Twin of Sources/LazyScanKit/Core/SavePlan.swift.

/// <summary>A document of the queue as saved: its number (from 1), its pages in order and its name, if any.</summary>
public sealed record SaveDocument(int Number, IReadOnlyList<ScannedPage> Pages, string? Label);

/// <summary>
/// What saving the collected pages writes: the documents of the split plan
/// (<see cref="DocumentSplitter"/>), each its own file, and what is left out. The files of one
/// save are written all or nothing (<see cref="WriteAllOrNothingAsync"/>): a save that fails or is
/// cancelled part-way removes what it wrote, so the queue, which stays as it was, can be saved
/// again without duplicates.
/// </summary>
public sealed record SavePlan(IReadOnlyList<SaveDocument> Documents, int SeparatorPages, int SkippedPages)
{
    /// <summary>The plan for saving <paramref name="queue"/> with <paramref name="options"/>.</summary>
    public static SavePlan Make(IReadOnlyList<ScannedPage> queue, DocumentOptions options)
    {
        var plan = DocumentSplitter.Plan(queue, options);
        var documents = plan.Documents
            .Select(d => new SaveDocument(d.Number, d.Pages.Select(i => queue[i]).ToList(), d.Label))
            .ToList();
        return new SavePlan(documents, plan.SeparatorCount, plan.SkippedCount);
    }

    /// <summary>The pages written, in every document.</summary>
    public int PageCount => Documents.Sum(d => d.Pages.Count);

    /// <summary>Nothing would be written: every page is left out.</summary>
    public bool IsEmpty => Documents.Count == 0;

    /// <summary>More than one file is written.</summary>
    public bool IsSplit => Documents.Count > 1;

    /// <summary>The {index} of the document's file name: its number when the queue is split, else none.</summary>
    public int? FileIndex(SaveDocument document) => IsSplit ? document.Number : null;

    /// <summary>
    /// The save button: "Save 3 PDFs (7 pages)" for a split queue, otherwise
    /// <see cref="OutputFormats.SaveTitle(OutputFormat, int)"/> ("Save PDF (7 pages)").
    /// </summary>
    public string SaveTitle(OutputFormat format)
    {
        if (!IsSplit) return OutputFormats.SaveTitle(format, PageCount);
        return OutputFormats.QueueFormat(format) switch
        {
            OutputFormat.Word => Loc.Plural(PageCount, "Save {1} Word documents ({0} page)",
                                            "Save {1} Word documents ({0} pages)", Documents.Count),
            OutputFormat.Text => Loc.Plural(PageCount, "Save {1} text files ({0} page)",
                                            "Save {1} text files ({0} pages)", Documents.Count),
            _ => Loc.Plural(PageCount, "Save {1} PDFs ({0} page)", "Save {1} PDFs ({0} pages)", Documents.Count),
        };
    }

    /// <summary>
    /// What was left out, after the saved message: " — 1 skipped page was left out", " — 2 separator
    /// pages were left out", " — 2 separator pages and 1 skipped page were left out"; empty when nothing was.
    /// </summary>
    public string LeftOutNote()
    {
        int s = SeparatorPages, k = SkippedPages;
        if (s == 0 && k == 0) return "";
        if (s == 0) return " " + Loc.Plural(k, "— {0} skipped page was left out", "— {0} skipped pages were left out");
        if (k == 0) return " " + Loc.Plural(s, "— {0} separator page was left out", "— {0} separator pages were left out");
        string separators = Loc.Plural(s, "{0} separator page", "{0} separator pages");
        string skipped = Loc.Plural(k, "{0} skipped page", "{0} skipped pages");
        return " " + Loc.T("— {0} and {1} were left out", separators, skipped);
    }

    /// <summary>
    /// "Saved 3 PDFs (7 pages, 1.2 MB): A.pdf, B.pdf, C.pdf and their text, A.txt, B.txt, C.txt — 2
    /// separator pages were left out" after a split save: <paramref name="size"/> is the files' size
    /// together (null when unknown), <paramref name="textFileNames"/> the text files written beside
    /// the PDFs, and <paramref name="noTextFound"/> the Word or text files with no text in them
    /// (" — no text was found" when that is all of them, " — no text was found in B.txt" otherwise).
    /// </summary>
    public string SavedMessage(OutputFormat format, IReadOnlyList<string> fileNames, string? size = null,
                               IReadOnlyList<string>? textFileNames = null, IReadOnlyList<string>? noTextFound = null)
    {
        string pages = Loc.Plural(PageCount, "{0} page", "{0} pages") + (size is null ? "" : $", {size}");
        string text = textFileNames is { Count: > 0 } names
            ? " " + Loc.T("and their text, {0}", string.Join(", ", names))
            : "";
        string empty = noTextFound is not { Count: > 0 } none
            ? ""
            : none.Count == fileNames.Count
            ? " " + Loc.T("— no text was found")
            : " " + Loc.T("— no text was found in {0}", string.Join(", ", none));
        int count = fileNames.Count;
        string saved = OutputFormats.QueueFormat(format) switch
        {
            OutputFormat.Word => Loc.Plural(count, "Saved {0} Word document ({1}):", "Saved {0} Word documents ({1}):", pages),
            OutputFormat.Text => Loc.Plural(count, "Saved {0} text file ({1}):", "Saved {0} text files ({1}):", pages),
            _ => Loc.Plural(count, "Saved {0} PDF ({1}):", "Saved {0} PDFs ({1}):", pages),
        };
        return saved + " " + string.Join(", ", fileNames) + text + empty + LeftOutNote();
    }

    /// <summary>The short status line's kind for <see cref="SavedMessage"/>: "Saved 3 PDFs", or just "Saved" for Word and text.</summary>
    public StatusHead SavedHead(OutputFormat format, int count) => OutputFormats.QueueFormat(format) switch
    {
        OutputFormat.Word or OutputFormat.Text => new StatusHead.Saved(),
        _ => new StatusHead.SavedFiles(count, FileKind.Pdf),
    };

    /// <summary>The error when a split save fails: nothing of it is kept, and the queue is still there.</summary>
    public static string NotSavedMessage(string reason) =>
        Loc.T("None of the documents was saved; the pages are still in the queue. {0}", reason);

    /// <summary>
    /// Runs <paramref name="write"/>, which records every file it writes in <paramref name="files"/>;
    /// when it fails or is cancelled, every file recorded is removed again and the exception goes on.
    /// Once <paramref name="write"/> has finished the save counts as done.
    /// </summary>
    public static async Task WriteAllOrNothingAsync(WrittenFiles files, Func<Task> write)
    {
        try
        {
            await write();
        }
        catch
        {
            files.RollBack();
            throw;
        }
    }
}

/// <summary>The files one save has written so far, so that a save that does not finish can remove them (<see cref="SavePlan.WriteAllOrNothingAsync"/>).</summary>
public sealed class WrittenFiles
{
    private readonly List<string> _paths = [];

    /// <summary>The files written, in order.</summary>
    public IReadOnlyList<string> Paths => _paths;

    public void Add(string path) => _paths.Add(path);

    /// <summary>Deletes every file written (best effort) and forgets them.</summary>
    public void RollBack()
    {
        foreach (string path in _paths)
        {
            try { File.Delete(path); } catch (Exception e) when (e is IOException or UnauthorizedAccessException) { }
        }
        _paths.Clear();
    }
}
