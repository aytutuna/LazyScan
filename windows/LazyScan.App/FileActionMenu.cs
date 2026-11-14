using System.Windows;
using System.Windows.Automation;
using System.Windows.Controls;
using System.Windows.Controls.Primitives;
using LazyScan.Core;

namespace LazyScan.App;

/// <summary>
/// The glyphs and the menu of the actions on saved files (<see cref="FileAction"/>), shared by
/// the Saved tab's cards and the bar shown after a save.
/// </summary>
public static class FileActionMenu
{
    public static string Glyph(FileAction action) => action switch
    {
        FileAction.Open => "",
        FileAction.OpenWith => "",
        FileAction.Reveal => "",
        FileAction.Share => "",
        FileAction.Email => "",
        FileAction.LazyPrint => "",
        FileAction.Copy => "",
        FileAction.SendToPhone => "",
        _ => "",
    };

    /// <summary>What the action does, for tooltips and screen readers.</summary>
    public static string Hint(FileAction action, int fileCount) => action switch
    {
        FileAction.Open => Loc.T("Open with the default app"),
        FileAction.OpenWith => Loc.T("Choose the app to open it with"),
        FileAction.Reveal => Loc.T("Show in File Explorer"),
        FileAction.Share => Loc.T("Send with Mail, Outlook, nearby sharing or another app"),
        FileAction.Email => Loc.T("Attach to an email: choose Mail or Outlook in the share window"),
        FileAction.LazyPrint => Loc.T("Open it in Lazy Print, then choose a printer and print"),
        FileAction.Copy => fileCount == 1 ? Loc.T("Copy the file to the clipboard") : Loc.T("Copy the files to the clipboard"),
        FileAction.SendToPhone => Loc.Plural(fileCount, "Send this file to your phone. It is fetched the next time Lazy Scan is open on the phone.",
            "Send these files to your phone. They are fetched the next time Lazy Scan is open on the phone."),
        _ => "",
    };

    /// <summary>
    /// A menu with one item per action (in <paramref name="actions"/> order), then
    /// <paramref name="extra"/> items after a separator. Each item runs <paramref name="run"/>.
    /// </summary>
    public static ContextMenu Build(IReadOnlyList<FileAction> actions, int fileCount, Action<FileAction> run,
                                    IReadOnlyList<MenuItem>? extra = null)
    {
        var menu = new ContextMenu();
        foreach (var action in actions)
        {
            var item = new MenuItem
            {
                Header = action.Label(),
                Icon = GlyphBlock(Glyph(action)),
                ToolTip = Hint(action, fileCount),
                Tag = action,
            };
            item.Click += (_, _) => run(action);
            menu.Items.Add(item);
        }
        if (extra is { Count: > 0 })
        {
            if (menu.Items.Count > 0) menu.Items.Add(new Separator());
            foreach (var item in extra) menu.Items.Add(item);
        }
        return menu;
    }

    /// <summary>
    /// Names the phone on the Send to phone item of a menu built by <see cref="Build"/>, and turns it off
    /// while the file waits for the phone to fetch it.
    /// </summary>
    public static void NamePhone(ContextMenu menu, string phoneName, bool waiting)
    {
        if (menu.Items.OfType<MenuItem>().FirstOrDefault(i => i.Tag is FileAction.SendToPhone) is not { } item) return;
        item.Header = Loc.T("Send to {0}", phoneName);
        item.IsEnabled = !waiting;
        ToolTipService.SetShowOnDisabled(item, true);
        if (waiting) item.ToolTip = Loc.T("Waiting for {0} to fetch the last file.", phoneName);
        AutomationProperties.SetAutomationId(item, "SendToPhoneMenuItem");
    }

    /// <summary>A menu item with a glyph, for <see cref="Build"/>'s extra items.</summary>
    public static MenuItem Item(string header, string glyph, string toolTip, Action click)
    {
        var item = new MenuItem { Header = header, Icon = GlyphBlock(glyph), ToolTip = toolTip };
        item.Click += (_, _) => click();
        return item;
    }

    /// <summary>Opens <paramref name="menu"/> under <paramref name="button"/>.</summary>
    public static void ShowBelow(ContextMenu menu, FrameworkElement button)
    {
        menu.PlacementTarget = button;
        menu.Placement = PlacementMode.Bottom;
        menu.IsOpen = true;
    }

    private static TextBlock GlyphBlock(string glyph)
    {
        var block = new TextBlock { Text = glyph };
        block.SetResourceReference(FrameworkElement.StyleProperty, "GlyphText");
        return block;
    }
}
