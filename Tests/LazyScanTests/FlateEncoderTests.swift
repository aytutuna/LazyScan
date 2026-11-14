import XCTest
import Foundation
@testable import LazyScanKit

// Mirrors windows/LazyScan.Core.Tests/FlateEncoderTests.cs: the same cases and the same pinned
// bytes (length and SHA-256, pinned in C#). The streams are inflated with Foundation's raw deflate
// between the zlib header and the Adler-32, where C# uses ZLibStream.

final class FlateEncoderTests: XCTestCase {
    /// Content-stream-like text: short lines that repeat in shape, as a page's text layer does.
    private static func lines(_ count: Int) -> [UInt8] {
        var text = ""
        for i in 0..<count {
            let hex = String(i * 40503 % 65536, radix: 16, uppercase: true)
            let code = String(repeating: "0", count: 4 - hex.count) + hex
            text += "/F1 12 Tf\n1 0 0 1 \(i * 7 % 600) \(i * 13 % 790) Tm\n<\(code)> Tj\n"
        }
        return Array(text.utf8)
    }

    /// Bytes of a linear congruential generator: nothing to match, every value possible.
    private static func noise(_ count: Int) -> [UInt8] {
        var data = [UInt8](repeating: 0, count: count)
        var x: UInt32 = 12345
        for i in 0..<count {
            x = x &* 1103515245 &+ 12345
            data[i] = UInt8(truncatingIfNeeded: x >> 16)
        }
        return data
    }

    private static func sha256(_ bytes: [UInt8]) -> String {
        CompanionPackage.sha256Hex(Data(bytes)).uppercased()
    }

    func test_roundTrip_throughFoundationsInflater() {
        var both = Self.noise(40_000)
        both.append(contentsOf: Self.noise(40_000))
        var counting = [UInt8]()
        for i in 0..<256 { counting.append(UInt8(i)) }
        for i in 0..<256 { counting.append(UInt8(255 - i)) }
        let samples: [[UInt8]] = [
            [0x41],
            Array("abcabcabcabcabcabcabcabc".utf8),
            [UInt8](repeating: 0, count: 1000),
            counting,
            Self.lines(3000),
            Self.noise(100_000),
            both,
        ]
        for data in samples {
            XCTAssertEqual(PDFFixture.inflate(FlateEncoder.zlib(data)), data)
        }
    }

    func test_header_andAdler32() {
        let data = Self.lines(10)
        let zlib = FlateEncoder.zlib(data)
        XCTAssertEqual(zlib[0], 0x78)
        XCTAssertEqual(zlib[1], 0x01)
        let n = zlib.count
        let adler = (UInt32(zlib[n - 4]) << 24) | (UInt32(zlib[n - 3]) << 16) | (UInt32(zlib[n - 2]) << 8) | UInt32(zlib[n - 1])
        XCTAssertEqual(GlyphlessFont.adler32(data), adler)
    }

    func test_repeatedText_getsMuchSmaller() {
        let data = Self.lines(3000)
        XCTAssertLessThan(FlateEncoder.zlib(data).count, data.count / 3)
    }

    func test_sameInput_sameBytes_pinnedAcrossPlatforms() {
        let zlib = FlateEncoder.zlib(Self.lines(3000))
        XCTAssertEqual(zlib, FlateEncoder.zlib(Self.lines(3000)))
        XCTAssertEqual(zlib.count, 38427)
        XCTAssertEqual(Self.sha256(zlib), "7ECC0A60EB606EE8DF5CCACE66B4353CC1EB292E9E4A1ADFC61E263D4312E886")
        let noise = FlateEncoder.zlib(Self.noise(100_000))
        XCTAssertEqual(noise.count, 105451)
        XCTAssertEqual(Self.sha256(noise), "7B161A57EA4234BDE7AD33F2AFBC27D48D071A31F312B85597488E7987DED153")
    }
}
