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
