using System.IO;
using System.Windows.Media;
using System.Windows.Media.Imaging;
using LazyScan.App.Services;
using Xunit;

namespace LazyScan.App.Tests;

// Rotating a file in the Saved tab turns the pixels and keeps the rest of the file's metadata.
public class SavedFileRotateTests : IDisposable
{
    private readonly string _folder = Directory.CreateTempSubdirectory("LazyScan-rotate-tests-").FullName;

    public void Dispose()
    {
        try { Directory.Delete(_folder, recursive: true); }
        catch (IOException) { }
    }

    private static BitmapSource Picture(int width, int height)
    {
        var bgra = new byte[width * height * 4];
        for (int i = 0; i < bgra.Length; i += 4)
        {
            bgra[i] = 40;
            bgra[i + 1] = 120;
            bgra[i + 2] = 200;
            bgra[i + 3] = 255;
        }
        var bitmap = BitmapSource.Create(width, height, 72, 72, PixelFormats.Bgra32, null, bgra, width * 4);
        bitmap.Freeze();
        return bitmap;
    }

    private static ColorContext Profile()
    {
        var srgb = new ColorContext(PixelFormats.Bgra32);
        return new ColorContext(srgb.ProfileUri);
    }

    private string Write(string name, BitmapEncoder encoder, BitmapMetadata? metadata, ColorContext? profile)
    {
        var contexts = profile is null ? null : new System.Collections.ObjectModel.ReadOnlyCollection<ColorContext>(new[] { profile });
        encoder.Frames.Add(BitmapFrame.Create(Picture(48, 24), null, metadata, contexts));
        string path = Path.Combine(_folder, name);
        using var stream = File.Create(path);
        encoder.Save(stream);
        return path;
    }

    private static BitmapFrame Read(string path)
    {
        using var stream = File.OpenRead(path);
        return BitmapDecoder.Create(stream, BitmapCreateOptions.PreservePixelFormat, BitmapCacheOption.OnLoad).Frames[0];
    }

    [Fact]
    public async Task Jpeg_KeepsDateLocationAndProfile_AndIsUpright()
    {
        var metadata = new BitmapMetadata("jpg");
        metadata.SetQuery("/app1/ifd/{ushort=274}", (ushort)6);
        metadata.SetQuery("/app1/ifd/exif/{ushort=36867}", "2024:05:06 07:08:09");
        metadata.SetQuery("/app1/ifd/gps/{ushort=1}", "N");
        string path = Write("photo.jpg", new JpegBitmapEncoder { QualityLevel = 90 }, metadata, Profile());

        Assert.Null(await SavedFiles.RotateClockwiseAsync(path));

        var frame = Read(path);
        var after = Assert.IsType<BitmapMetadata>(frame.Metadata);
        Assert.Equal("2024:05:06 07:08:09", after.GetQuery("/app1/ifd/exif/{ushort=36867}"));
        Assert.Equal("N", after.GetQuery("/app1/ifd/gps/{ushort=1}"));
        Assert.Equal((ushort)1, after.GetQuery("/app1/ifd/{ushort=274}"));
        Assert.NotEmpty(frame.ColorContexts);
        // Stored 48x24, turned by the tag and then a quarter turn more: 48x24 again.
        Assert.Equal((48, 24), (frame.PixelWidth, frame.PixelHeight));
    }

    [Fact]
    public async Task Tiff_KeepsItsTagsAndProfile()
    {
        var metadata = new BitmapMetadata("tiff");
        metadata.SetQuery("/ifd/{ushort=306}", "2024:05:06 07:08:09");
        string path = Write("scan.tif", new TiffBitmapEncoder { Compression = TiffCompressOption.Lzw }, metadata, Profile());

        Assert.Null(await SavedFiles.RotateClockwiseAsync(path));

        var frame = Read(path);
        var after = Assert.IsType<BitmapMetadata>(frame.Metadata);
        Assert.Equal("2024:05:06 07:08:09", after.GetQuery("/ifd/{ushort=306}"));
        Assert.NotEmpty(frame.ColorContexts);
        Assert.Equal((24, 48), (frame.PixelWidth, frame.PixelHeight));
    }

    [Fact]
    public async Task Png_KeepsItsText()
    {
        var metadata = new BitmapMetadata("png");
        metadata.SetQuery("/tEXt/Title", "Receipt");
        string path = Write("receipt.png", new PngBitmapEncoder(), metadata, null);

        Assert.Null(await SavedFiles.RotateClockwiseAsync(path));

        var frame = Read(path);
        var after = Assert.IsType<BitmapMetadata>(frame.Metadata);
        Assert.Equal("Receipt", after.GetQuery("/tEXt/Title"));
        Assert.Equal((24, 48), (frame.PixelWidth, frame.PixelHeight));
    }
}
