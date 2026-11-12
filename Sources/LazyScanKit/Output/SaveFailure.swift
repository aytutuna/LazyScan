import Foundation

// Twin of windows/LazyScan.Core/SaveErrors.cs.

/// Plain sentences for a file that could not be written: they name the folder it was going to, never
/// the hidden temp file, and say the pages are kept.
public enum SaveFailure {
    public static var pagesKept: String { L10n.t("The pages are still in the queue.") }

    /// `error` is nil when the system gave none (a file that could not be created).
    public static func message(_ error: Error?, folder: URL) -> String {
        "\(reason(error, folder: folder)) \(pagesKept)"
    }

    private enum Cause { case diskFull, notAllowed, missing }

    private static func reason(_ error: Error?, folder: URL) -> String {
        let name = folder.lastPathComponent
        switch cause(error, folder: folder) {
        case .diskFull?:
            return L10n.t("There is not enough space to save in “{0}”.", name)
        case .notAllowed?:
            return L10n.t("Files cannot be saved in “{0}”. It may be read-only. Choose another folder.", name)
        case .missing?:
            return L10n.t("The folder “{0}” was not found. Choose another folder.", name)
        case nil:
            return L10n.t("Could not save in “{0}”.", name)
        }
    }

    private static func cause(_ error: Error?, folder: URL) -> Cause? {
        let manager = FileManager.default
        if let error {
            let nsError = error as NSError
            var posix: Int32?
            if nsError.domain == NSPOSIXErrorDomain {
                posix = Int32(nsError.code)
            } else if let underlying = nsError.userInfo[NSUnderlyingErrorKey] as? NSError,
                      underlying.domain == NSPOSIXErrorDomain {
                posix = Int32(underlying.code)
            }
            if posix == ENOSPC { return .diskFull }
            if posix == EACCES || posix == EPERM || posix == EROFS { return .notAllowed }
            if nsError.domain == NSCocoaErrorDomain {
                switch nsError.code {
                case CocoaError.Code.fileWriteOutOfSpace.rawValue:
                    return .diskFull
                case CocoaError.Code.fileWriteNoPermission.rawValue, CocoaError.Code.fileWriteVolumeReadOnly.rawValue:
                    return .notAllowed
                default:
                    break
                }
            }
        }
        if !manager.fileExists(atPath: folder.path) { return .missing }
        if error == nil, !manager.isWritableFile(atPath: folder.path) { return .notAllowed }
        return nil
    }
}
