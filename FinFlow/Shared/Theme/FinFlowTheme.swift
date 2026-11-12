import SwiftUI
import UIKit

enum FinFlowTheme {
    // System-backed colors automatically adapt to light/dark appearance.
    static let background = Color(uiColor: .systemGroupedBackground)
    static let surface = Color(uiColor: .secondarySystemGroupedBackground)
    static let elevated = Color(uiColor: .tertiarySystemGroupedBackground)
    static let accent = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark ? UIColor(red: 0.84, green: 0.69, blue: 0.39, alpha: 1) : UIColor(red: 0.43, green: 0.31, blue: 0.12, alpha: 1)
    })
    static let gold = accent
    static let onAccent = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark ? UIColor(red: 0.04, green: 0.09, blue: 0.16, alpha: 1) : .white
    })
    static let mint = Color(red: 0.12, green: 0.66, blue: 0.45)
    static let danger = Color(red: 0.88, green: 0.20, blue: 0.25)
    static let secondaryText = Color.secondary
}

/// The drawer sets the rhythm: quick feedback, a gentle settle, no overshoot.
enum FinFlowMotion {
    static let press = Animation.easeOut(duration: 0.13)
    static let reveal = Animation.easeOut(duration: 0.22)
    static let panel = Animation.spring(response: 0.30, dampingFraction: 0.9)
}

struct FinFlowPressStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.98 : 1)
            .opacity(configuration.isPressed ? 0.82 : 1)
            .animation(reduceMotion ? nil : FinFlowMotion.press, value: configuration.isPressed)
    }
}

struct FinFlowScreenEntrance: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var visible = false

    func body(content: Content) -> some View {
        content
            .opacity(visible || reduceMotion ? 1 : 0)
            .offset(y: visible || reduceMotion ? 0 : 6)
            .onAppear {
                guard !visible else { return }
                withAnimation(reduceMotion ? nil : FinFlowMotion.reveal) { visible = true }
            }
    }
}

