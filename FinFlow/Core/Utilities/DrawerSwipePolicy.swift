import Foundation

/// Shared rules for the native pan recognizer, independent of SwiftUI rendering.
enum DrawerSwipePolicy {
    static func canStart(x: CGFloat, viewportWidth: CGFloat, isOpen: Bool) -> Bool {
        isOpen || (x >= 24 && x <= viewportWidth)
    }

    static func isHorizontal(_ translation: CGSize, isOpen: Bool) -> Bool {
        let dx = translation.width
        return abs(dx) > 0 && abs(dx) >= abs(translation.height) * 1.35
            && (isOpen ? dx < 0 : dx > 0)
    }

    static func offset(translation: CGFloat, width: CGFloat, isOpen: Bool) -> CGFloat {
        min(0, max(-width, (isOpen ? 0 : -width) + translation))
    }

    static func destination(translation: CGFloat, velocity: CGFloat, width: CGFloat, isOpen: Bool) -> Bool {
        if abs(translation) >= 20 && abs(velocity) >= 350 { return velocity > 0 }
        let distance = min(88, width * 0.28)
        return isOpen ? translation > -distance : translation >= distance
    }
}
