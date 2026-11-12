#if os(iOS)
import XCTest
@testable import LazyScanIOS

// The app lock's states without the device: an authenticator of the test's own answers, defaults of its own.

private final class FakeAuthenticator: IOSLockAuthenticator, @unchecked Sendable {
    var method: IOSLockMethod = .faceID
    var result: IOSAuthResult
    var reasons: [String] = []

    init(_ result: IOSAuthResult) {
        self.result = result
    }

    func authenticate(reason: String) async -> IOSAuthResult {
        reasons.append(reason)
        return result
    }
}

final class IOSAppLockTests: XCTestCase {
    private var suite: String!
    private var defaults: UserDefaults!

    override func setUp() {
        suite = "IOSAppLockTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suite)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suite)
    }

    @MainActor
    private func makeLock(on: Bool, _ authenticator: FakeAuthenticator) -> IOSAppLock {
        defaults.set(on, forKey: IOSAppLock.key)
        return IOSAppLock(defaults: defaults, authenticator: authenticator)
    }

    @MainActor
    func test_off_isNeverLocked() {
        let lock = makeLock(on: false, FakeAuthenticator(.success))
        XCTAssertFalse(lock.isLocked)
        lock.didEnterBackground()
        XCTAssertFalse(lock.isLocked)
    }

    @MainActor
    func test_on_startsLockedAndOpensOnSuccess() async {
        let authenticator = FakeAuthenticator(.success)
        let lock = makeLock(on: true, authenticator)
        XCTAssertTrue(lock.isLocked)
        await lock.promptIfDue()
        XCTAssertEqual(lock.state, .unlocked)
        XCTAssertFalse(lock.isLocked)
        XCTAssertEqual(authenticator.reasons.count, 1)
    }

    @MainActor
    func test_cancel_staysLockedWithoutFailing_andIsNotAskedAgainByItself() async {
        let authenticator = FakeAuthenticator(.cancelled)
        let lock = makeLock(on: true, authenticator)
        await lock.promptIfDue()
        XCTAssertEqual(lock.state, .locked)
        await lock.promptIfDue()
        XCTAssertEqual(authenticator.reasons.count, 1)
        authenticator.result = .success
        await lock.unlock()
        XCTAssertEqual(lock.state, .unlocked)
    }

    @MainActor
    func test_failure_staysHidden_andUnlockTriesAgain() async {
        let authenticator = FakeAuthenticator(.failed)
        let lock = makeLock(on: true, authenticator)
        await lock.promptIfDue()
        XCTAssertEqual(lock.state, .failed)
        XCTAssertTrue(lock.isLocked)
        authenticator.result = .success
        await lock.unlock()
        XCTAssertEqual(lock.state, .unlocked)
    }

    @MainActor
    func test_background_locksAgainAndAsksAgain() async {
        let authenticator = FakeAuthenticator(.success)
        let lock = makeLock(on: true, authenticator)
        await lock.promptIfDue()
        lock.didEnterBackground()
        XCTAssertEqual(lock.state, .locked)
        await lock.promptIfDue()
        XCTAssertEqual(lock.state, .unlocked)
        XCTAssertEqual(authenticator.reasons.count, 2)
    }

    @MainActor
    func test_removedPasscode_opensWithoutLockingTheUserOut() async {
        let lock = makeLock(on: true, FakeAuthenticator(.unavailable))
        await lock.promptIfDue()
        XCTAssertEqual(lock.state, .unlocked)
    }

    @MainActor
    func test_enable_needsTheDeviceToAgree() async {
        let authenticator = FakeAuthenticator(.unavailable)
        let lock = makeLock(on: false, authenticator)
        var result: IOSAuthResult = await lock.enable()
        XCTAssertEqual(result, .unavailable)
        XCTAssertFalse(lock.enabled)
        authenticator.result = .cancelled
        result = await lock.enable()
        XCTAssertFalse(lock.enabled)
        authenticator.result = .success
        result = await lock.enable()
        XCTAssertEqual(result, .success)
        XCTAssertTrue(lock.enabled)
        XCTAssertFalse(lock.isLocked)
        XCTAssertTrue(defaults.bool(forKey: IOSAppLock.key))
        XCTAssertEqual(authenticator.reasons.last, "Turn on the lock")
    }

    @MainActor
    func test_disable_opensAndForgets() async {
        let lock = makeLock(on: true, FakeAuthenticator(.success))
        await lock.disable()
        XCTAssertFalse(lock.isLocked)
        XCTAssertFalse(defaults.bool(forKey: IOSAppLock.key))
    }

    @MainActor
    func test_disable_whileLockedStaysOnAfterCancel() async {
        let lock = makeLock(on: true, FakeAuthenticator(.cancelled))
        await lock.disable()
        XCTAssertTrue(lock.enabled)
        XCTAssertTrue(lock.isLocked)
        XCTAssertTrue(defaults.bool(forKey: IOSAppLock.key))
    }

    func test_switchLabel_followsTheMethod() {
        XCTAssertEqual(IOSLockMethod.faceID.switchLabel, "Require Face ID")
        XCTAssertEqual(IOSLockMethod.touchID.switchLabel, "Require Touch ID")
        XCTAssertEqual(IOSLockMethod.passcode.switchLabel, "Require passcode")
    }
}
#endif
