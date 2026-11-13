import XCTest
@testable import FinFlow

final class StorageAndAPITests: XCTestCase {
    func testEncryptedCacheRejectsTampering() throws {
        let clear = Data("private-financial-data".utf8)
        let encrypted = try SecureCache.seal(clear)
        XCTAssertNotEqual(encrypted, clear)
        XCTAssertEqual(try SecureCache.open(encrypted), clear)
        var damaged = encrypted; damaged[damaged.count - 1] ^= 1
        XCTAssertThrowsError(try SecureCache.open(damaged))
    }

    func testOfflineCacheIsolationAndLogoutCleanup() {
        let store = OfflineTransactionStore.shared
        let tx = FinanceTransaction(id: 71, description: "Synthetic", amount: 25000.5, type: "expense", categoryId: 1, date: "2026-11-12", notes: nil, userId: 900001)
        store.saveTransactions([tx], userID: 900001)
        XCTAssertEqual(store.cachedTransactions(userID: 900001).count, 1)
        XCTAssertTrue(store.cachedTransactions(userID: 900002).isEmpty)
        store.clear(userID: 900001)
        XCTAssertTrue(store.cachedTransactions(userID: 900001).isEmpty)
    }

    func testDelayed401CannotDeleteNewSession() {
        let tokenStore = TokenStore.shared
        defer { tokenStore.deleteAll() }
        XCTAssertTrue(tokenStore.save("new-token", account: "token"))
        tokenStore.deleteSession(ifTokenMatches: "old-token")
        XCTAssertEqual(tokenStore.read("token"), "new-token")
        tokenStore.deleteSession(ifTokenMatches: "new-token")
        XCTAssertNil(tokenStore.read("token"))
    }

    func testSharedAPIModelsDecodeForEveryFinancialScreen() async throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [PreviewAPIProtocol.self]
        let client = APIClient(session: URLSession(configuration: configuration))
        let stats: TransactionStats = try await client.request("/transactions/stats")
        XCTAssertEqual(stats.balance, stats.totalIncome - stats.totalExpenses, accuracy: 0.001)
        let transactions: [FinanceTransaction] = try await client.request("/transactions")
        let categories: [FinanceCategory] = try await client.request("/categories")
        let wallets: [FinancialAccount] = try await client.request("/accounts")
        let goals: [FinanceGoal] = try await client.request("/goals")
        let budgets: [BudgetOverview] = try await client.request("/budgets")
        let planned: [PlannedExpense] = try await client.request("/planned-expenses")
        let recurring: [RecurringRule] = try await client.request("/recurring")
        XCTAssertFalse(transactions.isEmpty || categories.isEmpty || wallets.isEmpty || goals.isEmpty || budgets.isEmpty || planned.isEmpty || recurring.isEmpty)
        let response: AdvisorResponse = try await client.request("/ai/chat", method: "POST", body: AdvisorRequest(mensaje: "Consulta de prueba"))
        XCTAssertFalse(response.respuesta.isEmpty)
    }
}
