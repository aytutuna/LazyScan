import CoreGraphics
import Foundation

/// The pictures of a spooled page. The queue holds a thumbnail of it on the iPhone (`thumbnailSide`), and a
/// screen that shows the page large reads its `side` preview from the spool file when it appears and lets it
/// go when it leaves or on a memory warning.
public enum QueuePreview {
    /// The long side of the preview a page is shown with.
    public static let side: Int = 1600
    /// The long side of the picture the iPhone's queue keeps for the grid and the stack.
    public static let thumbnailSide: Int = 400

    /// `page` at most `maxSide` pixels on its longer side, turned as the queue shows it: read from its spool
    /// file, or the picture it holds when that is as large already or it has no file. Nil when the file cannot
    /// be read.
    public nonisolated static func image(of page: ScannedPage, maxSide: Int = side) -> CGImage? {
        guard let url = page.fileURL, max(page.image.width, page.image.height) < maxSide else { return page.image }
        return AppState.previewOfSpoolFile(url, quarterTurns: page.rotationQuarterTurns, maxSide: maxSide)
    }
}
