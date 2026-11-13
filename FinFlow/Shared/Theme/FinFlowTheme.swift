import SwiftUI
import UIKit

enum FinFlowTheme {
    // The same quiet navy and warm ivory as the FinFlow drawer.
    // Dynamic UIColors retain native appearance switching and system controls.
    static let background = adaptive(light: 0xF6F3ED, dark: 0x0B1220)
    static let surface = adaptive(light: 0xFFFDF8, dark: 0x0E192B)
    static let elevated = adaptive(light: 0xF0EBE2, dark: 0x1B2B43)
    static let action = adaptive(light: 0x0E192B, dark: 0xDCC29A)
    static let onAction = adaptive(light: 0xFFFDF8, dark: 0x0E192B)
    static let accent = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark ? UIColor(red: 0.863, green: 0.761, blue: 0.604, alpha: 1) : UIColor(red: 0.541, green: 0.408, blue: 0.216, alpha: 1)
    })
    static let gold = accent
    static let onAccent = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark ? UIColor(red: 0.04, green: 0.09, blue: 0.16, alpha: 1) : .white
    })
    static let mint = adaptive(light: 0x087A4B, dark: 0x4CC99B)
    static let danger = adaptive(light: 0xC22E45, dark: 0xFF7F8F)
    static let secondaryText = Color.secondary

    private static func adaptive(light: UInt32, dark: UInt32) -> Color {
        Color(uiColor: UIColor { traits in
            let hex = traits.userInterfaceStyle == .dark ? dark : light
            return UIColor(red: CGFloat((hex >> 16) & 255) / 255,
                           green: CGFloat((hex >> 8) & 255) / 255,
                           blue: CGFloat(hex & 255) / 255, alpha: 1)
        })
    }
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

