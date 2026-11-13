import SwiftUI
@preconcurrency import UserNotifications

@MainActor
final class AppNavigationStore: ObservableObject {
    static let shared = AppNavigationStore()
    enum Destination: String { case dashboard, transactions }
    @Published private(set) var pendingDestination: Destination?

    func open(_ value: String) {
        guard let destination = Destination(rawValue: value) else { return }
        pendingDestination = destination
    }
    func takeDestination() -> Destination? {
        defer { pendingDestination = nil }
        return pendingDestination
    }
    func clear() { pendingDestination = nil }
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
