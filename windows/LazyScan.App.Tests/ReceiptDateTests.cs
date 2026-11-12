using System.Windows.Media;
using System.Windows.Media.Imaging;
using LazyScan.Core;
using Xunit;

namespace LazyScan.App.Tests;

// The date on a receipt's card in the review: read, typed, cleared, reverted, and kept across a new read.
public class ReceiptDateTests
{
    private static PhotoItem Card()
    {
        var region = new DetectedPhotoRegion(new PointD(5, 5), new SizeD(10, 10), 0);
        var photo = new DetectedPhoto(region, RgbaImage.Filled(10, 10, 255, 255, 255), 300);
        var thumbnail = BitmapSource.Create(1, 1, 72, 72, PixelFormats.Bgra32, null, new byte[4], 4);
        return new PhotoItem(photo, thumbnail) { DatesShown = true };
    }

    private static ReceiptReading Read(DocumentDate? date) => new(0, [], null, date);

    [Fact]
    public void AReadDateShowsInTheBox()
    {
        var card = Card();
        card.BeginReading();
        Assert.True(card.IsReading);
        Assert.False(card.HasNoDate);

        card.EndReading(Read(new DocumentDate(2026, 3, 12)));

        Assert.False(card.IsReading);
        Assert.Equal("2026-03-12", card.DateText);
        Assert.False(card.HasNoDate);
        Assert.Equal("", card.NoDateHelp);
        Assert.Equal(new DocumentDate(2026, 3, 12), card.Photo.ReceiptDate);
    }

    [Fact]
    public void ANoDateReadMarksTheCardUndated()
    {
        var card = Card();
        card.BeginReading();
        card.EndReading(new ReceiptReading(0, null, "no OCR", null));

        Assert.Equal("", card.DateText);
        Assert.True(card.HasNoDate);
        Assert.True(card.DateHintShown);
        Assert.Equal("No date was found on this receipt", card.NoDateHelp);
    }

    [Fact]
    public void ATypedDateReplacesTheReadOne()
    {
        var card = Card();
        card.BeginReading();
        card.EndReading(Read(new DocumentDate(2026, 3, 12)));

        card.DateText = "2026-04-01";

        Assert.Equal(new DocumentDate(2026, 4, 1), card.Photo.ReceiptDate);
        Assert.False(card.DateInvalid);
    }

    [Fact]
    public void ClearingTheBoxMakesTheReceiptUndated()
    {
        var card = Card();
        card.BeginReading();
        card.EndReading(Read(new DocumentDate(2026, 3, 12)));

        card.DateText = "";

        Assert.Null(card.Photo.ReceiptDate);
        Assert.True(card.HasNoDate);
        Assert.False(card.DateInvalid);
    }

    [Theory]
    [InlineData("2026-02-30")]
    [InlineData("2026-1-5x")]
    [InlineData("12/03/2026")]
    public void AnInvalidDateLeavesTheReceiptUndated(string text)
    {
        var card = Card();
        card.BeginReading();
        card.EndReading(Read(new DocumentDate(2026, 3, 12)));

        card.DateText = text;

        Assert.Null(card.Photo.ReceiptDate);
        Assert.True(card.DateInvalid);
        Assert.True(card.HasNoDate);
        Assert.Equal(text, card.DateText);
    }

    [Fact]
    public void ReadingAgainKeepsATypedDate()
    {
        var card = Card();
        card.DateText = "2026-04-01";

        card.BeginReading();
        card.EndReading(Read(new DocumentDate(2026, 3, 12)));

        Assert.Equal(new DocumentDate(2026, 4, 1), card.Photo.ReceiptDate);
        Assert.Equal("2026-04-01", card.DateText);
    }

    [Fact]
    public void ATurnDropsTheReadDate()
    {
        var card = Card();
        card.BeginReading();
        card.EndReading(Read(new DocumentDate(2026, 3, 12)));

        card.RotateClockwise();

        Assert.False(card.Photo.IsRead);
        Assert.Equal("", card.DateText);
    }

    [Fact]
    public void EscapeBringsBackTheFoundDate()
    {
        var card = Card();
        card.BeginReading();
        card.EndReading(Read(new DocumentDate(2026, 11, 3)));

        card.BeginDateEdit();
        card.DateText = "2026-11-0";
        Assert.True(card.DateInvalid);
        card.RevertDateText();

        Assert.Equal("2026-11-03", card.DateText);
        Assert.Equal(new DocumentDate(2026, 11, 3), card.Photo.ReceiptDate);
        Assert.False(card.DateInvalid);
    }

    [Fact]
    public void EscapeBringsBackAnEarlierTypedDate()
    {
        var card = Card();
        card.DateText = "2026-04-01";

        card.BeginDateEdit();
        card.DateText = "2026-04-0";
        card.RevertDateText();

        Assert.Equal("2026-04-01", card.DateText);
    }

    [Fact]
    public void EachReadGetsItsOwnGeneration()
    {
        var card = Card();
        card.BeginReading();
        int first = card.ReadGeneration;
        card.BeginReading();

        Assert.NotEqual(first, card.ReadGeneration);
    }
}
