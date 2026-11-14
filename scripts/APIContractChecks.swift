import Foundation

@main
struct APIContractChecks {
    static func decode<T: Decodable>(_ type: T.Type, _ json: String) throws -> T {
        try JSONDecoder().decode(type, from: Data(json.utf8))
    }
    static func main() throws {
        let boundary = ISO8601DateFormatter().date(from: "2026-12-01T02:30:00Z")!
        precondition(DateFormatters.calendarDayFormatter(in: TimeZone(identifier: "America/Bogota")!).string(from: boundary) == "2026-11-30")
        precondition(DateFormatters.calendarDayFormatter(in: TimeZone(identifier: "Asia/Tokyo")!).string(from: boundary) == "2026-12-01")
        precondition(DateFormatters.isoDay.timeZone == TimeZone.current)
        let legacy = try decode(AuthResponse.self, #"{"token":"test-token","user":{"id":1,"email":"test@example.invalid","name":"Test"}}"#)
        precondition(legacy.refreshToken == nil && !legacy.user.isAdmin)
        let renewed = try decode(AuthResponse.self, #"{"token":"new-test-token","refreshToken":"opaque-test-refresh","user":{"id":1,"email":"test@example.invalid","name":"Test","role":"ADMIN"}}"#)
        precondition(renewed.refreshToken != nil && renewed.user.isAdmin)
        let catalog = try decode(BillingCatalog.self, #"{"currency":"COP","checkoutEnabled":false,"offers":[{"code":"MONTHLY","title":"Pro","description":"Test","originalCop":15000,"priceCop":12000,"promoCode":"TEST","promoTitle":"Oferta","savingsPercent":20,"checkoutEnabled":false}]}"#)
        precondition(catalog.offers[0].priceCop == 12000 && !catalog.checkoutEnabled)
        let entitlement = try decode(BillingEntitlement.self, #"{"planCode":"FREE","pro":false}"#)
        precondition(entitlement.validUntil == nil)
        let promotion = try decode(BillingPromotion.self, #"{"code":"TEST","title":"Test","planCode":"YEARLY","discountType":"PERCENT","discountValue":20,"startsAt":"2026-11-01T00:00:00Z","endsAt":"2026-12-01T00:00:00Z","maxRedemptions":null,"redemptionCount":0,"active":true,"published":false}"#)
        precondition(promotion.maxRedemptions == nil && !promotion.published)
        let transaction = try decode(FinanceTransaction.self, #"{"id":7,"description":"Test","amount":12500.50,"type":"expense","categoryId":2,"accountId":9,"date":"2026-11-12T00:00:00","currency":"COP","status":"pending"}"#)
        precondition(transaction.amount == 12500.50 && transaction.status == "pending")
        var input = CreateTransactionRequest(description: transaction.description, amount: transaction.amount, type: transaction.type, categoryId: transaction.categoryId, date: "2026-11-12", notes: nil)
        input.status = transaction.status ?? "completed"
        let wire = try JSONSerialization.jsonObject(with: JSONEncoder().encode(input)) as! [String: Any]
        precondition(wire["status"] as? String == "pending" && wire["currency"] as? String == "COP")
        print("Shared API contracts verified: legacy login, renewal, plans, promotions and pending movements.")
    }
}
