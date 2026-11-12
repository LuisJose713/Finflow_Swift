import SwiftUI
import UIKit
@preconcurrency import UserNotifications

@main
struct FinFlowApp: App {
    @StateObject private var session = SessionStore()
    @StateObject private var preferences = UiPreferencesStore()
    @AppStorage("finflow.appearance") private var appearance = "system"

    private var preferredScheme: ColorScheme? {
        switch appearance {
        case "light": return .light
        case "dark": return .dark
        default: return nil
        }
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(session)
                .environmentObject(preferences)
                .task(id: session.user?.id) {
                    await preferences.load(userID: session.user?.id)
                    await FinFlowDailyReminders.sync(authenticated: session.isAuthenticated)
                }
                .preferredColorScheme(preferredScheme)
                .tint(FinFlowTheme.accent)
                .privacySensitive()
                .background { AppPrivacyShield().frame(width: 0, height: 0) }
        }
    }
}

/// Place the cover on the scene's window so it also covers presented forms and
/// share sheets. A SwiftUI overlay behind a modal would leave that modal visible
/// in the app switcher. This does not prevent screenshots while the app is active.
private struct AppPrivacyShield: UIViewRepresentable {
    func makeUIView(context: Context) -> PrivacyObserverView { PrivacyObserverView(frame: .zero) }
    func updateUIView(_ view: PrivacyObserverView, context: Context) {}
    static func dismantleUIView(_ view: PrivacyObserverView, coordinator: ()) {
        view.stopObserving()
    }
}

@MainActor
private final class PrivacyObserverView: UIView {
    private var cover: UIView?

    override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = false
        isAccessibilityElement = false
        NotificationCenter.default.addObserver(self, selector: #selector(hideContent(_:)),
                                               name: UIScene.willDeactivateNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(hideContent(_:)),
                                               name: UIScene.didEnterBackgroundNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(showContent(_:)),
                                               name: UIScene.didActivateNotification, object: nil)
    }

    required init?(coder: NSCoder) { return nil }

    @objc private func hideContent(_ notification: Notification) {
        guard let scene = notification.object as? UIWindowScene,
              scene === window?.windowScene, let window else { return }
        if let cover {
            window.bringSubviewToFront(cover)
            return
        }
        let shield = UIView(frame: window.bounds)
        shield.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        shield.backgroundColor = .systemGroupedBackground
        shield.accessibilityViewIsModal = true
        let title = UILabel()
        title.text = "FinFlow\nContenido oculto"
        title.font = .preferredFont(forTextStyle: .title2)
        title.adjustsFontForContentSizeCategory = true
        title.textAlignment = .center
        title.numberOfLines = 0
        title.translatesAutoresizingMaskIntoConstraints = false
        shield.addSubview(title)
        NSLayoutConstraint.activate([
            title.centerXAnchor.constraint(equalTo: shield.centerXAnchor),
            title.centerYAnchor.constraint(equalTo: shield.centerYAnchor),
            title.leadingAnchor.constraint(greaterThanOrEqualTo: shield.leadingAnchor, constant: 24),
            title.trailingAnchor.constraint(lessThanOrEqualTo: shield.trailingAnchor, constant: -24)
        ])
        window.addSubview(shield)
        cover = shield
    }

    @objc private func showContent(_ notification: Notification) {
        guard let scene = notification.object as? UIWindowScene,
              scene === window?.windowScene else { return }
        removeCover()
    }

    func stopObserving() {
        NotificationCenter.default.removeObserver(self)
        removeCover()
    }

    private func removeCover() {
        cover?.removeFromSuperview()
        cover = nil
    }
}


/// Two daily, local-time reminders. The app icon is the official FinFlow icon.
/// The 16:00 notification never guesses or exposes private financial amounts.
@MainActor
enum FinFlowDailyReminders {
    static let preferenceKey = "finflow.dailyRemindersEnabled"
    private static let ids = ["finflow.daily.10", "finflow.daily.16"]

    static func setEnabled(_ enabled: Bool, authenticated: Bool) async {
        UserDefaults.standard.set(enabled, forKey: preferenceKey)
        await sync(authenticated: authenticated)
    }

    static func sync(authenticated: Bool) async {
        let center = UNUserNotificationCenter.current()
        guard authenticated else {
            center.removePendingNotificationRequests(withIdentifiers: ids)
            return
        }
        // Default to opt-in through the system authorization prompt on first login.
        if UserDefaults.standard.object(forKey: preferenceKey) == nil {
            UserDefaults.standard.set(true, forKey: preferenceKey)
        }
        guard UserDefaults.standard.bool(forKey: preferenceKey) else {
            center.removePendingNotificationRequests(withIdentifiers: ids)
            return
        }
        let settings = await center.notificationSettings()
        switch settings.authorizationStatus {
        case .notDetermined:
            let approved = (try? await center.requestAuthorization(options: [.alert, .sound])) ?? false
            guard approved else {
                UserDefaults.standard.set(false, forKey: preferenceKey)
                return
            }
        case .authorized, .provisional, .ephemeral:
            break
        default:
            center.removePendingNotificationRequests(withIdentifiers: ids)
            return
        }

        center.removePendingNotificationRequests(withIdentifiers: ids)
        let reminders: [(String, Int, String, String)] = [
            ("finflow.daily.10", 10, "Es hora de registrar tus movimientos",
             "Mantén tus finanzas al día. Registra tus ingresos y gastos."),
            ("finflow.daily.16", 16, "¿Cuánto has gastado hoy?",
             "Consulta el resumen de tus gastos de hoy en FinFlow.")
        ]
        for (id, hour, title, body) in reminders {
            let content = UNMutableNotificationContent()
            content.title = title
            content.body = body
            content.sound = .default
            content.userInfo = ["finflow.destination": hour == 10 ? "transactions" : "dashboard"]
            let trigger = UNCalendarNotificationTrigger(
                dateMatching: DateComponents(hour: hour, minute: 0),
                repeats: true
            )
            try? await center.add(UNNotificationRequest(
                identifier: id, content: content, trigger: trigger
            ))
        }
    }
}
