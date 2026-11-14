using System.Windows.Media;
using System.Windows.Media.Imaging;
using LazyScan.App.Services;
using Xunit;

namespace LazyScan.App.Tests;

public class TransparentImportTests
{
    [Fact]
    public void TransparentPixelsBlendOverWhite()
    {
        // BGRA: transparent black, half-transparent black, opaque red.
        byte[] bgra = [0, 0, 0, 0, 0, 0, 0, 128, 0, 0, 255, 255];
        var source = BitmapSource.Create(3, 1, 96, 96, PixelFormats.Bgra32, null, bgra, 12);

        var image = WpfImageCodec.FromBitmapSource(source);

        Assert.Equal([255, 255, 255, 255], image.Pixels[0..4]);
        Assert.Equal([127, 127, 127, 255], image.Pixels[4..8]);
        Assert.Equal([255, 0, 0, 255], image.Pixels[8..12]);
    }
}
