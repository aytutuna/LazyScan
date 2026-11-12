using System.Windows.Automation.Peers;
using System.Windows.Controls;

namespace LazyScan.App;

/// <summary>
/// The canvas of an editor that takes keyboard focus for its arrow keys. A plain Canvas has no
/// automation peer, so screen readers would never see its name, help text or the value it reports.
/// </summary>
internal sealed class FocusCanvas : Canvas
{
    private string _automationValue = "";

    /// <summary>What a screen reader reads after the name, for example where a corner or the cut is.</summary>
    public string AutomationValue
    {
        get => _automationValue;
        set
        {
            if (_automationValue == value) return;
            var old = _automationValue;
            _automationValue = value;
            (UIElementAutomationPeer.FromElement(this) as ValuePanePeer)?.RaiseValueChanged(old, value);
        }
    }

    protected override AutomationPeer OnCreateAutomationPeer() => new ValuePanePeer(this, () => _automationValue);
}
