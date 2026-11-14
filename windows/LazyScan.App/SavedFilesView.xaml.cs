using System.ComponentModel;
using System.IO;
using System.Windows;
using System.Windows.Automation;
using System.Windows.Automation.Peers;
using System.Windows.Automation.Provider;
using System.Windows.Controls;
using System.Windows.Input;
using System.Windows.Media;
using System.Windows.Media.Imaging;
using LazyScan.App.Services;
using LazyScan.Core;

namespace LazyScan.App;

/// <summary>A card in the Saved tab.</summary>
public sealed class SavedFileItem(SavedFile file) : INotifyPropertyChanged
{
    public event PropertyChangedEventHandler? PropertyChanged;

    private SavedFile _file = file;
    /// <summary>Replaced after a rotate, so the card shows the file's new date and size.</summary>
    public SavedFile File
    {
        get => _file;
        set
        {
            _file = value;
            Changed(nameof(File)); Changed(nameof(Name)); Changed(nameof(Caption));
            Changed(nameof(DateText)); Changed(nameof(SizeText)); Changed(nameof(ToolTipText));
            Changed(nameof(AutomationName));
        }
    }
    public string Name => File.Name;
    public string Caption => Loc.T("{0} · {1}", DateText, SizeText);
    public string DateText => File.Modified.ToString("g");
    public string SizeText => SavedFiles.SizeText(File.Size);
    /// <summary>The card's tooltip: the whole name (it may be cut on the card) and the size.</summary>
    public string ToolTipText => Loc.T("{0} · {1}", Name, SizeText);
    /// <summary>Short file type label shown on the card (PDF, JPG, PNG, TIFF).</summary>
    public string TypeText => Path.GetExtension(File.Path).ToLowerInvariant() switch
    {
        ".jpg" or ".jpeg" => "JPG",
        ".tif" or ".tiff" => "TIFF",
        var other => other.TrimStart('.').ToUpperInvariant(),
    };
    /// <summary>What a screen reader says for the card itself: name, type and date.</summary>
    public string AutomationName => Loc.T("{0}, {1}, {2}", Name, TypeText, DateText);
    /// <summary>Icon font glyph shown until (or instead of) the thumbnail.</summary>
    public string PlaceholderGlyph => File.IsPdf || File.IsTextDocument ? "" : "";
    public Visibility RotateVisibility => File.ImageFormat is null ? Visibility.Collapsed : Visibility.Visible;

    private bool _selected;
    public bool IsSelected
    {
        get => _selected;
        set { _selected = value; Changed(nameof(IsSelected)); }
    }

    private BitmapSource? _thumbnail;
    public BitmapSource? Thumbnail
    {
        get => _thumbnail;
        set { _thumbnail = value; Changed(nameof(Thumbnail)); }
    }

    private bool _rotating;
    /// <summary>A rotate is in flight: the button is disabled so a double-click can't queue a second one.</summary>
    public bool IsRotating
    {
        get => _rotating;
        set { _rotating = value; Changed(nameof(IsRotating)); Changed(nameof(CanRotate)); }
    }
    public bool CanRotate => !_rotating;

    // Thumbnail bookkeeping for the virtualized list (UI thread only).

    /// <summary>The card elements currently showing this item; the thumbnail is kept only while there is one.</summary>
    internal HashSet<FrameworkElement> Cards { get; } = [];
    /// <summary>Bumped whenever the thumbnail is dropped or goes stale; loads of an older version are discarded.</summary>
    internal int ThumbnailVersion { get; set; }
    /// <summary>The version a load is in flight for, if any.</summary>
    internal int? LoadingVersion { get; set; }

    private void Changed(string name) => PropertyChanged?.Invoke(this, new PropertyChangedEventArgs(name));
}

/// <summary>One row of cards in the Saved tab (the list virtualizes by row).</summary>
public sealed class SavedFileRow(IReadOnlyList<SavedFileItem> items)
{
    public IReadOnlyList<SavedFileItem> Items { get; } = items;
}

/// <summary>A card; its automation peer reports whether the file is selected and can select it.</summary>
public sealed class SavedCard : Grid
{
    protected override AutomationPeer OnCreateAutomationPeer() => new SavedCardPeer(this);
}

internal sealed class SavedCardPeer(SavedCard card) : FrameworkElementAutomationPeer(card), ISelectionItemProvider
{
    private SavedFileItem? Item => card.DataContext as SavedFileItem;

    private SavedFilesView? View
    {
        get
        {
            DependencyObject? parent = card;
            while (parent is not null and not SavedFilesView) parent = VisualTreeHelper.GetParent(parent);
            return parent as SavedFilesView;
        }
    }

    protected override AutomationControlType GetAutomationControlTypeCore() => AutomationControlType.ListItem;

    public override object? GetPattern(PatternInterface patternInterface) =>
        patternInterface == PatternInterface.SelectionItem ? this : base.GetPattern(patternInterface);

    public bool IsSelected => Item?.IsSelected == true;

    public IRawElementProviderSimple? SelectionContainer => null;

    public void Select()
    {
        if (Item is { } item) View?.SelectOnly(item);
    }

    public void AddToSelection()
    {
        if (Item is { } item) View?.SetSelected(item, true);
    }

    public void RemoveFromSelection()
    {
        if (Item is { } item) View?.SetSelected(item, false);
    }

    public void RaiseSelectedChanged(bool selected) =>
        RaisePropertyChangedEvent(SelectionItemPatternIdentifiers.IsSelectedProperty, !selected, selected);
}

/// <summary>The rows' panel; lets the view scroll a row into view by index.</summary>
public sealed class RowsPanel : VirtualizingStackPanel
{
    public void ScrollRowIntoView(int index) => BringIndexIntoView(index);
}

/// <summary>
/// The Saved tab: everything in the destination folder, newest first, with open, open with,
/// show in folder, share, email, copy (<see cref="AppViewModel.RunFileAction"/>) and 90°
/// rotate-in-place for saved image files. Port of UI/SavedFilesView.swift; the file work lives
/// in <see cref="SavedFiles"/>.
/// </summary>
public partial class SavedFilesView : UserControl
{
    /// <summary>Decode width of a card thumbnail (cards show ~180 px; leaves room for HiDPI).</summary>
    private const int ThumbnailDecodeWidth = 360;

    /// <summary>Side insets of every row of cards (see <see cref="GridInsets"/>).</summary>
    public static readonly DependencyProperty RowInsetProperty = DependencyProperty.Register(
        nameof(RowInset), typeof(Thickness), typeof(SavedFilesView),
        new PropertyMetadata(new Thickness(GridInsets.EdgeMargin, 0, GridInsets.EdgeMargin, 0)));

    public Thickness RowInset
    {
        get => (Thickness)GetValue(RowInsetProperty);
        set => SetValue(RowInsetProperty, value);
    }

    private List<SavedFileItem> _items = [];
    private int _columns;
    private AppViewModel? _viewModel;
    private Action<string>? _showError;
    /// <summary>Bumped per reload; a listing that finishes after a newer one started is dropped.</summary>
    private int _generation;
    /// <summary>At most two thumbnails decode at once, so a fast scroll never floods the thread pool.</summary>
    private readonly SemaphoreSlim _thumbnailGate = new(2, 2);
    /// <summary>The item each realized card element is showing.</summary>
    private readonly Dictionary<FrameworkElement, SavedFileItem> _cardItems = [];
    private Task _pendingWork = Task.CompletedTask;
    private RowsPanel? _rowsPanel;
    /// <summary>The item to focus once its card is realized (its row was scrolled into view first).</summary>
    private SavedFileItem? _focusWhenLoaded;
    /// <summary>The card a Shift selection starts from: the last one clicked or toggled.</summary>
    private SavedFileItem? _anchor;
    /// <summary>The folder the selection belongs to; another folder starts with none.</summary>
    private string? _selectionFolder;
    /// <summary>A plain click landed on a thumbnail (which opens the file) and must not change the selection.</summary>
    private bool _thumbnailPressed;
    /// <summary>The selection bar is narrow: its buttons show only their glyphs.</summary>
    private bool _selectionCompact;

    public SavedFilesView()
    {
        InitializeComponent();
    }

    public void Attach(AppViewModel viewModel, Action<string> showError)
    {
        _viewModel = viewModel;
        _showError = showError;
    }

    /// <summary>Completes when no file write started here (rotate in place) is still running.</summary>
    public Task PendingWork => _pendingWork;

    /// <summary>
    /// Re-read the destination folder off the UI thread. Only the listing is read here;
    /// thumbnails load as their cards scroll into view.
    /// </summary>
    public async void Reload()
    {
        if (_viewModel is null) return;
        int generation = ++_generation;
        string folder = _viewModel.DestinationFolder;
        ShowFolder(folder);
        var files = await Task.Run(() =>
        {
            SavedFiles.SweepStaleTempFiles(folder, SavedFiles.StaleTempFileAge);
            return SavedFiles.List(folder);
        });
        if (generation != _generation) return;

        var focus = FocusedPosition();
        var selected = _selectionFolder == folder
            ? _items.Where(i => i.IsSelected).Select(i => i.File.Path).ToHashSet(StringComparer.OrdinalIgnoreCase)
            : [];
        string? anchorPath = _selectionFolder == folder ? _anchor?.File.Path : null;
        _selectionFolder = folder;
        _items = (files ?? []).Select(file => new SavedFileItem(file) { IsSelected = selected.Contains(file.Path) }).ToList();
        _anchor = anchorPath is null ? null : _items.FirstOrDefault(i => i.File.Path.Equals(anchorPath, StringComparison.OrdinalIgnoreCase));
        UpdateSelectionBar();
        RebuildRows(force: true);
        RestoreFocus(focus);
        bool empty = _items.Count == 0;
        EmptyState.Visibility = empty ? Visibility.Visible : Visibility.Collapsed;
        Rows.Visibility = empty ? Visibility.Collapsed : Visibility.Visible;
        bool unreadable = files is null;
        EmptyGlyph.Text = unreadable ? "\uE7BA" : "\uE8B7";
        EmptyTitle.Text = unreadable ? Loc.T("The destination folder could not be read.") : Loc.T("Nothing saved yet");
        EmptyBody.Text = unreadable
            ? Loc.T("Check that the folder exists and that you have permission to open it.")
            : Loc.T("Scans you save to this folder appear here, newest first.");
        EmptyFolder.Text = folder;
        // The header already names the folder; the full path is repeated only when it failed.
        EmptyFolder.Visibility = unreadable ? Visibility.Visible : Visibility.Collapsed;
    }

    // MARK: - Folder header

    private void ShowFolder(string folder)
    {
        string name = Path.GetFileName(folder.TrimEnd(Path.DirectorySeparatorChar, Path.AltDirectorySeparatorChar));
        FolderName.Text = name.Length > 0 ? name : folder;
        FolderName.ToolTip = folder;
        AutomationProperties.SetHelpText(FolderName, folder);
    }

    // MARK: - Rows and thumbnails

    /// <summary>Columns per row; room is always kept for a vertical scrollbar.</summary>
    private int ColumnCount() => GridInsets.Columns(Rows.ActualWidth);

    /// <summary>
    /// Centre the rows in the scroll viewport and line the header up with them, exactly as the
    /// History tab does, so switching between the two tabs does not shift the grid.
    /// </summary>
    private void UpdateInsets()
    {
        double width = Rows.Template?.FindName("RowsScroller", Rows) is ScrollViewer { ViewportWidth: > 0 } scroller
            ? scroller.ViewportWidth
            : Rows.ActualWidth;
        var (cards, header) = GridInsets.For(width, ColumnCount());
        RowInset = cards;
        Header.Margin = new Thickness(header.Left, 16, header.Right, 8);
        SelectionBar.Margin = new Thickness(header.Left, 0, header.Right, 8);
    }

    /// <summary>The viewport changed width (a scrollbar came or went): re-centre.</summary>
    private void Rows_ScrollChanged(object sender, ScrollChangedEventArgs e)
    {
        if (e.ViewportWidthChange != 0) UpdateInsets();
    }

    /// <summary>Cut the items into rows that fit the current width (only when the column count changes, unless forced).</summary>
    private bool RebuildRows(bool force)
    {
        int columns = ColumnCount();
        if (!force && columns == _columns) return false;
        _columns = columns;
        var rows = new List<SavedFileRow>();
        for (int i = 0; i < _items.Count; i += columns)
        {
            rows.Add(new SavedFileRow(_items.GetRange(i, Math.Min(columns, _items.Count - i))));
        }
        Rows.ItemsSource = rows;
        return true;
    }

    private void Rows_SizeChanged(object sender, SizeChangedEventArgs e)
    {
        if (!e.WidthChanged) return;
        var focus = FocusedPosition();
        if (RebuildRows(force: false)) RestoreFocus(focus);
        UpdateInsets();
    }

    private void Card_Loaded(object sender, RoutedEventArgs e)
    {
        if (sender is not FrameworkElement card) return;
        // When the list discards a row it clears the row's data context before (or instead
        // of) unloading its cards, so the card is tracked by element, not by DataContext.
        card.DataContextChanged -= Card_DataContextChanged;
        card.DataContextChanged += Card_DataContextChanged;
        AttachCard(card);
    }

    private void Card_Unloaded(object sender, RoutedEventArgs e)
    {
        if (sender is not FrameworkElement card) return;
        card.DataContextChanged -= Card_DataContextChanged;
        DetachCard(card);
    }

    private void Card_DataContextChanged(object sender, DependencyPropertyChangedEventArgs e)
    {
        if (sender is not FrameworkElement card) return;
        DetachCard(card);
        if (card.IsLoaded) AttachCard(card);
    }

    private void AttachCard(FrameworkElement card)
    {
        DetachCard(card);
        if (card.DataContext is not SavedFileItem item) return;
        _cardItems[card] = item;
        item.Cards.Add(card);
        if (item == _focusWhenLoaded)
        {
            _focusWhenLoaded = null;
            card.Focus();
        }
        LoadThumbnail(item, replace: false);
    }

    private void DetachCard(FrameworkElement card)
    {
        if (!_cardItems.Remove(card, out var item)) return;
        item.Cards.Remove(card);
        if (item.Cards.Count > 0) return;
        // Scrolled out of view (or the list was rebuilt): drop the decoded pixels.
        item.ThumbnailVersion++;
        item.Thumbnail = null;
    }

    /// <summary>
    /// Decode the item's thumbnail if a card is showing it. With <paramref name="replace"/>
    /// the current thumbnail stays up until the new one is ready (used after a rotate).
    /// </summary>
    private async void LoadThumbnail(SavedFileItem item, bool replace)
    {
        if (replace) item.ThumbnailVersion++;
        else if (item.Thumbnail is not null || item.LoadingVersion == item.ThumbnailVersion) return;
        int version = item.ThumbnailVersion;
        item.LoadingVersion = version;
        await _thumbnailGate.WaitAsync();
        try
        {
            // Scrolled past or superseded while waiting: skip the decode entirely.
            if (version != item.ThumbnailVersion || item.Cards.Count == 0) return;
            var thumbnail = await SavedFiles.LoadThumbnailAsync(item.File, ThumbnailDecodeWidth);
            if (version == item.ThumbnailVersion && item.Cards.Count > 0) item.Thumbnail = thumbnail;
        }
        finally
        {
            _thumbnailGate.Release();
            if (item.LoadingVersion == version) item.LoadingVersion = null;
        }
    }

    private static SavedFileItem? ItemOf(object sender) =>
        (sender as FrameworkElement)?.DataContext as SavedFileItem;

    private void Refresh_Click(object sender, RoutedEventArgs e) => Reload();

    private void RevealFolder_Click(object sender, RoutedEventArgs e)
    {
        if (_viewModel is null) return;
        string folder = _viewModel.DestinationFolder;
        try
        {
            Directory.CreateDirectory(folder);
            SavedFiles.Reveal(folder);
        }
        catch (Exception ex)
        {
            _showError?.Invoke(Loc.T("Could not open {0}: {1}", folder, ex.Message));
        }
    }

    // Ctrl or Shift on the thumbnail is left for selecting, not opening.
    private void Thumbnail_MouseDown(object sender, MouseButtonEventArgs e)
    {
        if ((Keyboard.Modifiers & (ModifierKeys.Control | ModifierKeys.Shift)) != 0) return;
        _thumbnailPressed = true;
        if (e.ClickCount == 1 && ItemOf(sender) is { } item) Open(item);
    }

    private void Card_MouseDown(object sender, MouseButtonEventArgs e)
    {
        if (sender is not FrameworkElement { DataContext: SavedFileItem item } card) return;
        card.Focus();
        bool onThumbnail = _thumbnailPressed;
        _thumbnailPressed = false;
        if (onThumbnail) return;
        var modifiers = Keyboard.Modifiers;
        SelectByClick(item, modifiers.HasFlag(ModifierKeys.Control), modifiers.HasFlag(ModifierKeys.Shift));
    }

    private void RowsPanel_Loaded(object sender, RoutedEventArgs e) => _rowsPanel = (RowsPanel)sender;

    private void Card_KeyDown(object sender, KeyEventArgs e)
    {
        if (sender is not FrameworkElement { DataContext: SavedFileItem item } card) return;
        var modifiers = Keyboard.Modifiers;
        if (modifiers.HasFlag(ModifierKeys.Alt)) return;
        bool shift = modifiers.HasFlag(ModifierKeys.Shift);
        if (e.Key == Key.A && modifiers == ModifierKeys.Control)
        {
            Select(_items);
            e.Handled = true;
            return;
        }
        if (modifiers == ModifierKeys.None && e.Key == Key.Escape && _items.Any(i => i.IsSelected))
        {
            ClearSelection();
            e.Handled = true;
            return;
        }
        if (modifiers == ModifierKeys.None && e.Key is Key.Enter or Key.Space)
        {
            if (e.OriginalSource != card) return;
            if (e.Key == Key.Enter)
            {
                Open(item);
            }
            else
            {
                SetSelected(item, !item.IsSelected);
                _anchor = item;
            }
            e.Handled = true;
            return;
        }
        bool rtl = card.FlowDirection == FlowDirection.RightToLeft;
        int step = e.Key switch
        {
            Key.Left => rtl ? 1 : -1,
            Key.Right => rtl ? -1 : 1,
            Key.Up => -_columns,
            Key.Down => _columns,
            _ => 0,
        };
        if (step == 0) return;
        e.Handled = true;
        int index = _items.IndexOf(item);
        int target = index + step;
        // Down from a column the last row doesn't have lands on the last card.
        if (e.Key == Key.Down && target >= _items.Count && index / _columns < (_items.Count - 1) / _columns)
        {
            target = _items.Count - 1;
        }
        if (target < 0 || target >= _items.Count) return;
        FocusItem(_items[target]);
        if (!shift) return;
        _anchor ??= item;
        SelectRange(_anchor, _items[target], keep: false);
    }

    // MARK: - Selection

    private int SelectedCount => _items.Count(i => i.IsSelected);

    private List<string> SelectedPaths() => _items.Where(i => i.IsSelected).Select(i => i.File.Path).ToList();

    private void SetItemSelected(SavedFileItem item, bool selected)
    {
        if (item.IsSelected == selected) return;
        item.IsSelected = selected;
        foreach (var card in item.Cards)
        {
            if (UIElementAutomationPeer.FromElement(card) is SavedCardPeer peer) peer.RaiseSelectedChanged(selected);
        }
    }

    /// <summary>Exactly these items are selected.</summary>
    private void Select(IEnumerable<SavedFileItem> chosen)
    {
        var set = chosen.ToHashSet();
        foreach (var item in _items) SetItemSelected(item, set.Contains(item));
        UpdateSelectionBar();
    }

    internal void SetSelected(SavedFileItem item, bool selected)
    {
        SetItemSelected(item, selected);
        UpdateSelectionBar();
    }

    internal void SelectOnly(SavedFileItem item)
    {
        Select([item]);
        _anchor = item;
    }

    private void SelectRange(SavedFileItem from, SavedFileItem to, bool keep)
    {
        int a = _items.IndexOf(from), b = _items.IndexOf(to);
        var range = _items.Skip(Math.Min(a, b)).Take(Math.Abs(a - b) + 1).ToList();
        Select(keep ? range.Concat(_items.Where(i => i.IsSelected)) : range);
    }

    private void SelectByClick(SavedFileItem item, bool ctrl, bool shift)
    {
        if (shift)
        {
            _anchor ??= item;
            SelectRange(_anchor, item, keep: ctrl);
        }
        else if (ctrl)
        {
            SetSelected(item, !item.IsSelected);
            _anchor = item;
        }
        else
        {
            SelectOnly(item);
        }
    }

    /// <summary>Clears the selection; a focused bar goes away with it, so the focus moves to a card.</summary>
    private void ClearSelection()
    {
        bool barFocused = SelectionBar.IsKeyboardFocusWithin;
        var back = _anchor ?? _items.FirstOrDefault(i => i.IsSelected);
        Select([]);
        _anchor = null;
        if (barFocused && back is not null) FocusItem(back);
    }

    private void ClearSelection_Click(object sender, RoutedEventArgs e) => ClearSelection();

    private void SelectionBar_KeyDown(object sender, KeyEventArgs e)
    {
        if (e.Key != Key.Escape || Keyboard.Modifiers != ModifierKeys.None || !_items.Any(i => i.IsSelected)) return;
        ClearSelection();
        e.Handled = true;
    }

    /// <summary>Below this bar width the action buttons show only their glyphs.</summary>
    private const double SelectionBarCompactBelowWidth = 760;

    private void SelectionBar_SizeChanged(object sender, SizeChangedEventArgs e)
    {
        if (!e.WidthChanged) return;
        bool compact = e.NewSize.Width < SelectionBarCompactBelowWidth;
        if (compact == _selectionCompact) return;
        _selectionCompact = compact;
        foreach (var button in SelectionButtons.Children.OfType<Button>()) SetButtonCompact(button);
    }

    private void SetButtonCompact(Button button)
    {
        if (_selectionCompact)
        {
            button.ContentTemplate = (DataTemplate)FindResource("IconOnlyTemplate");
            button.Padding = new Thickness(8, 5, 8, 6);
        }
        else
        {
            button.ClearValue(ContentControl.ContentTemplateProperty);
            button.ClearValue(PaddingProperty);
        }
    }

    private void SetSelectionButtonText(Button button, FileAction action, int count)
    {
        string label = action == FileAction.Share ? Loc.T("Share") : action.Label();
        bool waiting = false;
        if (action == FileAction.SendToPhone && _viewModel?.SendPhone is { } phone)
        {
            label = Loc.T("Send to {0}", AppViewModel.PhoneNameOf(phone));
            waiting = _viewModel.IsWaitingForPhone(SelectedPaths());
        }
        string hint = action == FileAction.Share ? Loc.T("Send by email or to an app") : FileActionMenu.Hint(action, count);
        if (waiting) hint = Loc.T("Waiting for {0} to fetch the last file.", AppViewModel.PhoneNameOf(_viewModel!.SendPhone!));
        button.Content = label;
        button.IsEnabled = !waiting;
        ToolTipService.SetShowOnDisabled(button, true);
        button.ToolTip = hint;
        AutomationProperties.SetName(button, Loc.T("{0} {1}", label, Loc.Plural(count, "{0} file", "{0} files")));
        AutomationProperties.SetHelpText(button, hint);
    }

    /// <summary>The bar is shown for two or more selected files, with the actions offered for all of them.</summary>
    internal void UpdateSelectionBar()
    {
        var paths = SelectedPaths();
        if (paths.Count < 2 || _viewModel is null)
        {
            SelectionBar.Visibility = Visibility.Collapsed;
            SelectionButtons.Children.Clear();
            return;
        }
        string text = Loc.T("{0} selected", paths.Count);
        bool textChanged = SelectionText.Text != text || SelectionBar.Visibility != Visibility.Visible;
        SelectionText.Text = text;
        var actions = _viewModel.OfferedFor(paths).ToList();
        var buttons = SelectionButtons.Children.OfType<Button>().ToList();
        if (!actions.SequenceEqual(buttons.Select(b => (FileAction)b.Tag)))
        {
            SelectionButtons.Children.Clear();
            buttons.Clear();
            foreach (var action in actions)
            {
                var button = new Button { Style = (Style)FindResource("SubtleButtonStyle"), Tag = action };
                Icon.SetGlyph(button, FileActionMenu.Glyph(action));
                SetButtonCompact(button);
                button.Click += SelectionAction_Click;
                SelectionButtons.Children.Add(button);
                buttons.Add(button);
            }
        }
        foreach (var button in buttons) SetSelectionButtonText(button, (FileAction)button.Tag, paths.Count);
        SelectionBar.Visibility = Visibility.Visible;
        if (textChanged) AnnounceSelection();
    }

    private void AnnounceSelection()
    {
        Dispatcher.BeginInvoke(() =>
        {
            if (!SelectionText.IsVisible) return;
            var peer = UIElementAutomationPeer.FromElement(SelectionText) ?? UIElementAutomationPeer.CreatePeerForElement(SelectionText);
            peer?.RaiseAutomationEvent(AutomationEvents.LiveRegionChanged);
        }, System.Windows.Threading.DispatcherPriority.ContextIdle);
    }

    private void SelectionAction_Click(object sender, RoutedEventArgs e)
    {
        if (sender is Button { Tag: FileAction action }) _viewModel?.RunFileAction(action, SelectedPaths());
    }

    /// <summary>Moves keyboard focus to the item's card, scrolling its row into view first when the card doesn't exist yet.</summary>
    private void FocusItem(SavedFileItem item)
    {
        _focusWhenLoaded = null;
        if (item.Cards.FirstOrDefault() is { } card)
        {
            card.Focus();
            card.BringIntoView();
            return;
        }
        _focusWhenLoaded = item;
        _rowsPanel?.ScrollRowIntoView(_items.IndexOf(item) / _columns);
    }

    /// <summary>The path and position of the card that has keyboard focus, so a rebuilt list can give it back.</summary>
    private (string Path, int Index)? FocusedPosition()
    {
        if (!Rows.IsKeyboardFocusWithin) return null;
        if ((Keyboard.FocusedElement as FrameworkElement)?.DataContext is not SavedFileItem item) return null;
        return (item.File.Path, _items.IndexOf(item));
    }

    /// <summary>Focus goes back to the same file's card, or to the nearest one when the file is gone.</summary>
    private void RestoreFocus((string Path, int Index)? focus)
    {
        if (focus is not { } was || _items.Count == 0) return;
        int index = _items.FindIndex(i => i.File.Path == was.Path);
        if (index < 0) index = Math.Min(was.Index, _items.Count - 1);
        // Every old row was just replaced, so the card is focused once its new one is realized.
        _focusWhenLoaded = _items[index];
        _rowsPanel?.ScrollRowIntoView(index / _columns);
    }

    private void Open_Click(object sender, RoutedEventArgs e)
    {
        if (ItemOf(sender) is { } item) Open(item);
    }

    private void Open(SavedFileItem item) => Run(FileAction.Open, item);

    private void Reveal_Click(object sender, RoutedEventArgs e)
    {
        if (ItemOf(sender) is { } item) Run(FileAction.Reveal, item);
    }

    private void Share_Click(object sender, RoutedEventArgs e)
    {
        if (ItemOf(sender) is { } item) Run(FileAction.Share, item);
    }

    /// <summary>The card's More button: every action on the file, under the button.</summary>
    private void More_Click(object sender, RoutedEventArgs e)
    {
        if (sender is FrameworkElement button && ItemOf(sender) is { } item)
        {
            FileActionMenu.ShowBelow(BuildFileMenu(item), button);
        }
    }

    /// <summary>The card's context menu (right-click, Shift+F10, Menu key): the same as More.</summary>
    private void Card_ContextMenuOpening(object sender, ContextMenuEventArgs e)
    {
        if (sender is FrameworkElement card && card.DataContext is SavedFileItem item)
        {
            if (!item.IsSelected) SelectOnly(item);
            card.ContextMenu = SelectedCount > 1 ? BuildSelectionMenu() : BuildFileMenu(item);
        }
        else
        {
            e.Handled = true;
        }
    }

    /// <summary>The actions for all the selected files, as the selection bar offers them.</summary>
    private ContextMenu BuildSelectionMenu()
    {
        var paths = SelectedPaths();
        var menu = FileActionMenu.Build(_viewModel?.OfferedFor(paths) ?? SaveActions.Offered(paths.Count), paths.Count,
                                        action => _viewModel?.RunFileAction(action, paths));
        NamePhone(menu, paths);
        return menu;
    }

    /// <summary>Names the phone on the menu's Send to phone item; it is off while the files wait for the phone.</summary>
    private void NamePhone(ContextMenu menu, IReadOnlyList<string> paths)
    {
        if (_viewModel?.SendPhone is { } phone) FileActionMenu.NamePhone(menu, AppViewModel.PhoneNameOf(phone), _viewModel.IsWaitingForPhone(paths));
    }

    /// <summary>Every action on one saved file, then Rotate for image files or Add the scanned pages for a PDF.</summary>
    internal ContextMenu BuildFileMenu(SavedFileItem item)
    {
        List<MenuItem> extra = [];
        if (item.File.ImageFormat is not null)
        {
            var rotate = FileActionMenu.Item(Loc.T("Rotate 90° clockwise"), "\uE7AD", Loc.T("Rotate the saved file 90° clockwise"),
                                             () => RotateItem(item));
            rotate.IsEnabled = item.CanRotate;
            extra.Add(rotate);
        }
        // A PDF takes the pages waiting in the queue at its end (offered while there are pages to
        // save and nothing else runs).
        if (item.File.IsPdf && _viewModel is { } viewModel)
        {
            var add = FileActionMenu.Item(PdfAppender.SavedMenuLabel, "\uE8E5", PdfAppender.SavedMenuHint,
                                          () => _ = viewModel.AppendToPdf(item.File.Path));
            add.IsEnabled = viewModel.CanAppendPages;
            extra.Add(add);
        }
        var menu = FileActionMenu.Build(_viewModel?.OfferedFor([item.File.Path]) ?? SaveActions.Offered(1), 1, action => Run(action, item), extra);
        NamePhone(menu, [item.File.Path]);
        return menu;
    }

    /// <summary>Carries out an action on the card's file; problems are reported in the InfoBar.</summary>
    private void Run(FileAction action, SavedFileItem item) => _viewModel?.RunFileAction(action, [item.File.Path]);

    private void Rotate_Click(object sender, RoutedEventArgs e)
    {
        if (ItemOf(sender) is { } item) RotateItem(item);
    }

    private async void RotateItem(SavedFileItem item)
    {
        if (item.IsRotating) return;
        item.IsRotating = true;
        var rotation = SavedFiles.RotateClockwiseAsync(item.File.Path);
        _pendingWork = Task.WhenAll(_pendingWork, rotation);
        string? failure = await rotation;
        item.IsRotating = false;
        if (failure is not null)
        {
            _showError?.Invoke(Loc.T("Could not rotate {0}: {1}", item.Name, failure));
            return;
        }
        // Refresh just this card (new date, size and thumbnail) instead of the whole folder.
        if (SavedFiles.Describe(item.File.Path) is { } updated) item.File = updated;
        LoadThumbnail(item, replace: true);
    }
}
