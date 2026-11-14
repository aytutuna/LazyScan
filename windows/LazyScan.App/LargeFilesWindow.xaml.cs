using System.Windows;
using System.Windows.Automation;
using LazyScan.Core;

namespace LazyScan.App;

/// <summary>
/// Tells the user that the files about to go to the share window are too big for most mail services. Save smaller is
/// the default choice; without it (the pages are no longer held) Cancel is, and Send anyway never is.
/// </summary>
public partial class LargeFilesWindow : Window
{
    private LargeSendChoice _choice = LargeSendChoice.Cancel;

    private LargeFilesWindow(int count, long bytes, bool canSaveSmaller)
    {
        FlowDirection = App.Flow;
        InitializeComponent();
        Title = Loc.Plural(count, "Large file", "Large files");
        MessageText.Text = Loc.Plural(count,
            "This file is {1}. Many mail services reject attachments over {2}.",
            "These files are {1}. Many mail services reject attachments over {2}.",
            AppViewModel.AttachmentSizeText(bytes), AppViewModel.AttachmentSizeText(SaveActions.LargeAttachmentBytes));
        AutomationProperties.SetHelpText(this, MessageText.Text);
        var defaultChoice = canSaveSmaller ? SaveSmallerButton : CancelButton;
        if (!canSaveSmaller) SaveSmallerButton.Visibility = Visibility.Collapsed;
        defaultChoice.IsDefault = true;
        defaultChoice.SetResourceReference(StyleProperty, "AccentButtonStyle");
        Loaded += (_, _) => defaultChoice.Focus();
    }

    public static LargeSendChoice Ask(Window owner, int count, long bytes, bool canSaveSmaller)
    {
        var dialog = new LargeFilesWindow(count, bytes, canSaveSmaller) { Owner = owner };
        dialog.ShowDialog();
        return dialog._choice;
    }

    private void SaveSmaller_Click(object sender, RoutedEventArgs e) => Choose(LargeSendChoice.SaveSmaller);

    private void SendAnyway_Click(object sender, RoutedEventArgs e) => Choose(LargeSendChoice.SendAnyway);

    private void Choose(LargeSendChoice choice)
    {
        _choice = choice;
        Close();
    }
}
