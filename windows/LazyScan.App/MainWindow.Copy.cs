using System.Globalization;
using System.Windows;
using System.Windows.Automation;
using System.Windows.Controls;
using System.Windows.Input;
using LazyScan.Core;

namespace LazyScan.App;

// The Copy task's section of the inspector and printing the ID card (AppViewModel.Copy.cs).
public partial class MainWindow
{
    /// <summary>The printer names the printer box was last filled with.</summary>
    private string _copyPrintersShown = "\u0000";

    /// <summary>Fills the copies box (1 to 99) once.</summary>
    private void BuildCopyCountItems()
    {
        for (int count = 1; count <= PrintCopies.MaxCount; count++) CopyCountBox.Items.Add(count);
    }

    /// <summary>Fills the scale box: the three sizes, a separator, the preset percentages, Custom.</summary>
    private void BuildCopyScaleItems()
    {
        foreach (var scale in new[] { CopyScale.Actual, CopyScale.Fit, CopyScale.Fill })
        {
            CopyScaleBox.Items.Add(new ComboBoxItem { Content = PrintScale.Label(scale, 100), Tag = (scale, 0) });
        }
        CopyScaleBox.Items.Add(new Separator());
        foreach (int percent in PrintScale.PresetPercents)
        {
            CopyScaleBox.Items.Add(new ComboBoxItem { Content = PrintScale.Label(CopyScale.Percent, percent), Tag = (CopyScale.Percent, percent) });
        }
        CopyScaleBox.Items.Add(new ComboBoxItem { Content = Loc.T("Custom percent…"), Tag = (CopyScale.Percent, 0) });
    }

    /// <summary>The Copy task's section: shown for the task only, with the printers, the paper and the choices.</summary>
    private void SyncCopyOptions()
    {
        bool copy = ViewModel.IsCopyFlow;
        CopyOptions.Visibility = copy ? Visibility.Visible : Visibility.Collapsed;
        if (!copy) return;
        var options = ViewModel.Settings.TaskOptions;
        var printers = ViewModel.Printers;
        bool wasUpdating = _updatingUi;
        _updatingUi = true;
        try
        {
            string shown = string.Join('\u001f', printers.Select(p => $"{p.Name}\u001e{p.IsDefault}"));
            if (shown != _copyPrintersShown)
            {
                _copyPrintersShown = shown;
                CopyPrinterBox.Items.Clear();
                foreach (var printer in printers)
                {
                    CopyPrinterBox.Items.Add(new ComboBoxItem
                    {
                        Content = printer.IsDefault ? Loc.T("{0} (default)", printer.Name) : printer.Name,
                        Tag = printer.Name,
                    });
                }
            }
            string? current = ViewModel.CopyPrinterName;
            CopyPrinterBox.SelectedItem = CopyPrinterBox.Items.Cast<ComboBoxItem>()
                .FirstOrDefault(i => string.Equals((string)i.Tag, current, StringComparison.OrdinalIgnoreCase));
            CopyCountBox.SelectedItem = PrintCopies.Clamp(options.CopyCount);
            var scale = ViewModel.CopyScaleShown;
            int percent = PrintScale.Clamp(options.CopyScalePercent);
            bool custom = scale == CopyScale.Percent && (_copyCustomPicked || !PrintScale.PresetPercents.Contains(percent));
            CopyScaleBox.SelectedItem = CopyScaleBox.Items.OfType<ComboBoxItem>().FirstOrDefault(i =>
                i.Tag is ValueTuple<CopyScale, int> item && item.Item1 == scale
                && (scale != CopyScale.Percent || item.Item2 == (custom ? 0 : percent)));
            CopyScaleBox.IsEnabled = !ViewModel.CopyNeedsFit && !ViewModel.IsBusy;
            CopyPercentRow.Visibility = custom ? Visibility.Visible : Visibility.Collapsed;
            CopyPercentBox.IsEnabled = !ViewModel.IsBusy;
            if (!CopyPercentBox.IsKeyboardFocused) CopyPercentBox.Text = percent.ToString(CultureInfo.CurrentCulture);
            bool centerChoice = PrintScale.HasCenterChoice(scale) && !ViewModel.CopyAreaSelected;
            CopyCenterBox.Visibility = centerChoice ? Visibility.Visible : Visibility.Collapsed;
            CopyCenterBox.IsEnabled = !ViewModel.IsBusy;
            CopyCenterBox.IsChecked = options.CopyCenter;
            CopyFitReasonText.Text = PrintText.RealSizeUnavailable;
            CopyFitReason.Visibility = ViewModel.CopyNeedsFit ? Visibility.Visible : Visibility.Collapsed;
            CopyPdfBox.IsChecked = options.CopyAlsoSavePdf;
        }
        finally
        {
            _updatingUi = wasUpdating;
        }
        bool none = !ViewModel.HasPrinter;
        CopyNoPrinterNotice.Visibility = none ? Visibility.Visible : Visibility.Collapsed;
        CopyLookAgainButton.Visibility = none ? Visibility.Visible : Visibility.Collapsed;
        CopyPrinterBox.IsEnabled = !none;
        RulerButton.IsEnabled = !none && !ViewModel.IsBusy;
        // "Paper: Letter"; its size is the tooltip, and the whole of it the printer's help text.
        string paper = ViewModel.CopyPaperText;
        int sizeAt = paper.IndexOf(" (", StringComparison.Ordinal);
        string paperName = sizeAt > 0 ? paper[..sizeAt] : paper;
        CopyPaperText.Text = paper.Length > 0 ? Loc.T("Paper: {0}", paperName) : "";
        CopyPaperText.ToolTip = sizeAt > 0 ? paper[(sizeAt + 2)..].TrimEnd(')') : null;
        CopyPaperText.Visibility = CopyPaperText.Text.Length > 0 ? Visibility.Visible : Visibility.Collapsed;
        AutomationProperties.SetName(CopyPaperText, paper.Length > 0
            ? Loc.T("Printer paper: {0}", ViewModel.CopyPaperSpokenText)
            : "");
        // Edges a printer can't reach are lost at real size: always shown while that is the case.
        CopyMarginText.Text = ViewModel.CopyMarginWarning ?? "";
        CopyMarginNotice.Visibility = ViewModel.CopyMarginWarning is null ? Visibility.Collapsed : Visibility.Visible;
        AutomationProperties.SetHelpText(CopyPrinterBox, paper.Length > 0 ? Loc.T("Paper: {0}", paper) : "");
    }

    private void CopyPrinterBox_DropDownOpened(object? sender, EventArgs e) => _ = ViewModel.RefreshPrintersAsync();

    private void CopyLookAgain_Click(object sender, RoutedEventArgs e) => _ = ViewModel.RefreshPrintersAsync();

    private void CopyPrinter_Changed(object sender, SelectionChangedEventArgs e)
    {
        if (_updatingUi || !IsLoaded || CopyPrinterBox.SelectedItem is not ComboBoxItem { Tag: string name }) return;
        ViewModel.SetCopyPrinter(name);
    }

    private void CopyCount_Changed(object sender, SelectionChangedEventArgs e)
    {
        if (_updatingUi || !IsLoaded || CopyCountBox.SelectedItem is not int count) return;
        ViewModel.SetCopyCount(count);
    }

    /// <summary>Custom percent was picked, so its box stays while the stored share happens to match a preset.</summary>
    private bool _copyCustomPicked;

    private void CopyScale_Changed(object sender, SelectionChangedEventArgs e)
    {
        if (_updatingUi || !IsLoaded || CopyScaleBox.SelectedItem is not ComboBoxItem { Tag: ValueTuple<CopyScale, int> item }) return;
        var (scale, percent) = item;
        _copyCustomPicked = scale == CopyScale.Percent && percent == 0;
        if (scale == CopyScale.Percent && percent != 0) ViewModel.SetCopyScalePercent(percent);
        ViewModel.SetCopyScale(scale);
        SyncCopyOptions();
    }

    private void CopyCenter_Changed(object sender, RoutedEventArgs e)
    {
        if (_updatingUi || !IsLoaded) return;
        ViewModel.SetCopyCenter(CopyCenterBox.IsChecked == true);
    }

    private void CopyPercent_PreviewTextInput(object sender, TextCompositionEventArgs e) =>
        e.Handled = !e.Text.All(char.IsAsciiDigit);

    private void CopyPercent_PreviewKeyDown(object sender, KeyEventArgs e)
    {
        int stored = ViewModel.Settings.TaskOptions.CopyScalePercent;
        if (e.Key == Key.Enter)
        {
            CommitCopyPercent();
            CopyPercentBox.SelectAll();
        }
        else if (e.Key == Key.Escape)
        {
            CopyPercentBox.Text = stored.ToString(CultureInfo.CurrentCulture);
            CopyPercentBox.SelectAll();
        }
        else if (e.Key is Key.Up or Key.Down)
        {
            ViewModel.SetCopyScalePercent(stored + (e.Key == Key.Up ? PrintScale.PercentStep : -PrintScale.PercentStep));
            CopyPercentBox.Text = ViewModel.Settings.TaskOptions.CopyScalePercent.ToString(CultureInfo.CurrentCulture);
            CopyPercentBox.SelectAll();
        }
        else return;
        e.Handled = true;
    }

    private void CopyPercent_LostFocus(object sender, KeyboardFocusChangedEventArgs e) => CommitCopyPercent();

    /// <summary>A number is kept between 25 and 400; anything else puts the stored value back.</summary>
    private void CommitCopyPercent()
    {
        if (_updatingUi || !IsLoaded) return;
        string text = CopyPercentBox.Text;
        if (int.TryParse(text, NumberStyles.None, CultureInfo.CurrentCulture, out int percent))
        {
            ViewModel.SetCopyScalePercent(percent);
        }
        else if (text.Length > 0 && text.All(char.IsAsciiDigit))
        {
            ViewModel.SetCopyScalePercent(int.MaxValue);
        }
        CopyPercentBox.Text = PrintScale.Clamp(ViewModel.Settings.TaskOptions.CopyScalePercent).ToString(CultureInfo.CurrentCulture);
    }

    private void CopyPdf_Changed(object sender, RoutedEventArgs e)
    {
        if (_updatingUi || !IsLoaded) return;
        ViewModel.SetCopyAlsoSavePdf(CopyPdfBox.IsChecked == true);
        // The PDF size shows for a copy only while it is also saved as a PDF.
        SyncPdfSizeOptions();
    }

    private void PrintAgain_Click(object sender, RoutedEventArgs e) => _ = ViewModel.PrintHeldCopy();

    /// <summary>Shows the Printer box of the copy options, open; the copy prints when Print again is pressed.</summary>
    private void ChooseAnotherPrinter_Click(object sender, RoutedEventArgs e)
    {
        MainTabs.SelectedItem = ScanTab;
        _settingSections = true;
        try { CopyOptions.IsExpanded = true; }
        finally { _settingSections = false; }
        Dispatcher.BeginInvoke(() =>
        {
            CopyOptions.BringIntoView();
            CopyPrinterBox.Focus();
            CopyPrinterBox.IsDropDownOpen = true;
        }, System.Windows.Threading.DispatcherPriority.Loaded);
    }

    private void RulerPage_Click(object sender, RoutedEventArgs e) => _ = ViewModel.PrintRulerPage();

    private void IdCardPrint_Click(object sender, RoutedEventArgs e) => _ = ViewModel.PrintIdCard();

    private void IdCardLazyPrint_Click(object sender, RoutedEventArgs e) => _ = ViewModel.PrintIdCardWithLazyPrint();

    private void PrintQueue_Click(object sender, RoutedEventArgs e) => _ = ViewModel.PrintQueueWithLazyPrint();

    private void PrintQueueDirect_Click(object sender, RoutedEventArgs e) => _ = ViewModel.PrintQueue();

    /// <summary>The review's Print button: on the printer chosen for copies, else the default one.</summary>
    private void SyncIdCardPrint(bool busy)
    {
        string? printer = ViewModel.CopyPrinterName;
        bool canPrint = ViewModel.HasPrinter && ViewModel.IdCardFront is not null;
        IdCardPrintButton.IsEnabled = !busy && canPrint;
        string tip = !ViewModel.HasPrinter
            ? PrintText.NoPrinterMessage
            : Loc.T("Print at real size on {0}", printer ?? Loc.T("the default printer"));
        IdCardPrintButton.ToolTip = tip;
        AutomationProperties.SetHelpText(IdCardPrintButton, tip);
        IdCardLazyPrintButton.Visibility = ViewModel.LazyPrintInstalled ? Visibility.Visible : Visibility.Collapsed;
        IdCardLazyPrintButton.IsEnabled = !busy && ViewModel.IdCardFront is not null;
    }
}
