using System.Buffers.Binary;

namespace LazyScan.Core;

// The Mac's twin is Sources/LazyScanKit/Output/DeepTIFF.swift, which writes the same bytes
//.

/// <summary>
/// A page at 16 bits per sample as a scanner delivers it: <see cref="Channels"/> is 1 (gray) or 3 (red,
/// green, blue), <see cref="Samples"/> holds <c>Width * Height * Channels</c> values, row by row, a
/// pixel's channels together.
/// </summary>
public sealed class DeepPixels
{
    public int Width { get; }
    public int Height { get; }
    public int Channels { get; }
    public ushort[] Samples { get; }

    public DeepPixels(int width, int height, int channels, ushort[] samples)
    {
        if (width <= 0 || height <= 0)
            throw new ArgumentOutOfRangeException(nameof(width), "Image dimensions must be positive.");
        if (channels is not (1 or 3))
            throw new ArgumentOutOfRangeException(nameof(channels), "A page is gray or red, green and blue.");
        if (samples.LongLength != (long)width * height * channels)
            throw new ArgumentException("The samples must fill the page.", nameof(samples));
        Width = width;
        Height = height;
        Channels = channels;
        Samples = samples;
    }

    /// <summary>The part inside <paramref name="rect"/> (pixels, top-left origin, clipped to the page); null when nothing is left.</summary>
    public DeepPixels? Cropped(RectD rect)
    {
        var r = rect.Standardized.Integral.Intersection(new RectD(0, 0, Width, Height));
        int left = (int)r.MinX, top = (int)r.MinY, w = (int)r.Width, h = (int)r.Height;
        if (w < 1 || h < 1) return null;
        var part = new ushort[w * h * Channels];
        for (int row = 0; row < h; row++)
            Array.Copy(Samples, ((top + row) * Width + left) * Channels, part, row * w * Channels, w * Channels);
        return new DeepPixels(w, h, Channels, part);
    }

    /// <summary>Turned clockwise by <paramref name="quarterTurns"/> steps of 90 degrees, like <see cref="ImagePipeline.Rotate"/>.</summary>
    public DeepPixels Rotated(int quarterTurns)
    {
        int turns = ((quarterTurns % 4) + 4) % 4;
        if (turns == 0) return this;
        int newWidth = turns == 2 ? Width : Height, newHeight = turns == 2 ? Height : Width;
        var turned = new ushort[Samples.Length];
        for (int y = 0; y < newHeight; y++)
        {
            for (int x = 0; x < newWidth; x++)
            {
                (int sourceX, int sourceY) = turns switch
                {
                    1 => (y, Height - 1 - x),
                    2 => (Width - 1 - x, Height - 1 - y),
                    _ => (Width - 1 - y, x),
                };
                Array.Copy(Samples, (sourceY * Width + sourceX) * Channels, turned, (y * newWidth + x) * Channels, Channels);
            }
        }
        return new DeepPixels(newWidth, newHeight, Channels, turned);
    }
}

/// <summary>
/// One-page TIFF files at 16 bits per sample, uncompressed: little-endian, the strip first, then the
/// image file directory (BlackIsZero for gray, RGB for three channels), the resolution in pixels per inch.
/// </summary>
public static class DeepTiff
{
    /// <summary>Whether a page saved as <paramref name="format"/> is written here when it has deep pixels: single-page TIFFs.</summary>
    public static bool Applies(OutputFormat format) => format == OutputFormat.Tiff;

    /// <summary>
    /// The file. <paramref name="details"/> adds ImageDescription and an Exif directory with DateTimeOriginal
    /// to the directory, each only when it has a value.
    /// </summary>
    public static byte[] Make(DeepPixels pixels, int dpi, PhotoDetails? details = null)
    {
        int stripLength = checked(pixels.Samples.Length * 2);
        using var output = new MemoryStream(stripLength + 512);
        output.Write("II*\0"u8);
        WriteUInt32(output, checked((uint)(8 + stripLength))); // the directory comes after the strip, which is word aligned
        var strip = new byte[stripLength];
        for (int i = 0; i < pixels.Samples.Length; i++)
            BinaryPrimitives.WriteUInt16LittleEndian(strip.AsSpan(i * 2), pixels.Samples[i]);
        output.Write(strip);

        // Zero-terminated, and at least 5 bytes so that the value is an offset, not stored in the entry.
        byte[]? caption = details?.ExifCaption is { } captionText ? Terminated(captionText, 5) : null;
        byte[]? date = details?.ExifDate is { } dateText ? Terminated(dateText, 0) : null;
        bool color = pixels.Channels == 3;

        var entries = new List<(ushort Tag, ushort Type, uint Count, uint Value)>
        {
            (256, Long, 1, (uint)pixels.Width),                          // ImageWidth
            (257, Long, 1, (uint)pixels.Height),                         // ImageLength
            (258, Short, (uint)pixels.Channels, 16),                     // BitsPerSample (offset after the directory for three)
            (259, Short, 1, 1),                                          // Compression: none
            (262, Short, 1, color ? 2u : 1u),                            // PhotometricInterpretation: RGB or BlackIsZero
        };
        if (caption != null) entries.Add((270, Ascii, (uint)caption.Length, 0)); // ImageDescription (offset after the directory)
        entries.Add((273, Long, 1, 8));                                  // StripOffsets
        entries.Add((277, Short, 1, (uint)pixels.Channels));             // SamplesPerPixel
        entries.Add((278, Long, 1, (uint)pixels.Height));                // RowsPerStrip: one strip
        entries.Add((279, Long, 1, (uint)stripLength));                  // StripByteCounts
        entries.Add((282, Rational, 1, 0));                              // XResolution (value after the directory)
        entries.Add((283, Rational, 1, 0));                              // YResolution
        entries.Add((296, Short, 1, 2));                                 // ResolutionUnit: inch
        if (date != null) entries.Add((34665, Long, 1, 0));              // Exif directory (offset after the directory)

        long directory = output.Position;
        long resolution = directory + 2 + entries.Count * 12 + 4; // two rationals after the directory
        long bitsOffset = resolution + 16;
        // Then the description (padded to a word), the date and a one-entry Exif directory.
        long descriptionOffset = bitsOffset + (color ? 6 : 0);
        long dateOffset = descriptionOffset + ((caption?.Length ?? 0) + 1) / 2 * 2;
        long exifOffset = dateOffset + 20;
        WriteUInt16(output, (ushort)entries.Count);
        foreach (var (tag, type, count, entryValue) in entries)
        {
            uint value = entryValue;
            if (type == Rational) value = checked((uint)(resolution + (tag == 282 ? 0 : 8)));
            if (tag == 258 && color) value = checked((uint)bitsOffset);
            if (tag == 270) value = checked((uint)descriptionOffset);
            if (tag == 34665) value = checked((uint)exifOffset);
            WriteUInt16(output, tag);
            WriteUInt16(output, type);
            WriteUInt32(output, count);
            if (type == Short && count == 1)
            {
                WriteUInt16(output, (ushort)value);
                WriteUInt16(output, 0);
            }
            else
            {
                WriteUInt32(output, value); // a long, three shorts, an offset
            }
        }
        WriteUInt32(output, 0); // no next directory
        uint ppi = (uint)Math.Max(dpi, 1);
        WriteUInt32(output, ppi);
        WriteUInt32(output, 1);
        WriteUInt32(output, ppi);
        WriteUInt32(output, 1);
        if (color)
        {
            for (int i = 0; i < 3; i++) WriteUInt16(output, 16);
        }
        if (caption != null)
        {
            output.Write(caption);
            if (caption.Length % 2 == 1) output.WriteByte(0);
        }
        if (date != null)
        {
            output.Write(date);
            WriteUInt16(output, 1);
            WriteUInt16(output, 36867); // DateTimeOriginal
            WriteUInt16(output, Ascii);
            WriteUInt32(output, (uint)date.Length);
            WriteUInt32(output, checked((uint)dateOffset));
            WriteUInt32(output, 0);
        }
        return output.ToArray();
    }

    private static byte[] Terminated(string text, int minLength)
    {
        var bytes = System.Text.Encoding.UTF8.GetBytes(text);
        var result = new byte[Math.Max(bytes.Length + 1, minLength)];
        bytes.CopyTo(result, 0);
        return result;
    }

    private static void WriteUInt16(Stream stream, ushort value)
    {
        Span<byte> bytes = stackalloc byte[2];
        BinaryPrimitives.WriteUInt16LittleEndian(bytes, value);
        stream.Write(bytes);
    }

    private static void WriteUInt32(Stream stream, uint value)
    {
        Span<byte> bytes = stackalloc byte[4];
        BinaryPrimitives.WriteUInt32LittleEndian(bytes, value);
        stream.Write(bytes);
    }

    private const ushort Ascii = 2, Short = 3, Long = 4, Rational = 5;
}
