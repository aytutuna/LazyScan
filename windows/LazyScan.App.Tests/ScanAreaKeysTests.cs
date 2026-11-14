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

    [Fact]
    public void Move_KeepsTheSize_AndStaysOnTheBed()
    {
        var moved = MainWindow.MoveArea(new RectD(0.2, 0.3, 0.4, 0.4), 0.1, -0.1);
        Assert.Equal(0.3, moved.X, 6);
        Assert.Equal(0.2, moved.Y, 6);
        Assert.Equal(0.4, moved.Width, 6);
        var pinned = MainWindow.MoveArea(new RectD(0.2, 0.3, 0.4, 0.4), 2, -2);
        Assert.Equal(0.6, pinned.X, 6);
        Assert.Equal(0, pinned.Y, 6);
    }

    [Fact]
    public void Resize_ByACorner_KeepsTheOppositeCorner()
    {
        var r = MainWindow.ResizeArea(new RectD(0.2, 0.3, 0.4, 0.4), MainWindow.AreaHandle.TopLeft, 0.1, 0.2);
        Assert.Equal(0.1, r.X, 6);
        Assert.Equal(0.2, r.Y, 6);
        Assert.Equal(0.5, r.Width, 6);
        Assert.Equal(0.5, r.Height, 6);
    }

    [Fact]
    public void Resize_ByAnEdge_ChangesThatEdgeOnly()
    {
        var r = MainWindow.ResizeArea(new RectD(0.2, 0.3, 0.4, 0.4), MainWindow.AreaHandle.Right, 0.9, 0.0);
        Assert.Equal(0.2, r.X, 6);
        Assert.Equal(0.3, r.Y, 6);
        Assert.Equal(0.7, r.Width, 6);
        Assert.Equal(0.4, r.Height, 6);
        var bottom = MainWindow.ResizeArea(new RectD(0.2, 0.3, 0.4, 0.4), MainWindow.AreaHandle.Bottom, 0.0, 0.5);
        Assert.Equal(0.4, bottom.Width, 6);
        Assert.Equal(0.2, bottom.Height, 6);
    }

    [Fact]
    public void Resize_PastTheOppositeSide_StopsAtTheLeastSize_AndAtTheBed()
    {
        var r = MainWindow.ResizeArea(new RectD(0.2, 0.3, 0.4, 0.4), MainWindow.AreaHandle.Left, 0.9, 0.0);
        Assert.Equal(0.58, r.X, 6);
        Assert.Equal(0.02, r.Width, 6);
        var b = MainWindow.ResizeArea(new RectD(0.2, 0.3, 0.4, 0.4), MainWindow.AreaHandle.BottomRight, 1.5, 1.5);
        Assert.Equal(0.8, b.Width, 6);
        Assert.Equal(0.7, b.Height, 6);
    }

    [Fact]
    public void HitTest_HandlesWinOverTheInside_AndEdgesNeedRoom()
    {
        var area = new System.Windows.Rect(100, 100, 300, 180);
        Assert.Equal(MainWindow.AreaHandle.TopLeft, MainWindow.AreaHandleAt(area, new System.Windows.Point(95, 108)));
        Assert.Equal(MainWindow.AreaHandle.Right, MainWindow.AreaHandleAt(area, new System.Windows.Point(390, 190)));
        Assert.Equal(MainWindow.AreaHandle.Move, MainWindow.AreaHandleAt(area, new System.Windows.Point(250, 190)));
        Assert.Equal(MainWindow.AreaHandle.None, MainWindow.AreaHandleAt(area, new System.Windows.Point(450, 190)));
        var narrow = new System.Windows.Rect(100, 100, 30, 100);
        Assert.Equal(MainWindow.AreaHandle.Move, MainWindow.AreaHandleAt(narrow, new System.Windows.Point(115, 100 + 20 - 14)));
    }

    [Fact]
    public void SizeText_IsInMillimetersOrInches()
    {
        var bed = new SizeD(8.5, 11.7);
        var area = new RectD(0.1, 0.1, 0.5, 0.5);
        var mm = MainWindow.AreaSizeText(area, bed, false);
        Assert.Contains("108", mm);
        Assert.Contains("149", mm);
        var inches = MainWindow.AreaSizeText(area, bed, true);
        Assert.Contains(System.Globalization.CultureInfo.CurrentCulture.NumberFormat.NumberDecimalSeparator, inches);
        Assert.Contains("4", inches);
    }
}
