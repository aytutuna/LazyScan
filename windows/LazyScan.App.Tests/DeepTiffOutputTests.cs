using System.IO;
using System.Windows.Media;
using System.Windows.Media.Imaging;
using LazyScan.App.Services;
using LazyScan.Core;
using Xunit;

namespace LazyScan.App.Tests;

// Mirrors Tests/LazyScanTests/DeepTIFFTests.swift: the 16-bit files read back through WIC, and the
// exporter writing them only for a TIFF.
public class DeepTiffOutputTests : IDisposable
{
    private readonly string _folder = Directory.CreateTempSubdirectory("LazyScan-deeptiff-tests-").FullName;

    public void Dispose()
    {
        try { Directory.Delete(_folder, recursive: true); }
        catch (IOException) { }
    }

    private static BitmapSource Decode(string path)
    {
        using var stream = File.OpenRead(path);
        return BitmapDecoder.Create(stream, BitmapCreateOptions.PreservePixelFormat, BitmapCacheOption.OnLoad).Frames[0];
    }

    private static RgbaImage Page() => new(2, 1, [10, 20, 30, 255, 40, 50, 60, 255]);

    [Fact]
    public void Wic_ReadsAGrayFileAs16BitsPerSample()
    {
        var pixels = new DeepPixels(2, 1, 1, [0, 65535]);
        string path = WpfImageCodec.SaveAsNew(Page(), Path.Combine(_folder, "gray.tif"), OutputFormat.Tiff, 300, 0.9,
                                              ColorMode.Grayscale, null, pixels);
        var frame = Decode(path);
        Assert.Equal(PixelFormats.Gray16, frame.Format);
        var read = new ushort[2];
        frame.CopyPixels(read, 4, 0);
        Assert.Equal(new ushort[] { 0, 65535 }, read);
        Assert.Equal(300, Math.Round(frame.DpiX));
    }

    [Fact]
    public void Wic_ReadsAColorFileAs48BitRgb()
    {
        var pixels = new DeepPixels(2, 1, 3, [65535, 32768, 1, 0, 256, 65534]);
        string path = WpfImageCodec.SaveAsNew(Page(), Path.Combine(_folder, "color.tif"), OutputFormat.Tiff, 600, 0.9,
                                              ColorMode.Color, null, pixels);
        var frame = Decode(path);
        Assert.Equal(PixelFormats.Rgb48, frame.Format);
        var read = new ushort[6];
        frame.CopyPixels(read, 12, 0);
        Assert.Equal(new ushort[] { 65535, 32768, 1, 0, 256, 65534 }, read);
    }

    [Fact]
    public void WithoutDeepPixels_OrForAnotherFormat_TheFileStays8Bit()
    {
        var pixels = new DeepPixels(2, 1, 3, [65535, 32768, 1, 0, 256, 65534]);
        var plain = Decode(WpfImageCodec.SaveAsNew(Page(), Path.Combine(_folder, "plain.tif"), OutputFormat.Tiff, 300, 0.9));
        Assert.Equal(24, plain.Format.BitsPerPixel);
        var png = Decode(WpfImageCodec.SaveAsNew(Page(), Path.Combine(_folder, "deep.png"), OutputFormat.Png, 300, 0.9,
                                                 ColorMode.Color, null, pixels));
        Assert.True(png.Format.BitsPerPixel <= 32);
    }
}
