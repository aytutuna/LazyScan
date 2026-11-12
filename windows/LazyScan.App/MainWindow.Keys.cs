using LazyScan.Core;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Controls.Primitives;
using System.Windows.Input;

namespace LazyScan.App;

public partial class MainWindow
{
    private static string ScanKeys => Loc.T("Ctrl+Enter or F5");
    private static string PreviewKeys => Loc.T("Ctrl+Shift+Enter");
    private static string SaveKeys => Loc.T("Ctrl+S");
    private static string ImportKeys => Loc.T("Ctrl+O");

    /// <summary>A tooltip with its shortcut after it; the shortcut alone when there is no other text.</summary>
    private static string WithKeys(string? text, string keys) => text is null ? keys : $"{text} ({keys})";

    /// <summary>
    /// The shortcuts press the buttons, so each works exactly when its button does: shown and enabled.
    /// KeyDown only sees keys the focused control left alone, so text boxes and open lists keep theirs.
    /// </summary>
    private void Window_KeyDown(object sender, KeyEventArgs e)
    {
        var modifiers = Keyboard.Modifiers;
        if (e.Key == Key.Escape && modifiers == ModifierKeys.None && ViewModel.ViewsPage
            && (PageList.IsKeyboardFocusWithin || PageSwitch.IsKeyboardFocusWithin))
        {
            ViewModel.ShowPreview();
            RefreshFromViewModel();
            e.Handled = true;
            return;
        }
        if (e.Key == Key.Escape && modifiers == ModifierKeys.None && ViewModel.RescanTarget is not null
            && PageList.IsKeyboardFocusWithin)
        {
            ViewModel.CancelScanAgain();
            e.Handled = true;
            return;
        }
        if (e.Key == Key.Delete && modifiers == ModifierKeys.None)
        {
            if (RemoveFocusedPage()) e.Handled = true;
            return;
        }
        if (e.Key == Key.Enter) return;
        PressShortcut(e, e.Key, modifiers);
    }

    /// <summary>A focused button clicks itself on Enter before KeyDown, so the Enter shortcuts are taken here.</summary>
    private void Window_PreviewKeyDown(object sender, KeyEventArgs e)
    {
        var modifiers = Keyboard.Modifiers;
        if (e.Key == Key.Enter && (modifiers == ModifierKeys.Control || modifiers == (ModifierKeys.Control | ModifierKeys.Shift)))
            PressShortcut(e, e.Key, modifiers);
    }

    private void PressShortcut(KeyEventArgs e, Key key, ModifierKeys modifiers)
    {
        Button[] targets = (key, modifiers) switch
        {
            (Key.Enter, ModifierKeys.Control) => [ScanButton, ReviewScanMoreButton],
            (Key.F5, ModifierKeys.None) => [ScanButton],
            (Key.Enter, ModifierKeys.Control | ModifierKeys.Shift) => [PreviewButton],
            (Key.S, ModifierKeys.Control) => [SavePdfButton, ReviewSaveButton, IdCardSaveButton],
            (Key.O, ModifierKeys.Control) => [ImportPhotosButton],
            (Key.Z, ModifierKeys.Control) => [SavedUndoButton, UndoButton],
            (Key.Escape, ModifierKeys.None) => [CancelButton],
            _ => [],
        };
        foreach (var button in targets)
        {
            if (!button.IsVisible || !button.IsEnabled) continue;
            e.Handled = true;
            // Focus first, as a mouse click does, so a text box saves its value on LostFocus.
            button.Focus();
            button.RaiseEvent(new RoutedEventArgs(ButtonBase.ClickEvent));
            return;
        }
    }

    /// <summary>Delete takes the page the keyboard is on out of the queue, as its remove button does.</summary>
    private bool RemoveFocusedPage()
    {
        if (ViewModel.IsBusy || !PageList.IsKeyboardFocusWithin || !PageList.IsEnabled) return false;
        if (Keyboard.FocusedElement is not DependencyObject focused
            || ItemsControl.ContainerFromElement(PageList, focused) is not ListBoxItem { DataContext: var item }) return false;
        int index = PageList.Items.IndexOf(item);
        if (index < 0 || index >= ViewModel.ScannedPages.Count) return false;
        ViewModel.RemovePage(ViewModel.ScannedPages[index].Page.Id);
        int count = ViewModel.ScannedPages.Count;
        if (count > 0)
        {
            (PageList.ItemContainerGenerator.ContainerFromIndex(Math.Min(index, count - 1)) as ListBoxItem)?.Focus();
        }
        return true;
    }
}
