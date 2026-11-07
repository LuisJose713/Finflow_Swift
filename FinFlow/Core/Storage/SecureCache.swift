import Foundation
import CryptoKit

/// Encrypts cached financial data at rest using an on-device symmetric key.
/// Only encrypted AES-GCM payloads are persisted in UserDefaults; the key
/// lives in the Keychain with this-device-only accessibility.
enum SecureCache {
    private static let keyName = "offline-cache-key"

    enum Failure: LocalizedError {
        case keyUnavailable
        case invalidCiphertext

        var errorDescription: String? {
            switch self {
            case .keyUnavailable: return "No fue posible proteger la caché local."
            case .invalidCiphertext: return "Los datos de caché no pudieron validarse."
            }
        }
    }

    private static func encryptionKey() throws -> SymmetricKey {
        if let existing = TokenStore.shared.read(keyName),
           let data = Data(base64Encoded: existing), data.count == 32 {
            return SymmetricKey(data: data)
        }

        let generated = SymmetricKey(size: .bits256)
        let raw = generated.withUnsafeBytes { Data($0) }
        TokenStore.shared.save(raw.base64EncodedString(), account: keyName)
        guard TokenStore.shared.read(keyName) == raw.base64EncodedString() else {
            throw Failure.keyUnavailable
        }
        return generated
    }

    static func seal(_ cleartext: Data) throws -> Data {
        guard let data = try AES.GCM.seal(cleartext, using: encryptionKey()).combined else {
            throw Failure.invalidCiphertext
        }
        return data
    }

    static func open(_ encrypted: Data) throws -> Data {
        return try AES.GCM.open(
            AES.GCM.SealedBox(combined: encrypted), using: encryptionKey())
    }
}
