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


// MARK: - Experimental ciphertext-only sync (not used by legacy finance views)

/// The server stores only opaque AES-GCM envelopes. None of these requests
/// sends the recovery key or an unencrypted financial record.
struct OpaqueVaultEntry: Codable {
    let id: UUID
    let revision: Int64
    let nonce: String
    let ciphertext: String
    let updatedAt: String
}

struct DecryptedVaultEntry<Value> {
    let id: UUID
    let revision: Int64
    let updatedAt: String
    let value: Value
}

private struct VaultPutRequest: Encodable {
    let nonce: String
    let ciphertext: String
    let expectedRevision: Int64
}

enum VaultSyncClient {
    private static let base = "/private-vault/entries"

    private static func verifyAccount(_ userId: Int64) throws {
        guard userId > 0,
              let active = TokenStore.shared.read("userId"),
              Int64(active) == userId,
              TokenStore.shared.read("token") != nil
        else { throw APIError.unauthorized }
    }

    static func listPage<Value: Decodable>(
        userId: Int64, recoveryKey: String, after: UUID? = nil,
        limit: Int = 100, as: Value.Type = Value.self
    ) async throws -> [DecryptedVaultEntry<Value>] {
        try verifyAccount(userId)
        guard (1...250).contains(limit) else { throw VaultCrypto.VaultError.invalidEnvelope }
        var query = ["limit": String(limit)]
        if let after { query["after"] = after.uuidString.lowercased() }
        let rows: [OpaqueVaultEntry] = try await APIClient.shared.request(base, query: query)
        try verifyAccount(userId)
        let values = try rows.map { row -> DecryptedVaultEntry<Value> in
            let clear = try VaultCrypto.open(
                .init(nonce: row.nonce, ciphertext: row.ciphertext),
                recoveryKey: recoveryKey, userId: userId, entryId: row.id)
            let value = try JSONDecoder().decode(Value.self, from: clear)
            return .init(id: row.id, revision: row.revision, updatedAt: row.updatedAt, value: value)
        }
        try verifyAccount(userId)
        return values
    }

    static func save<Value: Encodable>(
        _ value: Value, entryId: UUID, userId: Int64,
        recoveryKey: String, expectedRevision: Int64 = 0
    ) async throws -> OpaqueVaultEntry {
        try verifyAccount(userId)
        guard expectedRevision >= 0 else { throw VaultCrypto.VaultError.invalidEnvelope }
        let clear = try JSONEncoder().encode(value)
        let encrypted = try VaultCrypto.seal(
            clear, recoveryKey: recoveryKey, userId: userId, entryId: entryId)
        try verifyAccount(userId)
        return try await APIClient.shared.request(
            base + "/" + entryId.uuidString.lowercased(),
            method: "PUT",
            body: VaultPutRequest(nonce: encrypted.nonce,
                                  ciphertext: encrypted.ciphertext,
                                  expectedRevision: expectedRevision))
    }

    static func remove(entryId: UUID, userId: Int64, expectedRevision: Int64) async throws {
        try verifyAccount(userId)
        guard expectedRevision > 0 else { throw VaultCrypto.VaultError.invalidEnvelope }
        let path = base + "/" + entryId.uuidString.lowercased() +
                   "?expectedRevision=" + String(expectedRevision)
        try await APIClient.shared.perform(path, method: "DELETE")
    }
}
