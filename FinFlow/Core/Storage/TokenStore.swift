import Foundation
import Security

extension Notification.Name {
    static let finflowSessionExpired = Notification.Name("finflow.sessionExpired")
}

final class TokenStore: @unchecked Sendable {
    static let shared = TokenStore()
    private let service = "com.finflow.ios.session"
    // Keychain mutations must be serialized so a late 401 cannot erase
    // the token installed by a concurrent successful login.
    private let lock = NSRecursiveLock()
    private init() {}

    @discardableResult
    func save(_ value: String, account: String) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        let data = Data(value.utf8)
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: account]
        let attributes: [String: Any] = [kSecValueData as String: data,
                                       kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly]
        let status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if status == errSecSuccess { return true }
        guard status == errSecItemNotFound else { return false }
        return SecItemAdd(query.merging(attributes) { _, new in new } as CFDictionary, nil) == errSecSuccess
    }
    func read(_ account: String) -> String? {
        lock.lock()
        defer { lock.unlock() }
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: account, kSecReturnData as String: true, kSecMatchLimit as String: kSecMatchLimitOne]
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess, let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }
    @discardableResult
    func saveCredentials(_ response: AuthResponse) -> Bool {
        lock.lock(); defer { lock.unlock() }
        return writeCredentials(response)
    }

    func replaceCredentials(_ response: AuthResponse, ifTokenMatches expected: String?) -> Bool {
        lock.lock(); defer { lock.unlock() }
        guard read("token") == expected else { return false }
        return writeCredentials(response)
    }

    private func writeCredentials(_ response: AuthResponse) -> Bool {
        let fields = [("refreshToken", response.refreshToken ?? ""),
                      ("userId", String(response.user.id)), ("userName", response.user.name),
                      ("email", response.user.email), ("token", response.token)]
        for (account, value) in fields {
            guard save(value, account: account) else { deleteAll(); return false }
        }
        return true
    }

    /// Atomic compare-and-delete: never remove a replacement token when an
    /// older request returns HTTP 401 after another successful login.
    func deleteSession(ifTokenMatches failedToken: String) {
        lock.lock()
        defer { lock.unlock() }
        guard !failedToken.isEmpty, read("token") == failedToken else { return }
        deleteAll()
        NotificationCenter.default.post(name: .finflowSessionExpired, object: nil)
    }

    func deleteAll() {
        lock.lock()
        defer { lock.unlock() }
        ["token", "refreshToken", "userId", "userName", "email"].forEach { account in
        SecItemDelete([kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: account] as CFDictionary)
    } }
}
