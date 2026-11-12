import Foundation

// The shared status texts name desktop things: the queue, a Save PDF button, tasks. The phone has
// a page strip, a round Save button and types, so the messages it can show have a phone form.
// The iPhone app turns it on at launch; tests of the shared texts, which also run on the iOS
// Simulator, keep the desktop form unless they choose the phone's with `choosing`.

public enum PhoneWording {
    @TaskLocal static var override: Bool?

    private static let lock = NSLock()
    private nonisolated(unsafe) static var launched = false

    /// Called once by the iPhone app, before any text is built.
    public static func useOnPhone() {
        lock.withLock { launched = true }
    }

    static var isPhone: Bool {
        if let override { return override }
        return lock.withLock { launched }
    }

    static func choosing<T>(phone: Bool, _ body: () throws -> T) rethrows -> T {
        try $override.withValue(phone, operation: body)
    }
}
