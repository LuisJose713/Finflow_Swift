#if DEBUG
import Foundation

/// Deterministic, synthetic data for XCTest only. Every request is intercepted;
/// this transport never falls through to production. Excluded from Release.
final class PreviewAPIProtocol: URLProtocol, @unchecked Sendable {
    private static let server = PreviewServer()
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        let (status, payload) = Self.server.response(for: request)
        let data = (try? JSONSerialization.data(withJSONObject: payload)) ?? Data()
        let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: "HTTP/1.1",
                                       headerFields: ["Content-Type": "application/json; charset=utf-8"])!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}

private final class PreviewServer: @unchecked Sendable {
    private let lock = NSLock()
    private var nextID = 100
    private var transactions: [[String: Any]] = [
        ["id": 1, "description": "Nómina de noviembre", "amount": 3200000, "type": "income", "categoryId": 1, "date": "2026-11-10", "status": "completed", "currency": "COP"],
        ["id": 2, "description": "Compra del supermercado", "amount": 284500.5, "type": "expense", "categoryId": 2, "date": "2026-11-11", "status": "completed", "currency": "COP"],
        ["id": 3, "description": "Café y desayuno", "amount": 18500, "type": "expense", "categoryId": 2, "date": "2026-11-12", "status": "completed", "currency": "COP"],
        ["id": 4, "description": "Proyecto independiente", "amount": 450000, "type": "income", "categoryId": 1, "date": "2026-11-12", "status": "pending", "currency": "COP"]
    ]
    private let categories: [[String: Any]] = [
        ["id": 1, "name": "Trabajo", "type": "income"],
        ["id": 2, "name": "Alimentación", "type": "expense"],
        ["id": 3, "name": "Transporte", "type": "expense", "userId": 987654]
    ]
    private var goals: [[String: Any]] = [
        ["id": 1, "title": "Fondo de tranquilidad", "targetAmount": 3000000, "currentAmount": 1200000, "deadline": "2027-05-01", "status": "active", "description": "Un paso a la vez."]
    ]

    func response(for request: URLRequest) -> (Int, Any) {
        lock.lock(); defer { lock.unlock() }
        let path = request.url?.path ?? ""
        let method = request.httpMethod ?? "GET"
        let body = jsonBody(request)
        let user: [String: Any] = ["id": 987654, "email": "ios.qa@example.invalid", "name": "Lucía Pruebas", "role": ProcessInfo.processInfo.environment["FINFLOW_UI_ADMIN"] == "1" ? "ADMIN" : "USER"]
        if path == "/auth/login" || path == "/auth/register" {
            return (200, ["token": "synthetic-test-token", "refreshToken": "synthetic-test-refresh", "user": user])
        }
        if path == "/auth/me" { return (200, user) }
        if path == "/auth/logout" || path == "/auth/account" { return (200, ["status": "ok"]) }
        if path == "/privacy/policy" {
            return (200, ["version": "ui-test-v1", "effectiveDate": "2026-11-12", "ready": false, "controllerName": "FinFlow · entorno de pruebas", "controllerNit": "", "contactEmail": "", "contactAddress": "", "contactPhone": ""])
        }
        if path == "/privacy/status" { return (200, ["accepted": false, "version": "ui-test-v1", "policyReady": false, "marketingConsent": false]) }
        if path == "/privacy/receipt" { return (200, ["consents": []]) }
        if path == "/privacy/rights-requests" { return (200, []) }
        if path.hasPrefix("/preferences/ui") { return (200, ["hiddenCards": []]) }
        if path == "/transactions/stats" {
            if ProcessInfo.processInfo.environment["FINFLOW_UI_FAILURE"] == "1" { return (503, ["message": "Servicio no disponible durante la prueba"]) }
            return (200, ["totalIncome": 3200000, "totalExpenses": 303000.5, "balance": 2896999.5, "savingsRate": 90.53,
                          "monthlyData": [["month": "2026-09", "income": 2800000, "expenses": 1640000], ["month": "2026-10", "income": 3100000, "expenses": 1950000], ["month": "2026-11", "income": 3200000, "expenses": 303000.5]],
                          "categoryData": [["category": "Alimentación", "amount": 303000.5, "percentage": 100]]])
        }
        if path == "/transactions", method == "GET" { return (200, transactions) }
        if path == "/transactions", method == "POST" {
            var row = body; row["id"] = nextID; nextID += 1
            transactions.insert(row, at: 0); return (200, row)
        }
        if path.hasPrefix("/transactions/"), let id = Int(path.split(separator: "/").last ?? "") {
            if method == "DELETE" { transactions.removeAll { $0["id"] as? Int == id }; return (200, [:]) }
            if method == "PUT" {
                var row = body; row["id"] = id
                transactions.removeAll { $0["id"] as? Int == id }; transactions.insert(row, at: 0); return (200, row)
            }
        }
        if path == "/categories" { return (200, categories) }
        if path == "/accounts" {
            return (200, [["id": 1, "name": "Cuenta principal", "type": "bank", "currency": "COP", "openingBalance": 500000, "balance": 3396999.5, "archived": false], ["id": 2, "name": "Efectivo", "type": "cash", "currency": "COP", "openingBalance": 80000, "balance": 80000, "archived": false]])
        }
        if path == "/accounts/transfers" { return (200, []) }
        if path == "/goals", method == "GET" { return (200, goals) }
        if path == "/goals", method == "POST" {
            var row = body; row["id"] = nextID; nextID += 1; row["status"] = "active"
            goals.append(row); return (200, row)
        }
        if path.hasSuffix("/contributions") { return (200, []) }
        if path == "/budgets" {
            return (200, [["id": 1, "categoryId": 2, "categoryName": "Alimentación", "year": 2026, "month": 11, "limitAmount": 600000, "spent": 303000.5, "remaining": 296999.5, "percentUsed": 51, "status": "ok", "currency": "COP"]])
        }
        if path == "/recurring" { return (200, [["id": 1, "title": "Internet del hogar", "amount": 85000, "type": "expense", "categoryId": 3, "dayOfMonth": 15, "nextDueDate": "2026-11-15", "active": true]]) }
        if path == "/planned-expenses" { return (200, [["id": 1, "title": "Matrícula universitaria", "amount": 800000, "categoryId": 3, "dueDate": "2026-12-01", "status": "pending"]]) }
        if path == "/ai/chat" { return (200, ["respuesta": "Podemos empezar por definir un presupuesto mensual y reservar una parte de tus ingresos para tu fondo de emergencia."]) }
        if path == "/billing/catalog" { return (200, ["currency": "COP", "checkoutEnabled": false, "offers": [["code": "MONTHLY", "title": "FinFlow Pro", "description": "Más posibilidades para tus finanzas", "originalCop": 15000, "priceCop": 15000, "savingsPercent": 0, "checkoutEnabled": false]]]) }
        if path == "/billing/me" { return (200, ["planCode": "FREE", "pro": false]) }
        return (501, ["message": "Ruta no implementada en el entorno de pruebas: \(method) \(path)"])
    }

    private func jsonBody(_ request: URLRequest) -> [String: Any] {
        var data = request.httpBody ?? Data()
        if data.isEmpty, let stream = request.httpBodyStream {
            stream.open(); defer { stream.close() }
            var buffer = [UInt8](repeating: 0, count: 4096)
            while stream.hasBytesAvailable {
                let count = stream.read(&buffer, maxLength: buffer.count)
                guard count > 0 else { break }; data.append(buffer, count: count)
            }
        }
        return (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
    }
}
#endif
