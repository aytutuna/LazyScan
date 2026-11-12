using LazyScan.Core;
using Xunit;

namespace LazyScan.App.Tests;

public class ScanAreaKeysTests
{
    [Fact]
    public void Nudge_WithNoArea_StartsFromTheMiddleQuarter()
    {
        var area = MainWindow.NudgeArea(null, 1, 0, false);
        Assert.Equal(0.26, area.X, 6);
        Assert.Equal(0.25, area.Y, 6);
        Assert.Equal(0.5, area.Width, 6);
        Assert.Equal(0.5, area.Height, 6);
    }

    [Fact]
    public void Nudge_MovesByOnePercent_AndStaysOnTheBed()
    {
        var moved = MainWindow.NudgeArea(new RectD(0.2, 0.3, 0.4, 0.4), -1, 1, false);
        Assert.Equal(0.19, moved.X, 6);
        Assert.Equal(0.31, moved.Y, 6);
        Assert.Equal(new RectD(0, 0.3, 0.4, 0.4), MainWindow.NudgeArea(new RectD(0, 0.3, 0.4, 0.4), -1, 0, false));
        Assert.Equal(0.6, MainWindow.NudgeArea(new RectD(0.6, 0.3, 0.4, 0.4), 1, 0, false).X, 6);
    }

    [Fact]
    public void Nudge_WithResize_KeepsTheTopLeftCorner_AndALeastSize()
    {
        var grown = MainWindow.NudgeArea(new RectD(0.2, 0.3, 0.4, 0.4), 1, 1, true);
        Assert.Equal(0.2, grown.X, 6);
        Assert.Equal(0.3, grown.Y, 6);
        Assert.Equal(0.41, grown.Width, 6);
        Assert.Equal(0.41, grown.Height, 6);
        Assert.Equal(0.02, MainWindow.NudgeArea(new RectD(0.2, 0.3, 0.02, 0.02), -1, -1, true).Width, 6);
        Assert.Equal(0.8, MainWindow.NudgeArea(new RectD(0.2, 0.3, 0.8, 0.4), 1, 0, true).Width, 6);
    }

    [Fact]
    public void Nudge_WithResize_AtTheFarEdge_DoesNotThrow()
    {
        var area = MainWindow.NudgeArea(new RectD(0.99, 0.3, 0.01, 0.4), 0, 1, true);
        Assert.Equal(0.01, area.Width, 6);
        Assert.Equal(0.41, area.Height, 6);
    }
}
