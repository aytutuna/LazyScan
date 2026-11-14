import Foundation

// Twin of windows/LazyScan.Core/FlateEncoder.cs: the same matches and the same bits, so a stream
// comes out byte for byte alike on every platform (pinned in FlateEncoderTests on both).

/// A zlib encoder with no compression library behind it: one fixed-Huffman deflate block, its
/// matches by a greedy LZ77 over a 32 KiB window. A table of the last position of each three-byte
/// hash finds the candidate, and a match is taken when it is at least three bytes long. Slower and
/// looser than zlib's, but deterministic, which the PDF writers need more than the last few percent.
enum FlateEncoder {
    private static let hashBits = 15
    private static let window = 32768
    private static let maxMatch = 258

    private static let lengthBase: [Int] = [3, 4, 5, 6, 7, 8, 9, 10, 11, 13, 15, 17, 19, 23, 27, 31, 35, 43, 51, 59,
                                            67, 83, 99, 115, 131, 163, 195, 227, 258]
    private static let lengthExtra: [Int] = [0, 0, 0, 0, 0, 0, 0, 0, 1, 1, 1, 1, 2, 2, 2, 2, 3, 3, 3, 3,
                                             4, 4, 4, 4, 5, 5, 5, 5, 0]
    private static let distanceBase: [Int] = [1, 2, 3, 4, 5, 7, 9, 13, 17, 25, 33, 49, 65, 97, 129, 193, 257, 385,
                                              513, 769, 1025, 1537, 2049, 3073, 4097, 6145, 8193, 12289, 16385, 24577]
    private static let distanceExtra: [Int] = [0, 0, 0, 0, 1, 1, 2, 2, 3, 3, 4, 4, 5, 5, 6, 6, 7, 7,
                                               8, 8, 9, 9, 10, 10, 11, 11, 12, 12, 13, 13]

    /// `data` as a zlib stream (RFC 1950): the header, the deflate block, the Adler-32.
    static func zlib(_ data: [UInt8]) -> [UInt8] {
        var bits = Bits()
        bits.put(1, 1)                // BFINAL
        bits.put(1, 2)                // BTYPE 01: fixed Huffman codes
        let count = data.count
        var head = [Int32](repeating: -1, count: 1 << hashBits)
        var i = 0
        while i < count {
            var length = 0
            var distance = 0
            if i + 3 <= count {
                let h = hash(data, i)
                let candidate = Int(head[h])
                head[h] = Int32(i)
                if candidate >= 0 && i - candidate <= window {
                    let limit = min(maxMatch, count - i)
                    while length < limit && data[candidate + length] == data[i + length] { length += 1 }
                    distance = i - candidate
                }
            }
            if length >= 3 {
                bits.match(length, distance)
                var k = i + 1
                while k < i + length {
                    if k + 3 <= count { head[hash(data, k)] = Int32(k) }
                    k += 1
                }
                i += length
            } else {
                bits.literal(Int(data[i]))
                i += 1
            }
        }
        bits.code(0, 7)               // end of block
        var output: [UInt8] = [0x78, 0x01]
        output.append(contentsOf: bits.finish())
        let adler = GlyphlessFont.adler32(data)
        output.append(UInt8(truncatingIfNeeded: adler >> 24))
        output.append(UInt8(truncatingIfNeeded: adler >> 16))
        output.append(UInt8(truncatingIfNeeded: adler >> 8))
        output.append(UInt8(truncatingIfNeeded: adler))
        return output
    }

    private static func hash(_ data: [UInt8], _ i: Int) -> Int {
        let value = UInt32(data[i]) << 16 | UInt32(data[i + 1]) << 8 | UInt32(data[i + 2])
        return Int((value &* 2654435761) >> UInt32(32 - hashBits))
    }

    /// Deflate's bit order: fields least significant bit first, Huffman codes most significant bit first.
    private struct Bits {
        private var output: [UInt8] = []
        private var buffer: UInt64 = 0
        private var filled = 0

        mutating func put(_ value: Int, _ count: Int) {
            buffer |= UInt64(value) << UInt64(filled)
            filled += count
            while filled >= 8 {
                output.append(UInt8(truncatingIfNeeded: buffer))
                buffer >>= 8
                filled -= 8
            }
        }

        mutating func code(_ code: Int, _ length: Int) {
            var reversed = 0
            for i in 0..<length { reversed |= ((code >> i) & 1) << (length - 1 - i) }
            put(reversed, length)
        }

        mutating func literal(_ value: Int) {
            if value < 144 {
                code(0x30 + value, 8)
            } else {
                code(0x190 + value - 144, 9)
            }
        }

        mutating func match(_ length: Int, _ distance: Int) {
            var symbol = FlateEncoder.lengthBase.count - 1
            while FlateEncoder.lengthBase[symbol] > length { symbol -= 1 }
            if symbol < 23 {
                code(symbol + 1, 7)                   // symbols 257-279: 7-bit codes 1-23
            } else {
                code(0xC0 + symbol - 23, 8)           // symbols 280-285: 8-bit codes 0xC0 +
            }
            put(length - FlateEncoder.lengthBase[symbol], FlateEncoder.lengthExtra[symbol])
            var slot = FlateEncoder.distanceBase.count - 1
            while FlateEncoder.distanceBase[slot] > distance { slot -= 1 }
            code(slot, 5)
            put(distance - FlateEncoder.distanceBase[slot], FlateEncoder.distanceExtra[slot])
        }

        func finish() -> [UInt8] {
            var bytes = output
            if filled > 0 { bytes.append(UInt8(truncatingIfNeeded: buffer)) }
            return bytes
        }
    }
}
