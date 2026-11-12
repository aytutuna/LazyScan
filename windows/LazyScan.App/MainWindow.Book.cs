using System.Windows;
using System.Windows.Automation;
using System.Windows.Controls;
using LazyScan.Core;

namespace LazyScan.App;

// Books and magazines (AppViewModel.Book.cs): the inspector's book options, and splitting or joining
// a spread from a page's menu.
public partial class MainWindow
{
    /// <summary>The book's rotations, as the inspector lists them.</summary>
    private void BuildBookChoices()
    {
        foreach (int turns in BookPages.RotationChoices)
        {
            BookRotationBox.Items.Add(new ComboBoxItem { Content = BookPages.RotationLabel(turns), Tag = turns });
        }
        foreach (var cutAt in Enum.GetValues<BookCutAt>())
        {
            CutAtBox.Items.Add(new ComboBoxItem { Content = BookPages.CutAtLabel(cutAt), Tag = cutAt });
        }
    }

    /// <summary>
    /// Splitting facing pages works on pages collected in the queue only, where the strip shows the
    /// pages, scanned one side of each sheet: with two-sided scanning the switch is greyed out with
    /// "Not with two-sided" next to it (with each scan saved at once the section says so once). The
    /// reading order, the rotation and softening the spine's shadow show, indented, while spreads are split.
    /// </summary>
    private void SyncBookOptions()
    {
        var s = ViewModel.Settings;
        bool queue = PageProcessor.ChecksBlankPages(s);
        bool oneSide = BookPages.ScansOneSide(s);
        bool collecting = queue && oneSide;
        bool wasUpdating = _updatingUi;
        _updatingUi = true;
        try
        {
            SplitFacingPagesBox.IsChecked = s.Document.SplitFacingPages;
            BookRightToLeftBox.IsChecked = s.TaskOptions.BookRightToLeft;
            int turns = BookSplitter.NormalizedTurns(s.TaskOptions.BookRotationQuarterTurns);
            BookRotationBox.SelectedItem = BookRotationBox.Items.Cast<ComboBoxItem>().FirstOrDefault(i => (int)i.Tag == turns);
            CutAtBox.SelectedItem = CutAtBox.Items.Cast<ComboBoxItem>().FirstOrDefault(i => (BookCutAt)i.Tag == s.TaskOptions.BookCutAt);
            SoftenSpineShadowBox.IsChecked = s.Document.SoftenSpineShadow;
        }
        finally
        {
            _updatingUi = wasUpdating;
        }
        SplitFacingPagesBox.IsEnabled = collecting && !ViewModel.IsBusy;
        BookOptions.Visibility = collecting && s.Document.SplitFacingPages ? Visibility.Visible : Visibility.Collapsed;
        BookRightToLeftBox.IsEnabled = !ViewModel.IsBusy;
        BookRotationBox.IsEnabled = !ViewModel.IsBusy;
        CutAtBox.IsEnabled = !ViewModel.IsBusy;
        SyncBookReorderOffer();
        string hint = BookPages.Hint(s);
        bool twoSided = queue && !oneSide;
        SplitFacingPagesHint.Text = twoSided ? BookPages.NotWithTwoSidedReason : "";
        SplitFacingPagesReason.Visibility = twoSided ? Visibility.Visible : Visibility.Collapsed;
        SplitFacingPagesBox.ToolTip = hint;
        AutomationProperties.SetHelpText(SplitFacingPagesBox, twoSided ? Loc.T("{0}. {1}", BookPages.NotWithTwoSidedReason, hint) : hint);
        string shadowHint = SpineShadow.Hint(s.Document.SoftenSpineShadow);
        SoftenSpineShadowBox.ToolTip = shadowHint;
        AutomationProperties.SetHelpText(SoftenSpineShadowBox, shadowHint);
    }

    /// <summary>The hint and button under the rotation: shown while the spreads in the queue differ from the options.</summary>
    private void SyncBookReorderOffer()
    {
        var offer = ViewModel.BookReorderOffer;
        bool wasShown = BookReorderButton.Visibility == Visibility.Visible;
        BookReorderReason.Visibility = offer is null ? Visibility.Collapsed : Visibility.Visible;
        BookReorderButton.Visibility = offer is null ? Visibility.Collapsed : Visibility.Visible;
        if (offer is not { } shown) return;
        BookReorderHint.Text = BookPages.ReorderHint(shown.Changed);
        string title = BookPages.ReorderButtonText(shown.Count);
        BookReorderButton.Content = title;
        BookReorderButton.IsEnabled = !ViewModel.IsBusy;
        AutomationProperties.SetName(BookReorderButton, title);
        AutomationProperties.SetHelpText(BookReorderButton, BookPages.ReorderOfferLabel(shown.Count, shown.Changed));
        if (!wasShown) AnnounceWhenShown(BookReorderHint);
    }

    private async void BookReorder_Click(object sender, RoutedEventArgs e)
    {
        await ViewModel.ApplyBookReorder();
        RefreshFromViewModel();
    }

    private void SoftenSpineShadow_Changed(object sender, RoutedEventArgs e)
    {
        if (_updatingUi || !IsLoaded) return;
        ViewModel.SetSoftenSpineShadow(SoftenSpineShadowBox.IsChecked == true);
        SyncBookOptions();
        RefreshFromViewModel();
    }

    private void SplitFacingPages_Changed(object sender, RoutedEventArgs e)
    {
        if (_updatingUi || !IsLoaded) return;
        ViewModel.SetSplitFacingPages(SplitFacingPagesBox.IsChecked == true);
        SyncBookOptions();
        RefreshFromViewModel();
    }

    private void BookRightToLeft_Changed(object sender, RoutedEventArgs e)
    {
        if (_updatingUi || !IsLoaded) return;
        ViewModel.SetBookRightToLeft(BookRightToLeftBox.IsChecked == true);
        RefreshFromViewModel();
    }

    private void BookRotation_Changed(object sender, SelectionChangedEventArgs e)
    {
        if (_updatingUi || !IsLoaded || BookRotationBox.SelectedItem is not ComboBoxItem { Tag: int turns }) return;
        ViewModel.SetBookRotation(turns);
        RefreshFromViewModel();
    }

    private void CutAt_Changed(object sender, SelectionChangedEventArgs e)
    {
        if (_updatingUi || !IsLoaded || CutAtBox.SelectedItem is not ComboBoxItem { Tag: BookCutAt cutAt }) return;
        ViewModel.SetBookCutAt(cutAt);
        RefreshFromViewModel();
    }

    /// <summary>"Split this spread…" or "Change the split…" in a page's menu: the split dialog, then the spread split or joined.</summary>
    private async void PageSplitSpread_Click(object sender, RoutedEventArgs e)
    {
        if (PageIdOf(sender) is not { } id || ViewModel.IsBusy) return;
        var source = await ViewModel.LoadSpreadEditor(id);
        if (source is null)
        {
            RefreshFromViewModel();
            return;
        }
        var dialog = new SpreadSplitWindow(source) { Owner = this };
        if (dialog.ShowDialog() != true) return;
        if (dialog.Choice == SpreadSplitChoice.KeepWhole)
        {
            await ViewModel.JoinSpread(id);
        }
        else if (dialog.Choice == SpreadSplitChoice.SplitAll)
        {
            await ViewModel.SplitAllSpreads(id, dialog.Axis, dialog.Fraction);
        }
        else
        {
            await ViewModel.SplitSpread(id, dialog.Axis, dialog.Fraction);
        }
        RefreshFromViewModel();
    }

    /// <summary>"Join the two pages" in a page's menu: the spread becomes one page again.</summary>
    private async void PageJoinSpread_Click(object sender, RoutedEventArgs e)
    {
        if (PageIdOf(sender) is not { } id) return;
        await ViewModel.JoinSpread(id);
        RefreshFromViewModel();
    }
}
