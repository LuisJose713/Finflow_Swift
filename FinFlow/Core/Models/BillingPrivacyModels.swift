import Foundation

// Server-authoritative billing and privacy models shared by iPhone and iPad.
// Never assign Pro access or mark a consent locally.
struct PrivacyPolicy: Decodable {
    let version: String
    let ready: Bool
    let controllerName: String
    let contactEmail: String
    let contactAddress: String
    let contactPhone: String
    let effectiveDate: String
}
struct PrivacyStatus: Decodable {
    let accepted: Bool
    let version: String
    let policyReady: Bool
}
struct PrivacyConsentInput: Encodable {
    let accepted: Bool
    let policyVersion: String
    let marketingConsent: Bool
}
struct PrivacyConsentResult: Decodable {
    let accepted: Bool
    let version: String
}
struct PrivacyRightsInput: Encodable {
    let type: String
    let description: String
}
struct PrivacyRightsResult: Decodable {
    let status: String
    let message: String
}
struct BillingCatalog: Decodable {
    let currency: String
    let checkoutEnabled: Bool
    let offers: [BillingOffer]
}
struct BillingOffer: Decodable, Identifiable {
    let code: String
    let title: String
    let description: String
    let originalCop: Int
    let priceCop: Int
    let promoCode: String?
    let promoTitle: String?
    let savingsPercent: Int
    let checkoutEnabled: Bool
    var id: String { code }
}
struct BillingEntitlement: Decodable {
    let planCode: String
    let pro: Bool
    let source: String?
    // validUntil intentionally omitted while Spring SQL Timestamp serialization is not stable.
}
struct BillingPlan: Codable, Identifiable {
    let code: String
    var title: String
    var description: String
    var priceCop: Int
    var active: Bool
    var sortOrder: Int
    var id: String { code }
}
struct BillingPromotion: Decodable, Identifiable {
    let code: String
    let title: String
    let planCode: String
    let discountType: String
    let discountValue: Int
    let startsAt: String
    let endsAt: String
    let maxRedemptions: Int?
    let redemptionCount: Int
    let active: Bool
    let published: Bool
    var id: String { code }
}
struct BillingPromotionInput: Encodable {
    let code: String
    let title: String
    let planCode: String
    let discountType: String
    let discountValue: Int
    let startsAt: String
    let endsAt: String
    let maxRedemptions: Int?
    let active: Bool
    let published: Bool
}
struct BillingGrantInput: Encodable {
    let userId: Int
    let planCode: String
    let reason: String
}
struct BillingGrantResult: Decodable {
    let status: String
    let userId: Int
    let planCode: String
}
struct ProfileUpdateInput: Encodable {
    let name: String
    let email: String
    let currentPassword: String
}
struct ProfileUpdateResult: Decodable {
    let status: String
    let logoutRequired: Bool
    let emailChanged: Bool
}
struct EmailChallengeInput: Encodable {
    let newEmail: String
    let currentPassword: String
}
struct EmailChallengeResult: Decodable {
    let status: String
    let expiresInSeconds: Int
}
struct EmailConfirmInput: Encodable {
    let code: String
}
struct EmailConfirmResult: Decodable {
    let status: String
    let logoutRequired: Bool?
    let attemptsRemaining: Int?
}
enum BillingFormatting {
    static func cop(_ amount: Int) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.locale = Locale(identifier: "es_CO")
        formatter.currencyCode = "COP"
        formatter.maximumFractionDigits = 0
        return formatter.string(from: NSNumber(value: amount)) ?? "$\(amount)"
    }
    static func isoUTC(_ date: Date) -> String {
        ISO8601DateFormatter().string(from: date)
    }
    static func readISO(_ value: String) -> Date {
        ISO8601DateFormatter().date(from: value) ?? .now
    }
}
