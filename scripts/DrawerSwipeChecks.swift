import Foundation

@main struct DrawerSwipeChecks {
    static func main() {
        for width in [CGFloat(320), 375, 430, 768] {
            precondition(!DrawerSwipePolicy.canStart(x: 23, viewportWidth: width, isOpen: false))
            precondition(DrawerSwipePolicy.canStart(x: 60, viewportWidth: width, isOpen: false))
            precondition(!DrawerSwipePolicy.canStart(x: 180, viewportWidth: width, isOpen: false))
        }
        precondition(DrawerSwipePolicy.isHorizontal(CGSize(width: 30, height: 5), isOpen: false))
        precondition(!DrawerSwipePolicy.isHorizontal(CGSize(width: 5, height: 30), isOpen: false))
        precondition(!DrawerSwipePolicy.isHorizontal(CGSize(width: -30, height: 1), isOpen: false))
        precondition(DrawerSwipePolicy.isHorizontal(CGSize(width: -30, height: 1), isOpen: true))
        precondition(DrawerSwipePolicy.offset(translation: 40, width: 320, isOpen: false) == -280)
        precondition(DrawerSwipePolicy.offset(translation: 500, width: 320, isOpen: false) == 0)
        precondition(DrawerSwipePolicy.offset(translation: -500, width: 320, isOpen: true) == -320)
        precondition(!DrawerSwipePolicy.destination(translation: 40, velocity: 0, width: 320, isOpen: false))
        precondition(DrawerSwipePolicy.destination(translation: 32, velocity: 600, width: 320, isOpen: false))
        precondition(DrawerSwipePolicy.destination(translation: 95, velocity: 0, width: 320, isOpen: false))
        precondition(!DrawerSwipePolicy.destination(translation: -95, velocity: 0, width: 320, isOpen: true))
        precondition(DrawerSwipePolicy.destination(translation: -120, velocity: 600, width: 320, isOpen: true))
        precondition(!DrawerSwipePolicy.destination(translation: 15, velocity: 900, width: 320, isOpen: false))
        print("Drawer checks passed: direction, back edge, tracking, clamping, distance, flick and reversal")
    }
}
