import SwiftUI
import Foundation
@preconcurrency import UserNotifications

struct AssistantTransactionDraft: Equatable {
    let id = UUID()
    let type: String
    let title: String?
    let amount: Double?
}

@MainActor
final class AppNavigationStore: ObservableObject {
    static let shared = AppNavigationStore()
    enum Destination: String { case dashboard, transactions, createTransaction }
    @Published private(set) var pendingDestination: Destination?
    @Published private(set) var pendingAssistantDraft: AssistantTransactionDraft?

    func open(_ value: String) {
        guard let destination = Destination(rawValue: value) else { return }
        pendingDestination = destination
    }
    func openTransactionDraft(type: String, title: String?, amount: Double?) {
        let safeType = type == "income" ? "income" : "expense"
        let safeTitle = title.map { String($0.trimmingCharacters(in: .whitespacesAndNewlines).prefix(255)) }
        let safeAmount = (amount?.isFinite == true && (amount ?? 0) > 0) ? amount : nil
        pendingAssistantDraft = AssistantTransactionDraft(type: safeType, title: safeTitle, amount: safeAmount)
        pendingDestination = .createTransaction
    }
    func takeAssistantDraft() -> AssistantTransactionDraft? {
        defer { pendingAssistantDraft = nil }
        return pendingAssistantDraft
    }
    func takeDestination() -> Destination? {
        defer { pendingDestination = nil }
        return pendingDestination
    }
    func clear() { pendingDestination = nil; pendingAssistantDraft = nil }
}


/**
 * Shared Siri write boundary. Prepare is strictly read-only; commit is called
 * exactly once, and only after Siri has received an explicit confirmation.
 * No automatic retries after a network timeout (the write may have succeeded).
 */
@MainActor
enum VoiceTransactionRegistration {
    struct Prepared {
        let ownerID: Int
        let request: CreateTransactionRequest
        let categoryName: String

        var summary: String {
            let kind = request.type == "income" ? "ingreso" : "gasto"
            let money = request.amount.formatted(.currency(code: "COP").locale(Locale(identifier: "es_CO")))
            return "¿Confirmas registrar un \\(kind) de \\(money) por \\(request.description) en \\(categoryName)?"
        }
    }

    static func prepare(type: String, title: String, amount: Double,
                        categoryName: String) async throws -> Prepared {
        let cleanedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanedCategory = categoryName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard (2...255).contains(cleanedTitle.count),
              amount.isFinite, amount > 0, amount <= 1_000_000_000_000,
              (amount * 100).rounded() == amount * 100 else {
            throw APIError.server("Indica un título válido y un monto en COP con máximo dos decimales.")
        }
        guard !cleanedCategory.isEmpty else {
            throw APIError.server("Indica en qué categoría quieres registrar el movimiento.")
        }
        guard TokenStore.shared.read("token")?.isEmpty == false else {
            throw APIError.unauthorized
        }
        // Backend validates the actual JWT. Never accept an owner ID from Siri.
        let user: AppUser = try await APIClient.shared.request("/auth/me")
        let categories: [FinanceCategory] = try await APIClient.shared.request("/categories")

        func normalized(_ text: String) -> String {
            text.trimmingCharacters(in: .whitespacesAndNewlines)
                .folding(options: [.caseInsensitive, .diacriticInsensitive],
                         locale: Locale(identifier: "es_CO"))
        }
        let matching = categories.filter { item in
            item.type.lowercased() == type && normalized(item.name) == normalized(cleanedCategory)
        }
        guard matching.count == 1, let category = matching.first else {
            throw APIError.server("No encontramos una categoría única llamada \\(cleanedCategory). Revisa tus categorías en FinFlow.")
        }
        let request = CreateTransactionRequest(
            description: cleanedTitle, amount: amount, type: type,
            categoryId: category.id, date: DateFormatters.isoDay.string(from: Date()),
            notes: nil
        )
        return Prepared(ownerID: user.id, request: request, categoryName: category.name)
    }

    static func commit(_ prepared: Prepared) async throws -> FinanceTransaction {
        guard TokenStore.shared.read("token")?.isEmpty == false,
              TokenStore.shared.read("userId") == String(prepared.ownerID) else {
            throw APIError.unauthorized
        }
        // Exactly one POST after confirmation. An ambiguous timeout is reported,
        // never automatically resent or reported as a confirmed success.
        return try await APIClient.shared.request(
            "/transactions", method: "POST", body: prepared.request
        )
    }
}

final class FinFlowNotificationDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        return true
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter,
                                            willPresent notification: UNNotification,
                                            withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .list, .sound])
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter,
                                            didReceive response: UNNotificationResponse,
                                            withCompletionHandler completionHandler: @escaping () -> Void) {
        if response.actionIdentifier == UNNotificationDefaultActionIdentifier,
           let value = response.notification.request.content.userInfo["finflow.destination"] as? String {
            Task { @MainActor in AppNavigationStore.shared.open(value) }
        }
        completionHandler()
    }
}
