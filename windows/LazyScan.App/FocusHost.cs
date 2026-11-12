using System.Windows.Automation;
using System.Windows.Automation.Peers;
using System.Windows.Automation.Provider;
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
            (UIElementAutomationPeer.FromElement(this) as Peer)?.RaiseValueChanged(old, value);
        }
    }

    protected override AutomationPeer OnCreateAutomationPeer() => new Peer(this);

    private sealed class Peer(FocusHost owner) : FrameworkElementAutomationPeer(owner), IValueProvider
    {
        protected override AutomationControlType GetAutomationControlTypeCore() => AutomationControlType.Pane;

        protected override string GetClassNameCore() => nameof(FocusHost);

        public override object? GetPattern(PatternInterface patternInterface) =>
            patternInterface == PatternInterface.Value ? this : base.GetPattern(patternInterface);

        public string Value => owner.AutomationValue;

        public bool IsReadOnly => true;

        public void SetValue(string value) => throw new InvalidOperationException();

        public void RaiseValueChanged(string old, string value) =>
            RaisePropertyChangedEvent(ValuePatternIdentifiers.ValueProperty, old, value);
    }
}
