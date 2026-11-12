using System.Windows.Automation.Peers;
using System.Windows.Controls;

namespace LazyScan.App;

/// <summary>
/// A grid that takes keyboard focus for the keys its owner handles. A plain Grid has no
/// automation peer, so screen readers would never see its name or the value it reports.
/// </summary>
internal sealed class FocusHost : Grid
{
    private string _automationValue = "";

    /// <summary>What a screen reader reads after the name, for example where a rectangle is.</summary>
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
