using LazyScan.Core;
using Xunit;

namespace LazyScan.App.Tests;

// The angle math of the Adjust crop window (PhotoCropEditorWindow): the handle's angle and the page clamp
// after a turn. The Mac has the same cases in Tests/LazyScanMacTests/CropGeometryTests.swift.
public class CropGeometryTests
{
    private const double PageWidth = 1000, PageHeight = 800;

    private static DetectedPhotoRegion Region(double x, double y, double w, double h, double angle) =>
        new(new PointD(x, y), new SizeD(w, h), angle, Guid.NewGuid());

    [Fact]
    public void AngleFrom_IsZeroWhenThePointerIsStraightAboveTheCenter()
    {
        var center = new PointD(400, 400);
        Assert.Equal(0, CropGeometry.AngleFrom(center, new PointD(400, 300)), 4);
        Assert.Equal(90, CropGeometry.AngleFrom(center, new PointD(500, 400)), 4);
    }

    [Fact]
    public void AngleFrom_FollowsTheHandleOfATurnedRegion()
    {
        double a = 30 * Math.PI / 180;
        var center = new PointD(400, 400);
        var handle = new PointD(center.X + 50 * Math.Sin(a), center.Y - 50 * Math.Cos(a));
        Assert.Equal(30, CropGeometry.AngleFrom(center, handle), 4);
    }

    [Fact]
    public void RotateTo_KeepsTheCenterAndTheSize()
    {
        var region = Region(500, 400, 200, 120, 3.2);
        CropGeometry.RotateTo(region, 12.5, PageWidth, PageHeight);
        Assert.Equal(12.5, region.AngleDegrees, 4);
        Assert.Equal(new PointD(500, 400), region.Center);
        Assert.Equal(new SizeD(200, 120), region.Size);
    }

    [Fact]
    public void RotateTo_MovesACropNearTheEdgeBackOnThePage()
    {
        var region = Region(500, 20, 100, 40, 0);
        CropGeometry.RotateTo(region, 90, PageWidth, PageHeight);
        Assert.Equal(500, region.Center.X, 4);
        Assert.Equal(50, region.Center.Y, 4);
        Assert.Equal(new SizeD(100, 40), region.Size);
        Assert.True(region.BoundingBox().Y >= -0.0001);
    }

    [Fact]
    public void RotateTo_CentersACropLargerThanThePage()
    {
        var region = Region(100, 100, 1200, 100, 0);
        CropGeometry.RotateTo(region, 5, PageWidth, PageHeight);
        Assert.Equal(500, region.Center.X, 4);
    }

    [Fact]
    public void RotateTo_KeepsTheAngleWithinHalfATurn()
    {
        var region = Region(500, 400, 100, 100, 170);
        CropGeometry.RotateTo(region, 175, PageWidth, PageHeight);
        Assert.Equal(175, region.AngleDegrees, 4);
        CropGeometry.RotateTo(region, 190, PageWidth, PageHeight);
        Assert.Equal(-170, region.AngleDegrees, 4);
        CropGeometry.RotateTo(region, 270, PageWidth, PageHeight);
        Assert.Equal(-90, region.AngleDegrees, 4);
        CropGeometry.RotateTo(region, -200, PageWidth, PageHeight);
        Assert.Equal(160, region.AngleDegrees, 4);
    }
}
