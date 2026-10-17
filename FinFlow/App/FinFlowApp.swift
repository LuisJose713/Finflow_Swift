import SwiftUI

@main
struct FinFlowApp: App {
    @StateObject private var session = SessionStore()
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
                .preferredColorScheme(preferredScheme)
                .tint(FinFlowTheme.accent)
        }
    }
}
