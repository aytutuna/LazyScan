using LazyScan.Core;
using Xunit;

namespace LazyScan.Core.Tests;

// A receipt joined from several pieces (a slip longer than the glass, scanned in parts). The Mac's twin is in
// Tests/LazyScanTests/AppStateSeamTests.swift, which joins and saves through the state.

public class ReceiptPiecesTests
{
    private static DetectedPhoto Piece(int width = 10, int height = 20) =>
        new(new DetectedPhotoRegion(new PointD(5, 5), new SizeD(width, height), 0), RgbaImage.Filled(width, height, 255, 255, 255), 300);

    [Fact]
    public void APlainReceiptIsItsOnlyPiece()
    {
        var receipt = Piece();

        Assert.Empty(receipt.Joined);
        Assert.Same(receipt, Assert.Single(receipt.Pieces));
    }

    [Fact]
    public void JoiningMakesTheLaterOneAPieceAfterTheEarlier()
    {
        var first = Piece();
        var second = Piece();
        var third = Piece();

        Receipts.Join(first, second);
        Receipts.Join(first, third);

        Assert.Equal([first, second, third], first.Pieces);
    }

    [Fact]
    public void JoiningAJoinedReceiptCarriesItsPieces()
    {
        var first = Piece();
        var second = Piece();
        var third = Piece();
        Receipts.Join(second, third);

        Receipts.Join(first, second);

        Assert.Equal([first, second, third], first.Pieces);
        Assert.Empty(second.Joined);
    }

    [Fact]
    public void SplittingGivesTheKeptPiecesBackAsReceipts()
    {
        var first = Piece();
        var second = Piece();
        Receipts.Join(first, second);
        first.Included = false;

        var pieces = Receipts.Split(first);

        Assert.Equal([first, second], pieces);
        Assert.Empty(first.Joined);
        Assert.All(pieces, p => Assert.False(p.Included));
    }

    [Fact]
    public void TheCaptionCountsThePieces()
    {
        Assert.Equal("2 pieces", Receipts.PiecesCaption(2));
        Assert.Equal("3 pieces", Receipts.PiecesCaption(3));
    }

    [Fact]
    public void TheHintNamesTheGlassOrTheFeeder()
    {
        Assert.Equal("Scan more adds to these. Lay the next receipts on the glass first.", Receipts.ScanMoreHint(ScanSource.Flatbed));
        Assert.Equal("Scan more adds to these. Put the next receipts in the feeder first.", Receipts.ScanMoreHint(ScanSource.DocumentFeeder));
    }

    [Fact]
    public void StackedPiecesShareTheWidestWidth()
    {
        var wide = RgbaImage.Filled(20, 10, 0, 0, 0);
        var narrow = RgbaImage.Filled(10, 10, 255, 255, 255);

        var stacked = Receipts.Stack([wide, narrow]);

        // The narrow piece is scaled up to 20 pixels wide, so it is 20 tall.
        Assert.Equal(20, stacked.Width);
        Assert.Equal(30, stacked.Height);
        Assert.Equal(0, stacked.Pixels[0]);
        Assert.Equal(0, stacked.Pixels[(9 * 20 + 19) * 4]);
        Assert.Equal(255, stacked.Pixels[(10 * 20) * 4]);
        Assert.Equal(255, stacked.Pixels[(29 * 20 + 19) * 4]);
    }

    [Fact]
    public void ASinglePieceStaysAsItIs()
    {
        var image = RgbaImage.Filled(10, 10, 1, 2, 3);

        Assert.Same(image, Receipts.Stack([image]));
    }
}
