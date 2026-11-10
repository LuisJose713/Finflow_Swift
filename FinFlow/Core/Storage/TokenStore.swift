import Foundation
import Security

final class TokenStore: @unchecked Sendable {
    static let shared = TokenStore()
    private let service = "com.finflow.ios.session"
    // Keychain mutations must be serialized so a late 401 cannot erase
    // the token installed by a concurrent successful login.
    private let lock = NSRecursiveLock()
    private init() {}

    func save(_ value: String, account: String) {
        lock.lock()
        defer { lock.unlock() }
        let data = Data(value.utf8)
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: account]
        SecItemDelete(query as CFDictionary)
        var insert = query; insert[kSecValueData as String] = data
        insert[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        SecItemAdd(insert as CFDictionary, nil)
    }
    func read(_ account: String) -> String? {
        lock.lock()
        defer { lock.unlock() }
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: account, kSecReturnData as String: true, kSecMatchLimit as String: kSecMatchLimitOne]
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess, let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }
    /// Atomic compare-and-delete: never remove a replacement token when an
    /// older request returns HTTP 401 after another successful login.
    func deleteSession(ifTokenMatches failedToken: String) {
        lock.lock()
        defer { lock.unlock() }
        guard !failedToken.isEmpty, read("token") == failedToken else { return }
        deleteAll()
    }

    func deleteAll() {
        lock.lock()
        defer { lock.unlock() }
        ["token", "userId", "userName", "email"].forEach { account in
        SecItemDelete([kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: account] as CFDictionary)
    } }
}
