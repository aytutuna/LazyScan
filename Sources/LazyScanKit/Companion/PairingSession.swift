import Foundation

// Twin of windows/LazyScan.Core/Companion/PairingSession.cs: the same lifetime, attempt limit
// and answers.

/// Where a pairing session is.
public enum PairingSessionState: Equatable, Sendable {
    /// Waiting for a phone to present the token.
    case open
    /// A phone presented the token; it cannot be used again.
    case used
    /// Its five minutes are over.
    case expired
    /// Closed by the desktop, or after too many wrong tokens.
    case closed
}

/// The answer to a token presented to a pairing session.
public enum PairingRedeemResult: Equatable, Sendable {
    case accepted
    case wrongToken
    case expired
    case alreadyUsed
    case closed
}

/// The answer to a short code presented to a pairing session.
public enum PairingCodeResult: Equatable, Sendable {
    /// The right code while the session is open; the session stays open for the pairing itself.
    case right
    case wrong
    /// The wrong code that was the last one allowed: the session is closed.
    case tooManyAttempts
    case expired
    case alreadyUsed
    case closed
}

/// A pairing session made with a token that is not 16 bytes, or a code that is not 6 digits.
public struct PairingSessionError: Error, Equatable, Sendable {}

/// One pairing window on the desktop: a random 128-bit token shown in the QR code, good for one
/// pairing within `lifetime`. Tokens are compared in constant time. Wrong ones are counted but do not
/// close the session, so another device cannot shut the code; the router limits each address instead.
/// The same session has a 6-digit code for a phone that cannot scan: it fetches the pairing text with it,
/// and `maxCodeAttempts` wrong codes close the session, counted for the session and not per address
/// (a code has a million values, a token has 2^128).
/// The clock is passed in, so tests control it. Safe to use from any thread.
public final class PairingSession: @unchecked Sendable {
    public static let lifetime: TimeInterval = 5 * 60
    public static let codeDigitCount = 6
    public static let maxCodeAttempts = 5

    private let lock = NSLock()
    private let tokenBytes: [UInt8]
    private var current: PairingSessionState = .open
    private var failed = 0
    private let codeBytes: [UInt8]
    private var failedCodeCount = 0

    /// The token as the pairing code carries it (base64url, 22 characters).
    public let token: String
    /// The short code as the desktop shows it, grouped in threes through `formattedCode`.
    public let code: String
    public let opened: Date
    public let expires: Date

    /// - Parameters:
    ///   - opened: When the session opens; it expires `lifetime` later.
    ///   - token: The token's 16 bytes; random when nil (tests pass their own).
    ///   - code: The 6 digits of the short code; random when nil.
    public init(opened: Date, token: Data? = nil, code: String? = nil) throws {
        var generator = SystemRandomNumberGenerator()
        let bytes: [UInt8]
        if let token = token {
            guard token.count == PairingUri.tokenByteCount else { throw PairingSessionError() }
            bytes = [UInt8](token)
        } else {
            bytes = (0..<PairingUri.tokenByteCount).map { _ in UInt8.random(in: UInt8.min...UInt8.max, using: &generator) }
        }
        let digits = code ?? String(format: "%06d", Int.random(in: 0..<1_000_000, using: &generator))
        guard digits.utf8.count == PairingSession.codeDigitCount, digits.utf8.allSatisfy({ $0 >= 48 && $0 <= 57 }) else {
            throw PairingSessionError()
        }
        tokenBytes = bytes
        codeBytes = Array(digits.utf8)
        self.code = digits
        self.token = CompanionProtocol.encodeBase64Url(Data(bytes))
        self.opened = opened
        expires = opened.addingTimeInterval(PairingSession.lifetime)
    }

    public var failedAttempts: Int {
        lock.lock()
        defer { lock.unlock() }
        return failed
    }

    /// The code in two groups of three ("482 913").
    public var formattedCode: String {
        String(code.prefix(3)) + " " + String(code.suffix(3))
    }

    public var failedCodes: Int {
        lock.lock()
        defer { lock.unlock() }
        return failedCodeCount
    }

    /// Where the session is at `now`.
    public func state(at now: Date) -> PairingSessionState {
        lock.lock()
        defer { lock.unlock() }
        return current == .open && now >= expires ? .expired : current
    }

    /// How long the session stays open after `now`; zero once it is not open.
    public func remaining(at now: Date) -> TimeInterval {
        state(at: now) == .open ? expires.timeIntervalSince(now) : 0
    }

    /// Presents `token` at `now`. The right token while the session is open is accepted once; a wrong
    /// one is counted and the session stays open.
    public func redeem(_ token: String?, now: Date) -> PairingRedeemResult {
        lock.lock()
        defer { lock.unlock() }
        switch current {
        case .used: return .alreadyUsed
        case .closed: return .closed
        case .open, .expired: break
        }
        if now >= expires {
            current = .expired
            return .expired
        }
        if current == .expired { return .expired }
        var matches = false
        if let presented = CompanionProtocol.decodeBase64Url(token), presented.count == PairingUri.tokenByteCount {
            let bytes = [UInt8](presented)
            var difference: UInt8 = 0
            for i in 0..<tokenBytes.count {
                difference |= bytes[i] ^ tokenBytes[i]
            }
            matches = difference == 0
        }
        if !matches {
            failed += 1
            return .wrongToken
        }
        current = .used
        return .accepted
    }

    /// Presents the short code at `now`; spaces are ignored. The right code leaves the session open, since
    /// the phone still has to pair with the token it gets. A wrong one is counted, and the last one allowed
    /// closes the session.
    public func checkCode(_ presented: String?, now: Date) -> PairingCodeResult {
        lock.lock()
        defer { lock.unlock() }
        switch current {
        case .used: return .alreadyUsed
        case .closed: return .closed
        case .open, .expired: break
        }
        if now >= expires {
            current = .expired
            return .expired
        }
        if current == .expired { return .expired }
        let bytes = Array((presented ?? "").replacingOccurrences(of: " ", with: "").utf8)
        var matches = bytes.count == codeBytes.count
        if matches {
            var difference: UInt8 = 0
            for i in 0..<codeBytes.count {
                difference |= bytes[i] ^ codeBytes[i]
            }
            matches = difference == 0
        }
        if matches { return .right }
        failedCodeCount += 1
        if failedCodeCount >= PairingSession.maxCodeAttempts {
            current = .closed
            return .tooManyAttempts
        }
        return .wrong
    }

    /// Closes the session: no token is accepted any more.
    public func close() {
        lock.lock()
        defer { lock.unlock() }
        if current == .open { current = .closed }
    }
}
