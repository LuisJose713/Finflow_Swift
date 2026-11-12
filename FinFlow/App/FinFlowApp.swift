import SwiftUI
import UIKit

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
                .task(id: session.user?.id) { await preferences.load(userID: session.user?.id) }
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
