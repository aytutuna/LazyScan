import Foundation

// Twin of windows/LazyScan.Core/TextSplit.cs: the same threshold, neighbors and rounding, so both
// platforms cut a page into the same bytes.

/// A page cut into a one-bit text mask at the page's own resolution (`Bilevel` layout, 0 = ink) and
/// a low-resolution color background with the ink filled in from the paper around it: the two layers
/// of a mixed-raster PDF page.
public struct TextSplit: Sendable {
    /// The background's resolution in dots per inch.
    public static let backgroundDPI = 100

    /// The ink, packed as `Bilevel`, `width` × `height` pixels.
    public let mask: [UInt8]
    public let width: Int
    public let height: Int
    /// The page without its ink, at about `backgroundDPI`.
    public let background: RgbaImage

    /// Splits `image`, scanned at `dpi`: a pixel is ink where it is below the share of the paper there
    /// that black and white makes black (`DocumentEnhancer.blackShare` at `defaultThreshold`). Each
    /// background pixel is the mean of the pixels it covers that are neither ink nor next to ink (the
    /// soft edge of a glyph); one with none takes the mean of the background pixels around it, pass
    /// after pass.
    public static func split(_ image: RgbaImage, dpi: Int) -> TextSplit {
        let w: Int = image.width
        let h: Int = image.height
        let gray: GrayImage = GrayImage.luma(image)
        let paper: BackgroundMap? = DocumentEnhancer.paperMap(gray)
        let share: Double = DocumentEnhancer.blackShare(threshold: DocumentEnhancer.defaultThreshold)
        let blackBelow: Int = Int(floor(share * Double(DocumentEnhancer.levels) + 0.5))
        let stride: Int = Bilevel.stride(w)
        var mask: [UInt8] = [UInt8](repeating: 0xFF, count: stride * h)
        var ink: [Bool] = [Bool](repeating: false, count: w * h)
        if let paper = paper {
            for y in 0..<h {
                for x in 0..<w {
                    let level: Int = DocumentEnhancer.level(Double(gray.pixels[y * w + x]), paper.valueAt(x: x, y: y))
                    if level >= blackBelow { continue }
                    ink[y * w + x] = true
                    mask[y * stride + (x >> 3)] &= ~UInt8(0x80 >> (x & 7))
                }
            }
        }

        let bw: Int = min(max((w * backgroundDPI + dpi / 2) / dpi, 1), w)
        let bh: Int = min(max((h * backgroundDPI + dpi / 2) / dpi, 1), h)
        var values: [Int] = [Int](repeating: 0, count: bw * bh * 3)
        var counts: [Int] = [Int](repeating: 0, count: bw * bh)
        let src: [UInt8] = image.pixels
        for by in 0..<bh {
            let y0: Int = by * h / bh
            let y1: Int = max(y0 + 1, (by + 1) * h / bh)
            for bx in 0..<bw {
                let x0: Int = bx * w / bw
                let x1: Int = max(x0 + 1, (bx + 1) * w / bw)
                var r: Int = 0, g: Int = 0, b: Int = 0, n: Int = 0
                for y in y0..<y1 {
                    for x in x0..<x1 {
                        if nearInk(ink, w, h, x, y) { continue }
                        let i: Int = (y * w + x) * 4
                        r += Int(src[i])
                        g += Int(src[i + 1])
                        b += Int(src[i + 2])
                        n += 1
                    }
                }
                let o: Int = by * bw + bx
                counts[o] = n
                if n == 0 { continue }
                values[o * 3] = r / n
                values[o * 3 + 1] = g / n
                values[o * 3 + 2] = b / n
            }
        }
        fillEmpty(&values, counts, bw, bh)

        var pixels: [UInt8] = [UInt8](repeating: 255, count: bw * bh * 4)
        for p in 0..<(bw * bh) {
            pixels[p * 4] = UInt8(values[p * 3])
            pixels[p * 4 + 1] = UInt8(values[p * 3 + 1])
            pixels[p * 4 + 2] = UInt8(values[p * 3 + 2])
        }
        return TextSplit(mask: mask, width: w, height: h,
                         background: RgbaImage(width: bw, height: bh, pixels: pixels))
    }

    private static func nearInk(_ ink: [Bool], _ w: Int, _ h: Int, _ x: Int, _ y: Int) -> Bool {
        for ny in max(0, y - 1)...min(h - 1, y + 1) {
            for nx in max(0, x - 1)...min(w - 1, x + 1) where ink[ny * w + nx] {
                return true
            }
        }
        return false
    }

    /// Gives each pixel with no count the mean of the counted ones among its eight neighbors, until all
    /// have a value (white when none has).
    private static func fillEmpty(_ values: inout [Int], _ counts: [Int], _ w: Int, _ h: Int) {
        var known: [Bool] = counts.map { $0 > 0 }
        var missing: Int = known.filter { !$0 }.count
        if missing == known.count {
            values = [Int](repeating: 255, count: values.count)
            return
        }
        while missing > 0 {
            var found: [Int] = []
            for y in 0..<h {
                for x in 0..<w {
                    let p: Int = y * w + x
                    if known[p] { continue }
                    var r: Int = 0, g: Int = 0, b: Int = 0, n: Int = 0
                    for ny in max(0, y - 1)...min(h - 1, y + 1) {
                        for nx in max(0, x - 1)...min(w - 1, x + 1) {
                            let q: Int = ny * w + nx
                            if !known[q] { continue }
                            r += values[q * 3]
                            g += values[q * 3 + 1]
                            b += values[q * 3 + 2]
                            n += 1
                        }
                    }
                    if n == 0 { continue }
                    values[p * 3] = r / n
                    values[p * 3 + 1] = g / n
                    values[p * 3 + 2] = b / n
                    found.append(p)
                }
            }
            for p in found { known[p] = true }
            missing -= found.count
        }
    }
}
