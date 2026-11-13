import Foundation

/// Encrypted per-user offline read cache and a preserved legacy write queue.
/// Writes are never silently replayed until the backend supports idempotency.
final class OfflineTransactionStore: @unchecked Sendable {
    static let shared = OfflineTransactionStore()
    private let defaults = UserDefaults.standard
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()
    private init() {}

    private struct PendingOperation: Codable, Identifiable {
        enum Kind: String, Codable { case create, delete }
        var id: UUID = UUID()
        var kind: Kind
        var transactionID: Int?
        var request: CreateTransactionRequest?
    }

    private func cacheKey(userID: Int) -> String { "finflow.offline.transactions.\(userID)" }
    private func queueKey(userID: Int) -> String { "finflow.offline.queue.\(userID)" }

    func clear(userID: Int) {
        defaults.removeObject(forKey: cacheKey(userID: userID))
        defaults.removeObject(forKey: queueKey(userID: userID))
    }

    func cachedTransactions(userID: Int) -> [FinanceTransaction] {
        readEncryptedOrLegacy([FinanceTransaction].self, at: cacheKey(userID: userID)) ?? []
    }

    func saveTransactions(_ transactions: [FinanceTransaction], userID: Int) {
        saveEncrypted(transactions, at: cacheKey(userID: userID))
    }

    func addPendingCreate(_ request: CreateTransactionRequest, userID: Int) -> FinanceTransaction {
        let temporaryID = -Int(Date().timeIntervalSince1970 * 1_000)
        let transaction = FinanceTransaction(id: temporaryID, description: request.description,
            amount: request.amount, type: request.type, categoryId: request.categoryId,
            date: request.date, notes: request.notes, userId: userID)
        var queue = pendingOperations(userID: userID)
        queue.append(PendingOperation(kind: .create, transactionID: temporaryID, request: request))
        saveQueue(queue, userID: userID)
        var cached = cachedTransactions(userID: userID)
        cached.removeAll { $0.id == temporaryID }
        cached.insert(transaction, at: 0)
        saveTransactions(cached, userID: userID)
        return transaction
    }

    func queueDelete(transaction: FinanceTransaction, userID: Int) {
        if transaction.id < 0 {
            // A locally created item not yet sent to the server can simply be discarded.
            var queue = pendingOperations(userID: userID)
            queue.removeAll { $0.kind == .create && $0.transactionID == transaction.id }
            saveQueue(queue, userID: userID)
        } else {
            var queue = pendingOperations(userID: userID)
            queue.append(PendingOperation(kind: .delete, transactionID: transaction.id))
            saveQueue(queue, userID: userID)
        }
        var cached = cachedTransactions(userID: userID)
        cached.removeAll { $0.id == transaction.id }
        saveTransactions(cached, userID: userID)
    }

    func removeFromCache(id: Int, userID: Int) {
        var cached = cachedTransactions(userID: userID)
        cached.removeAll { $0.id == id }
        saveTransactions(cached, userID: userID)
    }

    func hasPendingOperations(userID: Int) -> Bool { !pendingOperations(userID: userID).isEmpty }

    func pendingDeleteIDs(userID: Int) -> Set<Int> {
        Set(pendingOperations(userID: userID).compactMap { operation in
            operation.kind == .delete ? operation.transactionID : nil
        })
    }

    static func isConnectivityError(_ error: Error) -> Bool {
        if let urlError = error as? URLError {
            return [.notConnectedToInternet, .networkConnectionLost, .timedOut,
                    .cannotFindHost, .cannotConnectToHost, .dnsLookupFailed,
                    .internationalRoamingOff, .dataNotAllowed].contains(urlError.code)
        }
        let nsError = error as NSError
        return nsError.domain == NSURLErrorDomain
    }

    /// Deliberately disabled: replaying a POST after a timeout may duplicate money
    /// unless the backend offers an idempotency key. Legacy pending entries stay
    /// encrypted on-device for manual review and are never silently replayed.
    func synchronize(userID: Int) async {
        // No network effects until server idempotency is implemented.
    }

    private func pendingOperations(userID: Int) -> [PendingOperation] {
        readEncryptedOrLegacy([PendingOperation].self, at: queueKey(userID: userID)) ?? []
    }

    private func saveQueue(_ queue: [PendingOperation], userID: Int) {
        saveEncrypted(queue, at: queueKey(userID: userID))
    }

    private func readEncryptedOrLegacy<T: Decodable>(_ type: T.Type, at key: String) -> T? {
        guard let stored = defaults.data(forKey: key) else { return nil }

        if let cleartext = try? SecureCache.open(stored) {
            return try? decoder.decode(T.self, from: cleartext)
        }
        // One-time migration from older app builds that stored plain JSON.
        // Never remove legacy bytes until encrypted data can be written.
        guard let legacy = try? decoder.decode(T.self, from: stored) else { return nil }
        if let encrypted = try? SecureCache.seal(stored) {
            defaults.set(encrypted, forKey: key)
        }
        return legacy
    }

    private func saveEncrypted<T: Encodable>(_ value: T, at key: String) {
        guard let raw = try? encoder.encode(value),
              let encrypted = try? SecureCache.seal(raw) else { return }
        defaults.set(encrypted, forKey: key)
    }
}
