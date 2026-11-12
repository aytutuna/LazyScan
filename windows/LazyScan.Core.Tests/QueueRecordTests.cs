using LazyScan.Core;
using Xunit;

namespace LazyScan.Core.Tests;

public sealed class QueueRecordTests : IDisposable
{
    private readonly string _spool;

    public QueueRecordTests()
    {
        _spool = Path.Combine(Path.GetTempPath(), "LazyScanTests-" + Guid.NewGuid().ToString("N"));
        Directory.CreateDirectory(_spool);
    }

    public void Dispose()
    {
        try
        {
            Directory.Delete(_spool, recursive: true);
        }
        catch (IOException)
        {
        }
    }

    private ScannedPage Spooled(Guid? id = null, string? alternate = null)
    {
        var page = new ScannedPage(RgbaImage.Filled(4, 4, 128, 128, 128), 200, ColorMode.Grayscale, id,
                                   filePath: Path.Combine(_spool, $"{id ?? Guid.NewGuid()}.png"),
                                   fullPixelSize: new SizeD(40, 40));
        File.WriteAllBytes(page.FilePath!, [1]);
        if (alternate is not null)
        {
            string other = Path.Combine(_spool, alternate);
            File.WriteAllBytes(other, [1]);
            page = page.WithAlternate(new PageVersion(null, other, new SizeD(50, 60)));
        }
        return page;
    }

    [Fact]
    public void WriteThenRead_KeepsWhatTheQueueKnowsAboutEachPage()
    {
        var first = Spooled(alternate: "first-other.png").WithSide(PageSide.Back, 2)
            .WithInclusion(PageInclusion.Skip).WithDocumentLabel("Taxes");
        first.RotationQuarterTurns = 3;
        var second = Spooled().WithBlank(new BlankPageResult(0.01, 2, false, true))
            .WithBarcodes([new BarcodeReading(BarcodeSymbology.QrCode, "split", new RectD(1, 2, 3, 4))])
            .WithDocumentBreak(DocumentBreak.Split);

        QueueRecord.Write([first, second], _spool);
        var record = QueueRecord.Read(_spool);

        Assert.NotNull(record);
        Assert.Equal(2, record.Queued);
        Assert.Equal(2, record.Pages.Count);
        var a = record.Pages[0];
        Assert.Equal(first.Id, a.Id);
        Assert.Equal(Path.GetFileName(first.FilePath), a.File);
        Assert.Equal("first-other.png", a.AlternateFile);
        Assert.Equal(new SizeD(50, 60), a.AlternatePixelSize);
        Assert.Equal(new SizeD(40, 40), a.FullPixelSize);
        Assert.Equal(200, a.Dpi);
        Assert.Equal(ColorMode.Grayscale, a.ColorMode);
        Assert.Equal(3, a.RotationQuarterTurns);
        Assert.Equal(PageSide.Back, a.Side);
        Assert.Equal(2, a.SheetIndex);
        Assert.Equal(PageInclusion.Skip, a.Inclusion);
        Assert.Equal("Taxes", a.DocumentLabel);
        var b = record.Pages[1];
        Assert.Equal(new BlankPageResult(0.01, 2, false, true), b.Blank);
        Assert.Equal("split", Assert.Single(b.Barcodes!).Text);
        Assert.Equal(DocumentBreak.Split, b.DocumentBreak);
    }

    [Fact]
    public void Of_LeavesOutAPageWithoutAFileInTheSpool()
    {
        var inMemory = new ScannedPage(RgbaImage.Filled(4, 4, 0, 0, 0), 300, ColorMode.Color);
        var elsewhere = new ScannedPage(RgbaImage.Filled(4, 4, 0, 0, 0), 300, ColorMode.Color,
                                        filePath: Path.Combine(Path.GetTempPath(), "other.png"));
        var kept = Spooled();

        var record = QueueRecord.Of([inMemory, kept, elsewhere], _spool);

        Assert.Equal(kept.Id, Assert.Single(record.Pages).Id);
        Assert.Equal(3, record.Queued);
    }

    [Fact]
    public void Write_RemovesTheRecordWhenNothingIsLeftToKeep()
    {
        QueueRecord.Write([Spooled()], _spool);
        Assert.True(File.Exists(Path.Combine(_spool, QueueRecord.FileName)));

        QueueRecord.Write([], _spool);

        Assert.False(File.Exists(Path.Combine(_spool, QueueRecord.FileName)));
    }

    [Fact]
    public void Read_LeavesOutAPageWhoseFileIsGone()
    {
        var gone = Spooled();
        var stays = Spooled();
        QueueRecord.Write([gone, stays], _spool);
        File.Delete(gone.FilePath!);

        var record = QueueRecord.Read(_spool);

        Assert.Equal(stays.Id, Assert.Single(record!.Pages).Id);
        Assert.Equal(2, record.Queued);
    }

    [Fact]
    public void Read_DecodesEachPageOnItsOwn()
    {
        var good = Spooled();
        File.WriteAllText(Path.Combine(_spool, QueueRecord.FileName), $$"""
            {"queued": 3, "pages": [
              {"id": "{{good.Id}}", "file": "{{Path.GetFileName(good.FilePath)}}", "dpi": "many", "side": "sideways",
               "rotationQuarterTurns": 1, "somethingNew": true},
              "not a page",
              {"id": 7, "file": "x.png"}
            ]}
            """);

        var record = QueueRecord.Read(_spool);

        var page = Assert.Single(record!.Pages);
        Assert.Equal(good.Id, page.Id);
        Assert.Equal(300, page.Dpi);
        Assert.Null(page.Side);
        Assert.Equal(1, page.RotationQuarterTurns);
        Assert.Equal(3, record.Queued);
    }

    [Fact]
    public void Read_RefusesAFileNameThatLeavesTheSpool()
    {
        string outside = Path.Combine(Path.GetDirectoryName(_spool)!, "outside-" + Guid.NewGuid().ToString("N"));
        File.WriteAllBytes(outside, [1]);
        try
        {
            File.WriteAllText(Path.Combine(_spool, QueueRecord.FileName), $$"""
                {"pages": [{"id": "{{Guid.NewGuid()}}", "file": "..\{{Path.GetFileName(outside)}}"}]}
                """);

            Assert.Null(QueueRecord.Read(_spool));
        }
        finally
        {
            File.Delete(outside);
        }
    }

    [Theory]
    [InlineData("not json")]
    [InlineData("[]")]
    [InlineData("{\"pages\": 4}")]
    public void Read_ReturnsNullForAFileItCannotUse(string text)
    {
        File.WriteAllText(Path.Combine(_spool, QueueRecord.FileName), text);

        Assert.Null(QueueRecord.Read(_spool));
    }

    [Fact]
    public void Read_ReturnsNullWithoutARecord() => Assert.Null(QueueRecord.Read(_spool));

    [Fact]
    public void WriteThenRead_KeepsACameraPagesFacts()
    {
        var quad = new Quad(new PointD(1, 2), new PointD(30, 2), new PointD(30, 40), new PointD(1, 40));
        var page = Spooled();
        var camera = new ScannedPage(page.Image, 300, ColorMode.Color, page.Id, page.CreatedAt, page.FilePath, page.FullPixelSize)
        {
            Geometry = new PageGeometry(true, 1.5, GeometryBasis.PageEdges),
            Patch = PatchCode.Patch4,
            Source = PageSource.Photo,
            Capture = new CaptureFacts(quad, 4000, 3000) { Kind = CaptureKind.Document, FocalLength = 3200 },
            Upright = new UprightTurn(1, true),
        };

        QueueRecord.Write([camera], _spool);
        var read = Assert.Single(QueueRecord.Read(_spool)!.Pages);

        Assert.Equal(PageSource.Photo, read.Source);
        Assert.Equal(PatchCode.Patch4, read.Patch);
        Assert.Equal(new PageGeometry(true, 1.5, GeometryBasis.PageEdges), read.Geometry);
        Assert.Equal(quad, read.Capture!.Quad);
        Assert.Equal(3200, read.Capture.FocalLength);
        Assert.Equal(new UprightTurn(1, true), read.Upright);
    }
}
