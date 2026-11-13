import XCTest
import LocalAuthentication
@testable import FinFlow

@MainActor
private final class TestAuthenticator: LocalAuthenticationProviding {
    var isAvailable = true
    var name = "Face ID"
    var symbol = "faceid"
    var result = false
    var calls = 0
    var delayed = false
    var cancelled = false
    var continuation: CheckedContinuation<Bool, Error>?
    func authenticate(reason: String) async throws -> Bool {
        calls += 1
        if cancelled { throw LAError(.userCancel) }
        if delayed { return try await withCheckedThrowingContinuation { continuation = $0 } }
        return result
    }
    func cancel() {} // Deliberately allow a stale success to test the generation guard.
    func finish(_ result: Bool) { continuation?.resume(returning: result); continuation = nil }
}

final class AppLockTests: XCTestCase {
    @MainActor private func makeStore(_ auth: TestAuthenticator) -> AppLockStore {
        AppLockStore(authenticator: auth, defaults: UserDefaults(suiteName: "finflow.tests.\(UUID().uuidString)")!)
    }

    @MainActor func testCancelledPromptStaysLockedAndDoesNotLoopOnInactive() async {
        let auth = TestAuthenticator(); let store = makeStore(auth)
        store.prepare(ownerID: 1)
        XCTAssertTrue(store.isLocked)
        await store.unlock(automatically: true)
        XCTAssertTrue(store.isLocked)
        store.becameInactive(); await store.becameActive()
        XCTAssertEqual(auth.calls, 1)
        auth.result = true
        await store.unlock()
        XCTAssertFalse(store.isLocked)
    }

    @MainActor func testBackgroundRequiresFreshAuthentication() async {
        let auth = TestAuthenticator(); auth.result = true
        let store = makeStore(auth); store.prepare(ownerID: 1)
        await store.unlock(automatically: true)
        XCTAssertFalse(store.isLocked)
        store.enteredBackground()
        XCTAssertTrue(store.isLocked)
        await store.becameActive()
        XCTAssertFalse(store.isLocked)
        XCTAssertEqual(auth.calls, 2)
    }

    @MainActor func testLateSuccessAfterBackgroundCannotUnlock() async {
        let auth = TestAuthenticator(); auth.delayed = true
        let store = makeStore(auth); store.prepare(ownerID: 1)
        let attempt = Task { await store.unlock() }
        while auth.continuation == nil { await Task.yield() }
        store.enteredBackground(); auth.finish(true)
        await attempt.value
        XCTAssertTrue(store.isLocked)
        XCTAssertFalse(store.isAuthenticating)
    }

    @MainActor func testLateSuccessCannotUnlockAnotherAccount() async {
        let auth = TestAuthenticator(); auth.delayed = true
        let store = makeStore(auth); store.prepare(ownerID: 1)
        let attempt = Task { await store.unlock() }
        while auth.continuation == nil { await Task.yield() }
        store.prepare(ownerID: nil); store.prepare(ownerID: 2)
        auth.finish(true); await attempt.value
        XCTAssertTrue(store.isLocked)
    }

    @MainActor func testProtectionChangesRequireIdentityAndArePerAccount() async {
        let auth = TestAuthenticator(); let store = makeStore(auth)
        store.prepare(ownerID: 1)
        await store.setEnabled(false)
        XCTAssertTrue(store.isEnabled)
        auth.result = true
        await store.setEnabled(false)
        XCTAssertFalse(store.isEnabled)
        store.prepare(ownerID: 2)
        XCTAssertTrue(store.isEnabled)
        store.prepare(ownerID: 1)
        XCTAssertFalse(store.isEnabled)
    }

    @MainActor func testUnavailableAuthenticationCannotBypassExistingLock() async {
        let auth = TestAuthenticator(); let store = makeStore(auth)
        store.prepare(ownerID: 1)
        auth.isAvailable = false
        await store.unlock()
        XCTAssertTrue(store.isLocked)
        XCTAssertNotNil(store.error)
    }

    @MainActor func testConcurrentUnlockStartsOnlyOnePrompt() async {
        let auth = TestAuthenticator(); auth.delayed = true
        let store = makeStore(auth); store.prepare(ownerID: 1)
        let attempt = Task { await store.unlock() }
        while auth.continuation == nil { await Task.yield() }
        await store.unlock()
        XCTAssertEqual(auth.calls, 1)
        auth.finish(true); await attempt.value
        XCTAssertFalse(store.isLocked)
    }

    @MainActor func testSystemCancellationKeepsTheLock() async {
        let auth = TestAuthenticator(); auth.cancelled = true
        let store = makeStore(auth); store.prepare(ownerID: 1)
        await store.unlock()
        XCTAssertTrue(store.isLocked)
        XCTAssertFalse(store.isAuthenticating)
    }

    @MainActor func testNotificationDestinationWaitsForAuthenticatedNavigation() {
        let navigation = AppNavigationStore()
        navigation.open("transactions")
        XCTAssertEqual(navigation.pendingDestination, .transactions)
        navigation.open("https://example.invalid")
        XCTAssertEqual(navigation.pendingDestination, .transactions)
        XCTAssertEqual(navigation.takeDestination(), .transactions)
        XCTAssertNil(navigation.takeDestination())
        navigation.open("dashboard"); navigation.clear()
        XCTAssertNil(navigation.pendingDestination)
    }
}
