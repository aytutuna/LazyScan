using System.Windows;
using System.Windows.Automation;
using System.Windows.Controls;
using System.Windows.Controls.Primitives;
using System.Windows.Input;
using LazyScan.Core;

namespace LazyScan.App;

// Splitting a stack into documents (AppViewModel.Split.cs): the inspector's choice, the page
// strip's gaps and dividers, naming a document, and saving or printing the separator sheet (Patch T,
// or a QR code at barcode or QR sheets).
public partial class MainWindow
{
    /// <summary>The split choices (as the inspector lists them) and the sheets per document, 1 to 99.</summary>
    private void BuildSplitChoices()
    {
        foreach (var mode in SplitModes.DisplayOrder)
        {
            SplitModeBox.Items.Add(new ComboBoxItem { Content = mode.Label(), Tag = mode, ToolTip = mode.Hint() });
        }
        SplitCountBox.ItemsSource = Enumerable.Range(1, 99).ToList();
        Placeholders.Attach(QrSheetNameBox, QrSheetNamePlaceholder);
    }

    /// <summary>
    /// Splitting works on pages collected in the queue only, where the strip shows the documents
    /// before saving: with each scan saved at once the choice is greyed out with the reason (the
    /// section is hidden for copies, receipts and the ID card). Under the choice, one line says what
    /// happens to the sheets that split; the ⓘ holds how it works.
    /// </summary>
    private void SyncSplitOptions()
    {
        var s = ViewModel.Settings;
        var flow = TaskCatalog.FlowOf(s);
        bool copy = flow == TaskFlowKind.Copy;
        bool receipts = flow == TaskFlowKind.ReceiptSplit;
        bool collecting = PageProcessor.ChecksBlankPages(s);
        var mode = s.Document.SplitMode;
        int count = DocumentSplitter.ClampSheetCount(s.Document.SplitSheetCount);
        bool wasUpdating = _updatingUi;
        _updatingUi = true;
        try
        {
            SplitModeBox.SelectedItem = SplitModeBox.Items.Cast<ComboBoxItem>().FirstOrDefault(i => (SplitMode)i.Tag == mode);
            if (SplitCountBox.ItemsSource is List<int> counts && !counts.Contains(count))
            {
                SplitCountBox.ItemsSource = counts.Append(count).Order().ToList();
            }
            SplitCountBox.SelectedItem = count;
            CodesOnFirstPagesButton.IsChecked = s.Document.BarcodeStartsDocument;
            CodesOnSeparatorsButton.IsChecked = !s.Document.BarcodeStartsDocument;
            if (QrSheetNameBox.Text != ViewModel.QrSheetName) QrSheetNameBox.Text = ViewModel.QrSheetName;
        }
        finally
        {
            _updatingUi = wasUpdating;
        }
        SplitModeBox.IsEnabled = collecting && !ViewModel.IsBusy;
        SplitReason.Visibility = !collecting && !copy && !receipts ? Visibility.Visible : Visibility.Collapsed;
        SplitCountRow.Visibility = collecting && mode == SplitMode.SheetCount ? Visibility.Visible : Visibility.Collapsed;

        // The full explanation: how it works, step by step (the ⓘ), and the choice's help text.
        string help = copy
            ? Loc.T("Copies print every page as scanned: nothing is split.")
            : receipts
            ? Loc.T("Each receipt is saved on its own.")
            : !collecting
            ? Loc.T("Only for pages collected before saving: a scan saved at once is one file.")
            : mode.Steps();
        SplitInfoButton.InfoText = help;
        SplitModeBox.ToolTip = collecting ? mode.Hint() : help;
        AutomationProperties.SetHelpText(SplitModeBox, help);
        // One line: what happens to the sheets that split.
        string line = collecting ? mode.Caption() : "";
        SplitHint.Text = line;
        SplitHint.Visibility = line.Length > 0 ? Visibility.Visible : Visibility.Collapsed;

        // At barcode or QR sheets: the page with a code kept as its document's first page, or the
        // sheet left out; then the name the QR separator sheet carries.
        bool barcodes = collecting && mode == SplitMode.Barcode;
        BarcodeOptions.Visibility = barcodes ? Visibility.Visible : Visibility.Collapsed;
        CodesOnSeparatorsButton.IsEnabled = CodesOnFirstPagesButton.IsEnabled = !ViewModel.IsBusy;
        string startsHint = BarcodeSeparators.StartsDocumentHint(s.Document.BarcodeStartsDocument, s.Document.SplitBarcodePrefix);
        BarcodeStartsDocumentHint.Text = BarcodeSeparators.StartsDocumentCaption(s.Document.BarcodeStartsDocument);
        BarcodeStartsDocumentHint.ToolTip = startsHint;
        AutomationProperties.SetHelpText(CodesOnSeparatorsButton, startsHint);
        AutomationProperties.SetHelpText(CodesOnFirstPagesButton, startsHint);
        bool qrSheets = barcodes && !s.Document.BarcodeStartsDocument;
        QrSheetNameRow.Visibility = qrSheets ? Visibility.Visible : Visibility.Collapsed;
        AutomationProperties.SetHelpText(QrSheetNameBox,
            Loc.T("The QR code holds this name and the document after the sheet is named by it ({label}). Leave it empty for a sheet that only splits."));

        // The separator sheet: a PDF in the scans folder, to print on any printer; or printed at
        // once on the printer chosen for copies.
        bool separators = (collecting && mode == SplitMode.SeparatorSheet) || qrSheets;
        var sheetPaper = SeparatorSheet.Paper(AppViewModel.RegionCode);
        SaveSeparatorButton.Visibility = separators ? Visibility.Visible : Visibility.Collapsed;
        SaveSeparatorButton.IsEnabled = !ViewModel.IsBusy;
        SaveSeparatorButton.ToolTip = Loc.T("Saves a PDF of the sheet; print it at 100%");
        AutomationProperties.SetName(SaveSeparatorButton, qrSheets ? Loc.T("Save QR separator sheet as PDF") : Loc.T("Save separator sheet as PDF"));
        AutomationProperties.SetHelpText(SaveSeparatorButton, qrSheets
            ? Loc.T("Saves a QR separator sheet ({0}) carrying the name above as a PDF in the scans folder, to print on any printer.", sheetPaper.Label())
            : Loc.T("Saves a Patch T separator sheet ({0}) as a PDF in the scans folder. Print it at actual size (100%) on any printer.", sheetPaper.Label()));
        PrintSeparatorButton.Visibility = separators ? Visibility.Visible : Visibility.Collapsed;
        PrintSeparatorButton.IsEnabled = ViewModel.HasPrinter && !ViewModel.IsBusy;
        string printer = ViewModel.CopyPrinterName ?? Loc.T("the default printer");
        PrintSeparatorButton.ToolTip = ViewModel.HasPrinter ? Loc.T("Prints one now on {0}, at actual size", printer) : PrintText.NoPrinterReason;
        AutomationProperties.SetName(PrintSeparatorButton, qrSheets ? Loc.T("Print QR separator sheet") : Loc.T("Print separator sheet"));
        AutomationProperties.SetHelpText(PrintSeparatorButton, ViewModel.HasPrinter
            ? qrSheets
                ? Loc.T("Prints a QR separator sheet carrying the name above at actual size on {0}, on the paper it has, with no print dialog. Print as many as you need.", printer)
                : Loc.T("Prints a Patch T separator sheet at actual size on {0}, on the paper it has, with no print dialog. Print as many as you need.", printer)
            : Loc.T("{0}. Save the separator sheet as a PDF to print it elsewhere.", PrintText.NoPrinterReason));
        // At blank sheets one-sided, Skip blank pages has no say.
        SyncBlankPageOptions();
    }

    private void SplitMode_Changed(object sender, SelectionChangedEventArgs e)
    {
        if (_updatingUi || !IsLoaded || SplitModeBox.SelectedItem is not ComboBoxItem { Tag: SplitMode mode }) return;
        ViewModel.SetSplitMode(mode);
        SyncSplitOptions();
        RefreshFromViewModel();
    }

    /// <summary>The name the next QR separator sheet carries, as typed.</summary>
    private void QrSheetName_Changed(object sender, TextChangedEventArgs e)
    {
        if (_updatingUi || !IsLoaded) return;
        ViewModel.QrSheetName = QrSheetNameBox.Text;
    }

    private void SplitCount_Changed(object sender, SelectionChangedEventArgs e)
    {
        if (_updatingUi || !IsLoaded || SplitCountBox.SelectedItem is not int count) return;
        ViewModel.SetSplitSheetCount(count);
        RefreshFromViewModel();
    }

    private void SaveSeparator_Click(object sender, RoutedEventArgs e) => _ = SaveSeparatorAsync();

    private async Task SaveSeparatorAsync()
    {
        await ViewModel.SaveSeparatorSheet();
        RefreshFromViewModel();
    }

    private void PrintSeparator_Click(object sender, RoutedEventArgs e) => _ = PrintSeparatorAsync();

    private async Task PrintSeparatorAsync()
    {
        await ViewModel.PrintSeparatorSheet();
        RefreshFromViewModel();
    }

    /// <summary>The gap before a page, or its menu item: start a new document there, or join the page to the one before.</summary>
    private void PageBreak_Click(object sender, RoutedEventArgs e)
    {
        if (PageIdOf(sender) is not { } id) return;
        ViewModel.ToggleDocumentBreak(id);
        RefreshFromViewModel();
        Dispatcher.InvokeAsync(NamePageItems, System.Windows.Threading.DispatcherPriority.Loaded);
    }

    /// <summary>"Name this document…" in a page's menu: the name box opens over the page.</summary>
    private void PageName_Click(object sender, RoutedEventArgs e)
    {
        if (PageIdOf(sender) is not { } id || ViewModel.IsBusy) return;
        var item = ViewModel.ScannedPages.FirstOrDefault(p => p.Page.Id == id);
        if (item is null) return;
        _nameCancelled = false;
        item.NameDraft = ViewModel.DocumentLabelOf(id);
        item.IsNaming = true;
    }

    /// <summary>Esc in the name box: the name is left as it was.</summary>
    private bool _nameCancelled;

    private void NamePopup_Opened(object? sender, EventArgs e)
    {
        if (sender is Popup { Child: Border { Child: StackPanel panel } } && panel.Children.OfType<TextBox>().FirstOrDefault() is { } box)
        {
            // Focus once the popup's window is up, with the name selected to type over.
            Dispatcher.InvokeAsync(() =>
            {
                box.Focus();
                Keyboard.Focus(box);
                box.SelectAll();
            }, System.Windows.Threading.DispatcherPriority.Input);
        }
    }

    /// <summary>The name box closed (Enter, a click elsewhere): the name typed is kept, unless Esc cancelled it.</summary>
    private void NamePopup_Closed(object? sender, EventArgs e)
    {
        if (sender is not Popup { Tag: Guid id }) return;
        var item = ViewModel.ScannedPages.FirstOrDefault(p => p.Page.Id == id);
        bool cancelled = _nameCancelled;
        _nameCancelled = false;
        if (item is null) return;
        item.IsNaming = false;
        if (!cancelled) ViewModel.SetDocumentLabel(id, item.NameDraft);
        RefreshFromViewModel();
        Dispatcher.InvokeAsync(NamePageItems, System.Windows.Threading.DispatcherPriority.Loaded);
        int index = IndexOfPage(id);
        if (index >= 0 && PageList.ItemContainerGenerator.ContainerFromIndex(index) is ListBoxItem container) container.Focus();
    }

    private void NameBox_KeyDown(object sender, KeyEventArgs e)
    {
        if (PageIdOf(sender) is not { } id) return;
        var item = ViewModel.ScannedPages.FirstOrDefault(p => p.Page.Id == id);
        if (item is null) return;
        if (e.Key == Key.Escape)
        {
            _nameCancelled = true;
            item.IsNaming = false;
            e.Handled = true;
        }
        else if (e.Key == Key.Enter)
        {
            item.IsNaming = false;
            e.Handled = true;
        }
    }
}
