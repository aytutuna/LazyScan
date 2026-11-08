import Foundation

// Twin of windows/LazyScan.Core/LazyPrintUrl.cs: the address that opens Lazy Print with files.

/// `lazyprint:open?file=%2FUsers%2Fme%2Fscan.pdf`: the `file` parameter repeated for each file, each path
/// percent-encoded whole. The iPhone cannot read another app's paths, so it names a folder both apps share
/// instead: `lazyprint:open?handoff=<uuid>`, the folder `Handoff/<uuid>` of the `handoffGroup` container
/// (Swift only; the address has one `handoff` and no `file`).
public enum LazyPrintUrl {
    public static let scheme = "lazyprint"
    public static let handoffGroup = "group.com.alazy.handoff"
    public static let handoffFolder = "Handoff"

    private static let unreserved = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")

    public static func build(_ paths: [String]) -> String {
        let files = paths.map { "file=" + ($0.addingPercentEncoding(withAllowedCharacters: unreserved) ?? $0) }
        return scheme + ":open?" + files.joined(separator: "&")
    }

    public static func buildHandoff(_ id: UUID) -> String {
        let text = id.uuidString
        return scheme + ":open?handoff=" + (text.addingPercentEncoding(withAllowedCharacters: unreserved) ?? text)
    }
}
