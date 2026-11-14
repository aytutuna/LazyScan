using System.IO.Compression;
using System.Security.Cryptography;
using System.Text;
using LazyScan.Core;
using Xunit;

namespace LazyScan.Core.Tests;

// The PDF writers' own zlib encoder. The Mac's twin (FlateEncoderTests.swift) has the same cases
// and checks the same bytes (the pinned length and SHA-256 below).

public class FlateEncoderTests
{
    private static byte[] Inflate(byte[] zlib)
    {
        using var input = new ZLibStream(new MemoryStream(zlib), CompressionMode.Decompress);
        using var output = new MemoryStream();
        input.CopyTo(output);
        return output.ToArray();
    }

    /// <summary>Content-stream-like text: short lines that repeat in shape, as a page's text layer does.</summary>
    private static byte[] Lines(int count)
    {
        var sb = new StringBuilder();
        for (int i = 0; i < count; i++) sb.Append($"/F1 12 Tf\n1 0 0 1 {i * 7 % 600} {i * 13 % 790} Tm\n<{i * 40503 % 65536:X4}> Tj\n");
        return Encoding.ASCII.GetBytes(sb.ToString());
    }

    /// <summary>Bytes of a linear congruential generator: nothing to match, every value possible.</summary>
    private static byte[] Noise(int count)
    {
        var data = new byte[count];
        uint x = 12345;
        for (int i = 0; i < count; i++)
        {
            x = unchecked(x * 1103515245 + 12345);
            data[i] = (byte)(x >> 16);
        }
        return data;
    }

    [Fact]
    public void RoundTrip_ThroughThePlatformInflater()
    {
        byte[][] samples =
        [
            [0x41],
            "abcabcabcabcabcabcabcabc"u8.ToArray(),
            new byte[1000],
            [.. Enumerable.Range(0, 256).Select(i => (byte)i), .. Enumerable.Range(0, 256).Select(i => (byte)(255 - i))],
            Lines(3000),
            Noise(100_000),
            [.. Noise(40_000), .. Noise(40_000)],
        ];
        foreach (byte[] data in samples) Assert.Equal(data, Inflate(FlateEncoder.Zlib(data)));
    }

    [Fact]
    public void Header_AndAdler32()
    {
        byte[] data = Lines(10);
        byte[] zlib = FlateEncoder.Zlib(data);
        Assert.Equal((0x78, 0x01), (zlib[0], zlib[1]));
        Assert.Equal(GlyphlessFont.Adler32(data), (uint)((zlib[^4] << 24) | (zlib[^3] << 16) | (zlib[^2] << 8) | zlib[^1]));
    }

    [Fact]
    public void RepeatedText_GetsMuchSmaller()
    {
        byte[] data = Lines(3000);
        Assert.True(FlateEncoder.Zlib(data).Length < data.Length / 3);
    }

    [Fact]
    public void SameInput_SameBytes_PinnedAcrossPlatforms()
    {
        byte[] zlib = FlateEncoder.Zlib(Lines(3000));
        Assert.Equal(zlib, FlateEncoder.Zlib(Lines(3000)));
        Assert.Equal(38427, zlib.Length);
        Assert.Equal("7ECC0A60EB606EE8DF5CCACE66B4353CC1EB292E9E4A1ADFC61E263D4312E886", Convert.ToHexString(SHA256.HashData(zlib)));
        byte[] noise = FlateEncoder.Zlib(Noise(100_000));
        Assert.Equal(105451, noise.Length);
        Assert.Equal("7B161A57EA4234BDE7AD33F2AFBC27D48D071A31F312B85597488E7987DED153", Convert.ToHexString(SHA256.HashData(noise)));
    }
}
