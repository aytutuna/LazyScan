namespace LazyScan.Core;

// Twin of Sources/LazyScanKit/Output/FlateEncoder.swift: the same matches and the same bits, so a
// stream comes out byte for byte alike on every platform (pinned in FlateEncoderTests on both).

/// <summary>
/// A zlib encoder with no compression library behind it: one fixed-Huffman deflate block, its
/// matches by a greedy LZ77 over a 32 KiB window. A table of the last position of each three-byte
/// hash finds the candidate, and a match is taken when it is at least three bytes long. Slower and
/// looser than zlib's, but deterministic, which the PDF writers need more than the last few percent.
/// </summary>
internal static class FlateEncoder
{
    private const int HashBits = 15;
    private const int Window = 32768;
    private const int MaxMatch = 258;

    private static readonly int[] LengthBase = [3, 4, 5, 6, 7, 8, 9, 10, 11, 13, 15, 17, 19, 23, 27, 31, 35, 43, 51, 59,
                                                67, 83, 99, 115, 131, 163, 195, 227, 258];
    private static readonly int[] LengthExtra = [0, 0, 0, 0, 0, 0, 0, 0, 1, 1, 1, 1, 2, 2, 2, 2, 3, 3, 3, 3,
                                                 4, 4, 4, 4, 5, 5, 5, 5, 0];
    private static readonly int[] DistanceBase = [1, 2, 3, 4, 5, 7, 9, 13, 17, 25, 33, 49, 65, 97, 129, 193, 257, 385,
                                                  513, 769, 1025, 1537, 2049, 3073, 4097, 6145, 8193, 12289, 16385, 24577];
    private static readonly int[] DistanceExtra = [0, 0, 0, 0, 1, 1, 2, 2, 3, 3, 4, 4, 5, 5, 6, 6, 7, 7,
                                                   8, 8, 9, 9, 10, 10, 11, 11, 12, 12, 13, 13];

    /// <summary><paramref name="data"/> as a zlib stream (RFC 1950): the header, the deflate block, the Adler-32.</summary>
    internal static byte[] Zlib(ReadOnlySpan<byte> data)
    {
        var bits = new Bits();
        bits.Put(1, 1);                   // BFINAL
        bits.Put(1, 2);                   // BTYPE 01: fixed Huffman codes
        int count = data.Length;
        var head = new int[1 << HashBits];
        Array.Fill(head, -1);
        int i = 0;
        while (i < count)
        {
            int length = 0, distance = 0;
            if (i + 3 <= count)
            {
                int h = Hash(data, i);
                int candidate = head[h];
                head[h] = i;
                if (candidate >= 0 && i - candidate <= Window)
                {
                    int limit = Math.Min(MaxMatch, count - i);
                    while (length < limit && data[candidate + length] == data[i + length]) length++;
                    distance = i - candidate;
                }
            }
            if (length >= 3)
            {
                bits.Match(length, distance);
                for (int k = i + 1; k < i + length; k++)
                {
                    if (k + 3 <= count) head[Hash(data, k)] = k;
                }
                i += length;
            }
            else
            {
                bits.Literal(data[i]);
                i++;
            }
        }
        bits.Code(0, 7);                  // end of block
        var output = new List<byte> { 0x78, 0x01 };
        output.AddRange(bits.ToArray());
        uint adler = GlyphlessFont.Adler32(data);
        output.AddRange([(byte)(adler >> 24), (byte)(adler >> 16), (byte)(adler >> 8), (byte)adler]);
        return [.. output];
    }

    private static int Hash(ReadOnlySpan<byte> data, int i)
    {
        uint value = (uint)(data[i] << 16 | data[i + 1] << 8 | data[i + 2]);
        return (int)(unchecked(value * 2654435761u) >> (32 - HashBits));
    }

    /// <summary>Deflate's bit order: fields least significant bit first, Huffman codes most significant bit first.</summary>
    private sealed class Bits
    {
        private readonly List<byte> _bytes = [];
        private ulong _buffer;
        private int _filled;

        public void Put(int value, int count)
        {
            _buffer |= (ulong)value << _filled;
            _filled += count;
            while (_filled >= 8)
            {
                _bytes.Add((byte)_buffer);
                _buffer >>= 8;
                _filled -= 8;
            }
        }

        public void Code(int code, int length)
        {
            int reversed = 0;
            for (int i = 0; i < length; i++) reversed |= ((code >> i) & 1) << (length - 1 - i);
            Put(reversed, length);
        }

        public void Literal(int value)
        {
            if (value < 144) Code(0x30 + value, 8);
            else Code(0x190 + value - 144, 9);
        }

        public void Match(int length, int distance)
        {
            int symbol = LengthBase.Length - 1;
            while (LengthBase[symbol] > length) symbol--;
            if (symbol < 23) Code(symbol + 1, 7);               // symbols 257-279: 7-bit codes 1-23
            else Code(0xC0 + symbol - 23, 8);                   // symbols 280-285: 8-bit codes 0xC0 +
            Put(length - LengthBase[symbol], LengthExtra[symbol]);
            int slot = DistanceBase.Length - 1;
            while (DistanceBase[slot] > distance) slot--;
            Code(slot, 5);
            Put(distance - DistanceBase[slot], DistanceExtra[slot]);
        }

        public byte[] ToArray()
        {
            var bytes = new List<byte>(_bytes);
            if (_filled > 0) bytes.Add((byte)_buffer);
            return [.. bytes];
        }
    }
}
