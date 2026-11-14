using System.IO;
using System.Windows.Media.Imaging;
using LazyScan.App.Services;
using LazyScan.Core;
using Xunit;

namespace LazyScan.App.Tests;

// Mirrors Tests/LazyScanTests/PhotoDetailsTests.swift: the date taken and caption in the saved files,
// read back through WIC.
public class PhotoDetailsOutputTests : IDisposable
{
    private readonly string _folder = Directory.CreateTempSubdirectory("LazyScan-photodetails-tests-").FullName;

    public void Dispose()
    {
        try { Directory.Delete(_folder, recursive: true); }
        catch (IOException) { }
    }

    private static RgbaImage Page(byte value) => new(40, 30, Enumerable.Repeat(value, 40 * 30 * 4).ToArray());

    private static (string? Date, string? Caption) Tags(string path, OutputFormat format)
    {
        using var stream = File.OpenRead(path);
        var decoder = BitmapDecoder.Create(stream, BitmapCreateOptions.None, BitmapCacheOption.OnLoad);
        var metadata = (BitmapMetadata)decoder.Frames[0].Metadata;
        if (format == OutputFormat.Png)
        {
            // A lone Creation Time chunk would be the first one; the tests always write both or neither.
            return (metadata.GetQuery("/[1]tEXt/{str=Creation Time}") as string,
                    metadata.GetQuery("/tEXt/{str=Description}") as string);
        }
        string ifd = format == OutputFormat.Jpeg ? "/app1/ifd" : "/ifd";
        return (metadata.GetQuery(ifd + "/exif/{ushort=36867}") as string, metadata.Title);
    }

    [Fact]
    public void SavedImages_CarryTheDateAndCaption_AndNothingWithoutThem()
    {
        var details = new PhotoDetails(Year: 1985, Caption: "Dad at the lake");
        foreach (var (format, ext) in new[] { (OutputFormat.Jpeg, "jpg"), (OutputFormat.Png, "png"), (OutputFormat.Tiff, "tif") })
        {
            string tagged = WpfImageCodec.SaveAsNew(Page(120), Path.Combine(_folder, $"tagged.{ext}"), format, 300, 0.9,
                                                    details: details);
            Assert.Equal(("1985:01:01 00:00:00", "Dad at the lake"), Tags(tagged, format));

            string plain = WpfImageCodec.SaveAsNew(Page(120), Path.Combine(_folder, $"plain.{ext}"), format, 300, 0.9);
            Assert.Equal((null, null), Tags(plain, format));
        }
    }

    [Fact]
    public void BlackAndWhiteTiff_CarriesTheDateAndCaption()
    {
        var details = new PhotoDetails(1985, 7, 23, "A");
        string path = WpfImageCodec.SaveAsNew(Page(0), Path.Combine(_folder, "bw.tif"), OutputFormat.Tiff, 300, 0.9,
                                              ColorMode.BlackWhite, details);
        Assert.Equal(("1985:07:23 00:00:00", "A"), Tags(path, OutputFormat.Tiff));
        Assert.Equal(BilevelTiff.Make(Page(0), 300, details), File.ReadAllBytes(path));
    }

    [Fact]
    public void BlackAndWhiteTiff_WithoutDetails_IsTheSameFileAsBefore()
    {
        Assert.Equal(BilevelTiff.Make(Page(0), 300), BilevelTiff.Make(Page(0), 300, new PhotoDetails()));
    }
}
