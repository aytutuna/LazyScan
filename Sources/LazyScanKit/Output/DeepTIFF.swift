import Foundation

// Twin of windows/LazyScan.Core/DeepTiff.cs: the same file, byte for byte (the golden value in
// DeepTIFFTests, pinned in C#). See CONTRACTS.md, "16-bit TIFF".

/// A page at 16 bits per sample as a scanner delivers it: `channels` is 1 (gray) or 3 (red, green, blue),
/// `samples` holds `width * height * channels` values, row by row, a pixel's channels together.
public struct DeepPixels: Equatable, Sendable {
    public let width: Int
    public let height: Int
    public let channels: Int
    public let samples: [UInt16]

    public init(width: Int, height: Int, channels: Int, samples: [UInt16]) {
        precondition(width > 0 && height > 0, "Image dimensions must be positive.")
        precondition(channels == 1 || channels == 3, "A page is gray or red, green and blue.")
        precondition(samples.count == width * height * channels, "The samples must fill the page.")
        self.width = width
        self.height = height
        self.channels = channels
        self.samples = samples
    }
}

/// One-page TIFF files at 16 bits per sample, uncompressed: little-endian, the strip first, then the image
/// file directory (BlackIsZero for gray, RGB for three channels), the resolution in pixels per inch.
public enum DeepTIFF {
    /// Whether a page saved as `format` is written here when it has deep pixels: single-page TIFFs.
    public static func applies(_ format: OutputFormat) -> Bool {
        format == .tiff
    }

    /// The file. `details` adds ImageDescription and an Exif directory with DateTimeOriginal to the
    /// directory, each only when it has a value.
    public static func make(_ pixels: DeepPixels, dpi: Int, details: PhotoDetails = .none) -> Data {
        var output: [UInt8] = []
        output.reserveCapacity(pixels.samples.count * 2 + 512)
        output.append(contentsOf: [0x49, 0x49, 0x2A, 0x00])
        let stripLength = pixels.samples.count * 2
        appendUInt32(&output, 8 + stripLength) // the directory comes after the strip, which is word aligned
        for sample in pixels.samples {
            output.append(UInt8(truncatingIfNeeded: sample))
            output.append(UInt8(truncatingIfNeeded: sample >> 8))
        }

        // Zero-terminated, and at least 5 bytes so that the value is an offset, not stored in the entry.
        let caption = details.exifCaption.map { Array($0.utf8) + [UInt8](repeating: 0, count: max(1, 5 - $0.utf8.count)) }
        let date = details.exifDate.map { Array($0.utf8) + [0] }
        let color = pixels.channels == 3

        var entries: [Entry] = []
        entries.append(Entry(tag: 256, type: long, count: 1, value: pixels.width))        // ImageWidth
        entries.append(Entry(tag: 257, type: long, count: 1, value: pixels.height))       // ImageLength
        entries.append(Entry(tag: 258, type: short, count: pixels.channels, value: 16))   // BitsPerSample (offset after the directory for three)
        entries.append(Entry(tag: 259, type: short, count: 1, value: 1))                  // Compression: none
        entries.append(Entry(tag: 262, type: short, count: 1, value: color ? 2 : 1))      // PhotometricInterpretation: RGB or BlackIsZero
        if let caption { entries.append(Entry(tag: 270, type: ascii, count: caption.count, value: 0)) } // ImageDescription (offset after the directory)
        entries.append(Entry(tag: 273, type: long, count: 1, value: 8))                   // StripOffsets
        entries.append(Entry(tag: 277, type: short, count: 1, value: pixels.channels))    // SamplesPerPixel
        entries.append(Entry(tag: 278, type: long, count: 1, value: pixels.height))       // RowsPerStrip: one strip
        entries.append(Entry(tag: 279, type: long, count: 1, value: stripLength))         // StripByteCounts
        entries.append(Entry(tag: 282, type: rational, count: 1, value: 0))               // XResolution (value after the directory)
        entries.append(Entry(tag: 283, type: rational, count: 1, value: 0))               // YResolution
        entries.append(Entry(tag: 296, type: short, count: 1, value: 2))                  // ResolutionUnit: inch
        if date != nil { entries.append(Entry(tag: 34665, type: long, count: 1, value: 0)) } // Exif directory (offset after the directory)

        let directory = output.count
        let resolution = directory + 2 + entries.count * 12 + 4 // two rationals after the directory
        let bitsOffset = resolution + 16
        // Then the description (padded to a word), the date and a one-entry Exif directory.
        let descriptionOffset = bitsOffset + (color ? 6 : 0)
        let dateOffset = descriptionOffset + ((caption?.count ?? 0) + 1) / 2 * 2
        let exifOffset = dateOffset + 20
        appendUInt16(&output, entries.count)
        for entry in entries {
            appendUInt16(&output, entry.tag)
            appendUInt16(&output, entry.type)
            appendUInt32(&output, entry.count)
            var value = entry.value
            if entry.type == rational { value = resolution + (entry.tag == 282 ? 0 : 8) }
            if entry.tag == 258 && color { value = bitsOffset }
            if entry.tag == 270 { value = descriptionOffset }
            if entry.tag == 34665 { value = exifOffset }
            if entry.type == short && entry.count == 1 {
                appendUInt16(&output, value)
                appendUInt16(&output, 0)
            } else {
                appendUInt32(&output, value) // a long, three shorts, an offset
            }
        }
        appendUInt32(&output, 0) // no next directory
        let ppi = max(dpi, 1)
        appendUInt32(&output, ppi)
        appendUInt32(&output, 1)
        appendUInt32(&output, ppi)
        appendUInt32(&output, 1)
        if color { for _ in 0..<3 { appendUInt16(&output, 16) } }
        if let caption {
            output.append(contentsOf: caption)
            if caption.count % 2 == 1 { output.append(0) }
        }
        if let date {
            output.append(contentsOf: date)
            appendUInt16(&output, 1)
            appendUInt16(&output, 36867) // DateTimeOriginal
            appendUInt16(&output, ascii)
            appendUInt32(&output, date.count)
            appendUInt32(&output, dateOffset)
            appendUInt32(&output, 0)
        }
        return Data(output)
    }

    private static let ascii = 2
    private static let short = 3
    private static let long = 4
    private static let rational = 5

    private struct Entry {
        let tag: Int
        let type: Int
        let count: Int
        let value: Int
    }

    private static func appendUInt16(_ bytes: inout [UInt8], _ value: Int) {
        bytes.append(UInt8(truncatingIfNeeded: value))
        bytes.append(UInt8(truncatingIfNeeded: value >> 8))
    }

    private static func appendUInt32(_ bytes: inout [UInt8], _ value: Int) {
        bytes.append(UInt8(truncatingIfNeeded: value))
        bytes.append(UInt8(truncatingIfNeeded: value >> 8))
        bytes.append(UInt8(truncatingIfNeeded: value >> 16))
        bytes.append(UInt8(truncatingIfNeeded: value >> 24))
    }
}
