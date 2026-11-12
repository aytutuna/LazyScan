using System.Windows;
using System.Windows.Automation;
using System.Windows.Automation.Peers;
using System.Windows.Automation.Provider;
using Xunit;

namespace LazyScan.App.Tests;

public class FocusCanvasTests
{
    [Fact]
    public void Peer_AnnouncesTheNameAndTheValue()
    {
        RunSta(() =>
        {
            var canvas = new FocusCanvas();
            AutomationProperties.SetName(canvas, "Crop frame");
            canvas.AutomationValue = "100 × 200 px";

            var peer = UIElementAutomationPeer.CreatePeerForElement(canvas);
            Assert.Equal("Crop frame", peer.GetName());
            var value = (IValueProvider)peer.GetPattern(PatternInterface.Value)!;
            Assert.Equal("100 × 200 px", value.Value);

            canvas.AutomationValue = "120 × 200 px";
            Assert.Equal("120 × 200 px", value.Value);
        });
    }

    private static void RunSta(Action work)
    {
        Exception? failure = null;
        var thread = new Thread(() =>
        {
            try { work(); }
            catch (Exception e) { failure = e; }
        });
        thread.SetApartmentState(ApartmentState.STA);
        thread.Start();
        thread.Join();
        if (failure is not null) System.Runtime.ExceptionServices.ExceptionDispatchInfo.Throw(failure);
    }
}
