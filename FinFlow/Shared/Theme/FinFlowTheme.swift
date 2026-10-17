import SwiftUI
import UIKit

enum FinFlowTheme {
    // System-backed colors automatically adapt to light/dark appearance.
    static let background = Color(uiColor: .systemGroupedBackground)
    static let surface = Color(uiColor: .secondarySystemGroupedBackground)
    static let elevated = Color(uiColor: .tertiarySystemGroupedBackground)
    static let accent = Color(red: 0.42, green: 0.48, blue: 1.0)
    static let mint = Color(red: 0.12, green: 0.66, blue: 0.45)
    static let danger = Color(red: 0.88, green: 0.20, blue: 0.25)
    static let secondaryText = Color.secondary
}
