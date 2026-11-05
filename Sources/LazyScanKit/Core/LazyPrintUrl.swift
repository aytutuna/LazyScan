import Foundation

// Twin of windows/LazyScan.Core/LazyPrintUrl.cs: the address that opens Lazy Print with files.

/// `lazyprint:open?file=%2FUsers%2Fme%2Fscan.pdf`: the `file` parameter repeated for each file, each path
/// percent-encoded whole.
public enum LazyPrintUrl {
    public static let scheme = "lazyprint"

    private static let unreserved = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")

    public static func build(_ paths: [String]) -> String {
        let files = paths.map { "file=" + ($0.addingPercentEncoding(withAllowedCharacters: unreserved) ?? $0) }
        return scheme + ":open?" + files.joined(separator: "&")
    }
}
