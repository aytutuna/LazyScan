using System.Windows;
using System.Windows.Automation;
using System.Windows.Automation.Peers;
using System.Windows.Automation.Provider;

namespace LazyScan.App;

/// <summary>
/// The peer of a panel that takes keyboard focus: it announces the name and help text and reads
/// out a value that the owner updates as keys are handled.
/// </summary>
internal sealed class ValuePanePeer(FrameworkElement pane, Func<string> value)
    : FrameworkElementAutomationPeer(pane), IValueProvider
{
    protected override AutomationControlType GetAutomationControlTypeCore() => AutomationControlType.Pane;

    protected override string GetClassNameCore() => Owner.GetType().Name;

    public override object? GetPattern(PatternInterface patternInterface) =>
        patternInterface == PatternInterface.Value ? this : base.GetPattern(patternInterface);

    public string Value => value();

    public bool IsReadOnly => true;

    public void SetValue(string value) => throw new InvalidOperationException();

    public void RaiseValueChanged(string old, string value) =>
        RaisePropertyChangedEvent(ValuePatternIdentifiers.ValueProperty, old, value);
}
