using System.Globalization;
using System.Windows;
using System.Windows.Automation;
using System.Windows.Automation.Peers;
using System.Windows.Controls;
using LazyScan.Core;

namespace LazyScan.App;

// The date taken and caption of a photo review (PhotoDetailsEntry): one of each for the whole batch,
// empty on every review, written into the saved files by AppViewModel.SaveReviewedPhotos.
public partial class MainWindow
{
    private bool _photoReviewWasShown;
    private bool _syncingDetails;
    private bool _photoYearProblem;

    private void SetUpPhotoDetails()
    {
        var names = CultureInfo.CurrentUICulture.DateTimeFormat.MonthNames;
        PhotoMonthBox.ItemsSource = new[] { Loc.T("Month") }.Concat(names.Take(12)).ToList();
        PhotoDayBox.ItemsSource = DayItems(31);
        PhotoMonthBox.SelectedIndex = 0;
        PhotoDayBox.SelectedIndex = 0;
        Placeholders.Attach(PhotoYearBox, PhotoYearPlaceholder);
        Placeholders.Attach(PhotoCaptionBox, PhotoCaptionPlaceholder);
    }

    private static List<string> DayItems(int days) =>
        new[] { Loc.T("Day") }.Concat(Enumerable.Range(1, days).Select(d => d.ToString(CultureInfo.CurrentCulture))).ToList();

    /// <summary>Shows the row on a photo review only, and starts it empty each time a review opens.</summary>
    private void SyncPhotoDetailsRow()
    {
        bool shown = ViewModel.ShowPhotoReview && !ViewModel.IsReceiptReview;
        ReviewDetailsRow.Visibility = shown ? Visibility.Visible : Visibility.Collapsed;
        ReviewDetailsRow.IsEnabled = !ViewModel.IsBusy;
        if (shown && !_photoReviewWasShown)
        {
            PhotoYearBox.Text = "";
            PhotoMonthBox.SelectedIndex = 0;
            PhotoDayBox.SelectedIndex = 0;
            PhotoCaptionBox.Text = "";
            SyncPhotoDetails();
        }
        _photoReviewWasShown = shown;
    }

    private void PhotoDetails_Changed(object sender, RoutedEventArgs e) => SyncPhotoDetails();

    private void SyncPhotoDetails()
    {
        if (_syncingDetails || !IsLoaded) return;
        _syncingDetails = true;
        try
        {
            string digits = new(PhotoYearBox.Text.Where(char.IsAsciiDigit).ToArray());
            if (digits != PhotoYearBox.Text)
            {
                PhotoYearBox.Text = digits;
                PhotoYearBox.CaretIndex = digits.Length;
            }
            int year = DateTime.Now.Year;
            int month = Math.Max(PhotoMonthBox.SelectedIndex, 0);
            int days = PhotoDetailsEntry.DaysInMonth(PhotoDetailsEntry.Year(digits, year), month);
            // A shorter month drops a day it does not have.
            int day = Math.Max(PhotoDayBox.SelectedIndex, 0);
            if (month == 0 || day > days) day = 0;
            if (PhotoDayBox.Items.Count != days + 1) PhotoDayBox.ItemsSource = DayItems(days);
            PhotoDayBox.SelectedIndex = day;
            PhotoDayBox.IsEnabled = month != 0;
            AutomationProperties.SetHelpText(PhotoDayBox, month == 0 ? Loc.T("Optional. Choose a month first.") : Loc.T("Optional"));

            bool problem = PhotoDetailsEntry.YearProblem(digits, month, day, year);
            PhotoYearError.Visibility = problem ? Visibility.Visible : Visibility.Collapsed;
            if (problem && !_photoYearProblem && PhotoYearErrorText.IsVisible)
            {
                var peer = UIElementAutomationPeer.FromElement(PhotoYearErrorText) ?? UIElementAutomationPeer.CreatePeerForElement(PhotoYearErrorText);
                peer?.RaiseAutomationEvent(AutomationEvents.LiveRegionChanged);
            }
            _photoYearProblem = problem;
            PhotoYearBox.ClearValue(Control.BorderBrushProperty);
            if (problem) PhotoYearBox.SetResourceReference(Control.BorderBrushProperty, "SystemFillColorCriticalBrush");
            ViewModel.ReviewDetails = PhotoDetailsEntry.Details(digits, month, day, PhotoCaptionBox.Text.Trim(), year);
        }
        finally
        {
            _syncingDetails = false;
        }
    }
}
