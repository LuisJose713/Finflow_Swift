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
