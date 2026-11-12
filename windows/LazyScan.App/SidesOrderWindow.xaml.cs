using System.Windows;
using LazyScan.Core;

namespace LazyScan.App;

/// <summary>Asks what to do when Save is pressed while the fronts and backs are not in order.</summary>
public partial class SidesOrderWindow : Window
{
    private SidesSaveChoice? _choice;

    public SidesOrderWindow()
    {
        FlowDirection = App.Flow;
        InitializeComponent();
    }

    /// <summary>Shows the dialog over <paramref name="owner"/>; the choice made, or null when cancelled.</summary>
    public static SidesSaveChoice? Ask(Window owner)
    {
        var dialog = new SidesOrderWindow { Owner = owner };
        dialog.ShowDialog();
        return dialog._choice;
    }

    private void Combine_Click(object sender, RoutedEventArgs e) => Choose(SidesSaveChoice.Combine);

    private void FrontsOnly_Click(object sender, RoutedEventArgs e) => Choose(SidesSaveChoice.FrontsOnly);

    private void Choose(SidesSaveChoice choice)
    {
        _choice = choice;
        DialogResult = true;
    }
}
