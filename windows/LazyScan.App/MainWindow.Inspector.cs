using System.Windows;
using System.Windows.Automation;
using System.Windows.Controls;
using System.Windows.Controls.Primitives;
using System.Windows.Input;
using System.Windows.Shapes;
using LazyScan.Core;

namespace LazyScan.App;

// The inspector's sections (InspectorSections): their headers, which are open (as the user left them,
// remembered in the preferences), what each shows for the task and format, and the summary a collapsed
// header gives of what is on in it. Also the file name's Insert menu and its live preview.
public partial class MainWindow
{
    /// <summary>A section of the inspector: its Expander and the parts of its header.</summary>
    private sealed record InspectorSection(string Id, Expander Expander, TextBlock Title, TextBlock Summary,
                                           FrameworkElement Dot, TextBlock Lock)
    {
        public string TitleText => Title.Text;
    }

    private readonly List<InspectorSection> _sections = [];
    /// <summary>The sections are being opened or closed by the app (a task opening its section): not remembered.</summary>
    private bool _settingSections;

    private void SetUpInspectorSections()
    {
        // TaskTitle needs the settings of a task in progress; these two headers are fixed.
        Add(CopyOptions, InspectorSections.Task, "", Loc.T("Photocopy"));
        Add(ReceiptOptions, InspectorSections.Task, "", Loc.T("Receipts"));
        Add(ScannerSection, InspectorSections.Scanner, "", InspectorSections.Title(InspectorSections.Scanner));
        Add(OutputSection, InspectorSections.Output, "", InspectorSections.Title(InspectorSections.Output));
        Add(AdjustmentsSection, InspectorSections.Adjustments, "", InspectorSections.Title(InspectorSections.Adjustments));
        Add(PagesSection, InspectorSections.Pages, "", InspectorSections.Title(InspectorSections.Pages));
        Add(SplitSection, InspectorSections.Split, "", InspectorSections.Title(InspectorSections.Split));
        Add(ArchiveSection, InspectorSections.Archive, "", InspectorSections.Title(InspectorSections.Archive));
        Add(MoreSection, InspectorSections.More, "", InspectorSections.Title(InspectorSections.More));

        Dictionary<string, bool> saved;
        try
        {
            saved = AppPreferencesStore.Load().InspectorSections;
        }
        catch
        {
            saved = [];
        }
        _settingSections = true;
        try
        {
            foreach (var section in _sections)
            {
                section.Expander.IsExpanded = saved.TryGetValue(section.Id, out bool open) ? open : InspectorSections.OpenByDefault(section.Id);
            }
        }
        finally
        {
            _settingSections = false;
        }
    }

    private void Add(Expander expander, string id, string glyph, string title)
    {
        var icon = new TextBlock { Text = glyph, Margin = new Thickness(0, 2, 12, 0), VerticalAlignment = VerticalAlignment.Top };
        icon.SetResourceReference(StyleProperty, "GlyphText");
        var titleText = new TextBlock { Text = title, TextWrapping = TextWrapping.NoWrap, VerticalAlignment = VerticalAlignment.Center };
        titleText.SetResourceReference(StyleProperty, "BodyStrongText");
        // A 6 DIP accent dot: something in the collapsed section differs from the default.
        var dot = new Ellipse { Width = 6, Height = 6, Margin = new Thickness(8, 1, 0, 0), VerticalAlignment = VerticalAlignment.Center, Visibility = Visibility.Collapsed };
        dot.SetResourceReference(Shape.FillProperty, "AccentFillColorDefaultBrush");
        var titleRow = new StackPanel { Orientation = Orientation.Horizontal };
        titleRow.Children.Add(titleText);
        titleRow.Children.Add(dot);
        var lockGlyph = new TextBlock { Text = "", FontSize = 12, Margin = new Thickness(0, 1, 4, 0), Visibility = Visibility.Collapsed, VerticalAlignment = VerticalAlignment.Top };
        lockGlyph.SetResourceReference(StyleProperty, "GlyphText");
        lockGlyph.SetResourceReference(TextBlock.ForegroundProperty, "TextFillColorSecondaryBrush");
        var summary = new TextBlock { Visibility = Visibility.Collapsed, MaxWidth = 196 };
        summary.SetResourceReference(StyleProperty, "SectionSummaryText");
        var summaryRow = new StackPanel { Orientation = Orientation.Horizontal };
        summaryRow.Children.Add(lockGlyph);
        summaryRow.Children.Add(summary);
        var texts = new StackPanel { VerticalAlignment = VerticalAlignment.Center };
        texts.Children.Add(titleRow);
        texts.Children.Add(summaryRow);
        var header = new DockPanel();
        DockPanel.SetDock(icon, Dock.Left);
        header.Children.Add(icon);
        header.Children.Add(texts);
        expander.Header = header;
        expander.Tag = id;
        var section = new InspectorSection(id, expander, titleText, summary, dot, lockGlyph);
        _sections.Add(section);
        expander.Expanded += (_, e) => SectionToggled(section, e);
        expander.Collapsed += (_, e) => SectionToggled(section, e);
    }

    private void SectionToggled(InspectorSection section, RoutedEventArgs e)
    {
        if (!ReferenceEquals(e.OriginalSource, section.Expander)) return;
        if (IsLoaded) SyncInspectorSections();
        if (_settingSections) return;
        bool open = section.Expander.IsExpanded;
        try
        {
            AppPreferencesStore.Update(preferences => preferences.InspectorSections[section.Id] = open);
        }
        catch
        {
            // The preferences could not be written: the section stays as it is for this session.
        }
    }

    /// <summary>Opens a section for a task that needs it (Restore old photos opens Adjustments); not remembered.</summary>
    private void OpenSectionFor(ScanTask task)
    {
        if (InspectorSections.OpenedBy(task) is not { } id) return;
        _settingSections = true;
        try
        {
            foreach (var section in _sections.Where(s => s.Id == id)) section.Expander.IsExpanded = true;
        }
        finally
        {
            _settingSections = false;
        }
    }

    /// <summary>
    /// Which sections show for the task and format (hide what can't apply), and each collapsed
    /// header's summary, accent dot and accessible name.
    /// </summary>
    private void SyncInspectorSections()
    {
        if (_sections.Count == 0) return;
        var s = ViewModel.Settings;
        bool copy = TaskCatalog.FlowOf(s) == TaskFlowKind.Copy;
        var shownFormat = ShownFormat(s);
        bool textApplies = InspectorSections.TextApplies(s);

        PagesSection.Visibility = InspectorSections.Shown(s).Contains(InspectorSections.Pages) ? Visibility.Visible : Visibility.Collapsed;
        SplitSection.Visibility = PagesSection.Visibility;
        // Archive & password apply whenever the save writes a PDF (a queue of image pages too, and a
        // copy also saved as a PDF), not only when PDF is the format shown.
        ArchiveSection.Visibility = WritesPdf(s) ? Visibility.Visible : Visibility.Collapsed;
        AlsoSaveTextBox.Visibility = textApplies ? Visibility.Visible : Visibility.Collapsed;
        // A copy runs nothing after it is printed: After saving is hidden for it, and More's summary
        // leaves the action out.
        AfterSaveRow.Visibility = copy ? Visibility.Collapsed : Visibility.Visible;
        var output = _sections.First(x => x.Id == InspectorSections.Output);
        output.Title.Text = InspectorSections.Title(InspectorSections.Output, s);

        foreach (var section in _sections)
        {
            string summary = "";
            bool changed = false;
            bool locked = false;
            string? name = null;
            switch (section.Id)
            {
                case InspectorSections.Scanner:
                    summary = InspectorSections.ScannerSummary(s);
                    changed = InspectorSections.ScannerChanged(s);
                    break;
                case InspectorSections.Output:
                    summary = InspectorSections.OutputSummary(s, shownFormat);
                    changed = InspectorSections.OutputChanged(s, shownFormat);
                    break;
                case InspectorSections.Adjustments:
                    summary = InspectorSections.AdjustmentsSummary(s.Adjustments);
                    changed = summary.Length > 0;
                    break;
                case InspectorSections.Pages:
                    summary = InspectorSections.PagesSummary(s.Document);
                    changed = summary.Length > 0;
                    name = InspectorSections.PagesHeaderName(s.Document);
                    break;
                case InspectorSections.Split:
                    summary = InspectorSections.SplitSummary(s.Document);
                    changed = s.Document.SplitMode != SplitMode.None;
                    break;
                case InspectorSections.Archive:
                    summary = InspectorSections.ArchiveSummary(s.Output);
                    changed = s.Output.Protect || s.Output.Archival;
                    locked = s.Output.Protect;
                    break;
                case InspectorSections.More:
                    var more = s.Output.Clone();
                    if (copy) more.AfterSave = AfterSaveAction.None;
                    summary = InspectorSections.MoreSummary(more, textApplies);
                    changed = summary.Length > 0;
                    break;
            }
            bool collapsed = !section.Expander.IsExpanded;
            section.Summary.Text = summary;
            section.Summary.Visibility = collapsed && summary.Length > 0 ? Visibility.Visible : Visibility.Collapsed;
            section.Lock.Visibility = collapsed && locked ? Visibility.Visible : Visibility.Collapsed;
            section.Dot.Visibility = collapsed && changed ? Visibility.Visible : Visibility.Collapsed;
            AutomationProperties.SetName(section.Expander,
                name ?? InspectorSections.HeaderName(section.TitleText, summary));
        }
        SyncFileNamePreview();
    }

    /// <summary>
    /// The save of document pages writes a PDF: a queue saves one for an image format too
    /// (<see cref="OutputFormats.QueueFormat"/>), receipts and the ID card save a PDF or an image
    /// (<see cref="OutputFormats.PageFormat"/>), and a copy with Also save as PDF on saves a PDF
    /// whatever the format. Photos never do.
    /// </summary>
    internal static bool WritesPdf(ScanSettings s) => InspectorSections.WritesPdf(s);

    /// <summary>
    /// The format the inspector shows: photos save an image (a PDF or text format shows as JPEG),
    /// receipts and the ID card a PDF or an image (Word and text show as PDF), and a copy a PDF or nothing (it shows as PDF).
    /// </summary>
    private static OutputFormat ShownFormat(ScanSettings s) => InspectorSections.ShownFormat(s);

    // MARK: - File name: the Insert menu and the preview

    private void InsertToken_Click(object sender, RoutedEventArgs e)
    {
        var menu = new ContextMenu { PlacementTarget = InsertTokenButton, Placement = PlacementMode.Bottom };
        foreach (var part in NamingTokens.All)
        {
            var item = new MenuItem { Header = part.Label, InputGestureText = part.Token };
            item.Click += (_, _) => InsertToken(part.Token);
            menu.Items.Add(item);
        }
        menu.IsOpen = true;
    }

    /// <summary>Puts <paramref name="token"/> where the caret was in the file name, and saves the name.</summary>
    internal void InsertToken(string token)
    {
        var insertion = NamingTokens.Insert(token, TemplateBox.Text, TemplateBox.CaretIndex);
        TemplateBox.Text = insertion.Text;
        TemplateBox.CaretIndex = insertion.Caret;
        TemplateBox.Focus();
        if (!string.IsNullOrWhiteSpace(TemplateBox.Text))
        {
            ViewModel.Settings.NamingTemplate = TemplateBox.Text;
            ViewModel.SettingsEdited();
            // Name by receipt date's reason and tooltip follow the file name ({docdate} may just have come in).
            SyncReceiptOptions();
        }
        SyncFileNamePreview();
    }

    private void TemplateBox_TextChanged(object sender, TextChangedEventArgs e)
    {
        if (IsLoaded) SyncFileNamePreview();
    }

    /// <summary>What the preview was last worked out for, so the counter file is not read at every refresh.</summary>
    private string? _previewSignature;

    /// <summary>The name the next file gets ("Scan 2026-10-20 4.pdf"), under the File name box.</summary>
    private void SyncFileNamePreview()
    {
        var s = ViewModel.Settings;
        string template = TemplateBox.Text.Trim().Length > 0 ? TemplateBox.Text : s.NamingTemplate;
        string signature = string.Join('\u001f', template, s.Format, s.Intent, s.DocumentMultiPage, ViewModel.SavedRevision,
                                       DateTime.Now.ToString("yyyyMMddHHmm"), TaskCatalog.Infer(s));
        if (signature == _previewSignature) return;
        _previewSignature = signature;
        string? name = ViewModel.FileNamePreview(template);
        FileNamePreview.Text = name ?? "";
        FileNamePreview.Visibility = name is null ? Visibility.Collapsed : Visibility.Visible;
        AutomationProperties.SetHelpText(TemplateBox, name is null ? "" : Loc.T("The next file is named {0}", name));
        string? suggested = name is null ? null : System.IO.Path.GetFileNameWithoutExtension(name);
        SaveNameHint.Text = suggested ?? "";
        AutomationProperties.SetHelpText(SaveNameBox, suggested ?? "");
    }

    // MARK: - The name for one save

    private void SaveName_TextChanged(object sender, TextChangedEventArgs e)
    {
        ViewModel.SaveName = SaveNameBox.Text;
        SaveNameHint.Visibility = SaveNameBox.Text.Length == 0 ? Visibility.Visible : Visibility.Collapsed;
        ClearSaveNameButton.Visibility = SaveNameBox.Text.Length > 0 && SaveNameBox.IsEnabled ? Visibility.Visible : Visibility.Collapsed;
    }

    private void SaveName_PreviewKeyDown(object sender, KeyEventArgs e)
    {
        if (e.Key == Key.Enter && Keyboard.Modifiers == ModifierKeys.None && SavePdfButton.IsEnabled)
        {
            e.Handled = true;
            _ = ViewModel.SavePdf();
        }
        else if (e.Key == Key.Escape && SaveNameBox.Text.Length > 0)
        {
            e.Handled = true;
            SaveNameBox.Clear();
        }
    }

    private void ClearSaveName_Click(object sender, RoutedEventArgs e)
    {
        SaveNameBox.Clear();
        SaveNameBox.Focus();
    }

    /// <summary>
    /// The field shows the name the template would give until something is typed. It is off while the
    /// queue is saved as several documents (the page strip names each) and while pages are added to a PDF.
    /// </summary>
    private void SyncSaveName(bool split)
    {
        if (SaveNameBox.Text != ViewModel.SaveName) SaveNameBox.Text = ViewModel.SaveName;
        bool free = !ViewModel.IsBusy && !split && ViewModel.AppendTarget is null
                    && ViewModel.Settings.DocumentMultiPage;
        SaveNameBox.IsEnabled = free;
        ClearSaveNameButton.IsEnabled = free;
        ClearSaveNameButton.Visibility = SaveNameBox.Text.Length > 0 && free ? Visibility.Visible : Visibility.Collapsed;
        SaveNameBox.ToolTip = split ? Loc.T("Each document is named in the page strip.")
            : Loc.T("Name this file. Leave empty to use the file name from More options.");
    }
}
