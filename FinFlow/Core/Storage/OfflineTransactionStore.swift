import Foundation

/// Persistent cache and retry queue for transaction writes made without a connection.
/// Data is scoped by user ID so accounts never share cached financial records.
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

    func cachedTransactions(userID: Int) -> [FinanceTransaction] {
        guard let data = defaults.data(forKey: cacheKey(userID: userID)),
              let values = try? decoder.decode([FinanceTransaction].self, from: data) else { return [] }
        return values
    }

    func saveTransactions(_ transactions: [FinanceTransaction], userID: Int) {
        guard let data = try? encoder.encode(transactions) else { return }
        defaults.set(data, forKey: cacheKey(userID: userID))
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

    /// Replays writes in order. A failed operation stays queued for the next refresh.
    func synchronize(userID: Int) async {
        var queue = pendingOperations(userID: userID)
        guard !queue.isEmpty else { return }
        var remaining: [PendingOperation] = []
        for operation in queue {
            do {
                switch operation.kind {
                case .create:
                    guard let payload = operation.request else { continue }
                    let created: FinanceTransaction = try await APIClient.shared.request("/transactions", method: "POST", body: payload)
                    var cached = cachedTransactions(userID: userID)
                    if let temporaryID = operation.transactionID,
                       let index = cached.firstIndex(where: { $0.id == temporaryID }) {
                        cached[index] = created
                    } else if !cached.contains(where: { $0.id == created.id }) {
                        cached.insert(created, at: 0)
                    }
                    saveTransactions(cached, userID: userID)
                case .delete:
                    if let id = operation.transactionID {
                        try await APIClient.shared.perform("/transactions/\(id)", method: "DELETE")
                        removeFromCache(id: id, userID: userID)
                    }
                }
            } catch {
                remaining.append(operation)
            }
        }
        saveQueue(remaining, userID: userID)
    }

    private func pendingOperations(userID: Int) -> [PendingOperation] {
        guard let data = defaults.data(forKey: queueKey(userID: userID)),
              let values = try? decoder.decode([PendingOperation].self, from: data) else { return [] }
        return values
    }

    private func saveQueue(_ queue: [PendingOperation], userID: Int) {
        guard let data = try? encoder.encode(queue) else { return }
        defaults.set(data, forKey: queueKey(userID: userID))
    }
}
