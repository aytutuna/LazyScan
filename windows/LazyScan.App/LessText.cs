using LazyScan.Core;

namespace LazyScan.App;

/// <summary>
/// The short visible texts only the Windows layout has: the empty stage's line and chip, and the
/// short reasons of controls the Mac lays out differently. The short texts both apps show (disabled
/// reasons, consequence lines, the status line, the inspector's summaries) are in Core
/// (<see cref="LazyScan.Core.StatusLine"/>, <see cref="LazyScan.Core.InspectorSections"/>
/// and the types they belong to).
/// </summary>
internal static class ShortText
{
    /// <summary>The empty stage's line without a task.</summary>
    public static string PlaceOriginal => Loc.T("Place the original face down, then select Scan.");
    /// <summary>The same line while the feeder is the source.</summary>
    public static string LoadFeeder => Loc.T("Load the pages in the feeder, then select Scan.");
    /// <summary>The empty stage's note while the Demo Scanner is selected; with a real scanner listed it says to select that one.</summary>
    public static string DemoNote(string? listedScanner) => listedScanner is null
        ? Loc.T("This is the demo scanner: it scans sample pages. Your own scanner appears in the sidebar once it is found.")
        : Loc.T("This is the demo scanner: it scans sample pages. Select {0} in the list to use it.", listedScanner);
    /// <summary>The chip on a preview until an area is selected.</summary>
    public static string DragToSelect => Loc.T("Drag to select an area");
    /// <summary>Saturation and Restore faded colors while the scan is grayscale or black and white.</summary>
    public static string NeedsColor => Loc.T("Needs Color");
    /// <summary>Page clean-up and splitting while each scan is saved at once.</summary>
    public static string NeedsCollectPages => Loc.T("Needs Collect pages");
    /// <summary>Skip blank pages while blank sheets split the stack into documents.</summary>
    public static string BlankSheetsSplit => Loc.T("Blank sheets split documents");
    /// <summary>Receipts in one PDF, while they are saved as images.</summary>
    public static string OnlyForPdfs => Loc.T("Only for PDFs");
    /// <summary>Name by receipt date while the file name has no {docdate}: the receipt's date is not used.</summary>
    public static string NeedsDocDate => Loc.T("Needs {docdate} in File name");
}
