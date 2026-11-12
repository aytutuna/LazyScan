import Foundation

extension FileManager {
    /// Creates `url` and its parents. On iOS the folder gets the CompleteUnlessOpen class, which files made
    /// in it inherit: they can still be written while the phone is locked, but not opened again until it is unlocked.
    public func createDirectoryCompleteUnlessOpen(at url: URL) throws {
        try createDirectory(at: url, withIntermediateDirectories: true)
        #if os(iOS)
        try? setAttributes([.protectionKey: FileProtectionType.completeUnlessOpen], ofItemAtPath: url.path)
        #endif
    }
}
