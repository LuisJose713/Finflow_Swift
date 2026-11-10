import Foundation
import CryptoKit

/// Client-side AES-256-GCM. Never upload the recovery key or plaintext finance fields.
/// Not yet connected to legacy FinFlow features; no production migration is implied.
enum VaultCrypto {
    enum VaultError: Error {
        case invalidKey
        case invalidEnvelope
        case invalidIdentity
    }

    struct Envelope: Codable, Equatable {
        let nonce: String
        let ciphertext: String // ciphertext concatenated with GCM authentication tag
    }

    private static let prefix = "finflow:private-vault:v1:"

    static func newRecoveryKey() -> String {
        let key = SymmetricKey(size: .bits256)
        return encode(key.withUnsafeBytes { Data($0) })
    }

    static func seal(
        _ clear: Data, recoveryKey: String, userId: Int64, entryId: UUID
    ) throws -> Envelope {
        let key = try importKey(recoveryKey)
        let nonce = AES.GCM.Nonce()
        let sealed = try AES.GCM.seal(clear, using: key, nonce: nonce,
                                      authenticating: try aad(userId, entryId))
        let iv = nonce.withUnsafeBytes { Data($0) }
        return Envelope(nonce: encode(iv),
                        ciphertext: encode(sealed.ciphertext + sealed.tag))
    }

    static func open(
        _ envelope: Envelope, recoveryKey: String, userId: Int64, entryId: UUID
    ) throws -> Data {
        let key = try importKey(recoveryKey)
        let iv = try decode(envelope.nonce)
        let combinedCipher = try decode(envelope.ciphertext)
        guard iv.count == 12, combinedCipher.count >= 16 else { throw VaultError.invalidEnvelope }
        let sealed = try AES.GCM.SealedBox(
            nonce: AES.GCM.Nonce(data: iv),
            ciphertext: combinedCipher.dropLast(16),
            tag: combinedCipher.suffix(16))
        return try AES.GCM.open(sealed, using: key, authenticating: try aad(userId, entryId))
    }

    private static func aad(_ userId: Int64, _ id: UUID) throws -> Data {
        guard userId > 0 else { throw VaultError.invalidIdentity }
        return Data("\(prefix)\(userId):\(id.uuidString.lowercased())".utf8)
    }

    private static func importKey(_ encoded: String) throws -> SymmetricKey {
        let bytes = try decode(encoded)
        guard bytes.count == 32 else { throw VaultError.invalidKey }
        return SymmetricKey(data: bytes)
    }

    private static func encode(_ bytes: Data) -> String {
        bytes.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    private static func decode(_ encoded: String) throws -> Data {
        guard !encoded.isEmpty,
              encoded.unicodeScalars.allSatisfy({
                  CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789_-").contains($0)
              })
        else { throw VaultError.invalidEnvelope }
        let conventional = encoded.replacingOccurrences(of: "-", with: "+")
                                  .replacingOccurrences(of: "_", with: "/")
        let padded = conventional + String(repeating: "=", count: (4 - conventional.count % 4) % 4)
        guard let value = Data(base64Encoded: padded) else { throw VaultError.invalidEnvelope }
        return value
    }
}
