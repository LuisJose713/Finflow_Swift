import SwiftUI
import UIKit

/// A directional native recognizer lets vertical lists keep their own scrolling.
/// The invisible anchor only scopes the recognizer; it never intercepts a tap.
struct DrawerPanGesture: UIViewRepresentable {
    var enabled: Bool
    var isOpen: Bool
    var drawerWidth: CGFloat
    var changed: (CGFloat) -> Void
    var ended: (Bool) -> Void
    var cancelled: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIView(context: Context) -> AnchorView {
        let view = AnchorView()
        view.isUserInteractionEnabled = false
        view.isAccessibilityElement = false
        view.attached = { [weak coordinator = context.coordinator] anchor in coordinator?.attach(anchor) }
        return view
    }

    func updateUIView(_ view: AnchorView, context: Context) {
        let resized = context.coordinator.configuration.drawerWidth != drawerWidth
        context.coordinator.configuration = self
        if resized { context.coordinator.pan.isEnabled = false }
        context.coordinator.attach(view)
        context.coordinator.pan.isEnabled = enabled
    }

    static func dismantleUIView(_ view: AnchorView, coordinator: Coordinator) { coordinator.detach() }

    final class AnchorView: UIView {
        var attached: ((AnchorView) -> Void)?
        override func didMoveToWindow() { super.didMoveToWindow(); attached?(self) }
    }

    @MainActor final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        var configuration: DrawerPanGesture
        weak var anchor: AnchorView?
        weak var controller: UIViewController?
        private var initiallyOpen = false
        private var width: CGFloat = 320
        private var tracking = false
        lazy var pan: UIPanGestureRecognizer = {
            let recognizer = UIPanGestureRecognizer(target: self, action: #selector(handle(_:)))
            recognizer.delegate = self
            recognizer.maximumNumberOfTouches = 1
            recognizer.cancelsTouchesInView = true
            return recognizer
        }()

        init(_ configuration: DrawerPanGesture) { self.configuration = configuration }

        func attach(_ anchor: AnchorView) {
            self.anchor = anchor
            guard anchor.window != nil else { detach(); return }
            var responder: UIResponder? = anchor
            while let current = responder, !(current is UIViewController) { responder = current.next }
            guard let controller = responder as? UIViewController else { return }
            if pan.view !== controller.view {
                pan.view?.removeGestureRecognizer(pan)
                controller.view.addGestureRecognizer(pan)
            }
            self.controller = controller
            pan.isEnabled = configuration.enabled
        }

        func detach() {
            pan.view?.removeGestureRecognizer(pan)
            controller = nil
            if tracking { tracking = false; configuration.cancelled() }
        }

        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
            guard configuration.enabled, let host = pan.view,
                  controller?.presentedViewController == nil,
                  let touchedView = touch.view, touchedView.isDescendant(of: host) else { return false }
            // The recognizer is installed on the hosting controller, not the
            // invisible SwiftUI anchor. That anchor can be resized or offset
            // during tab transitions; always hit-test in the host's coordinates.
            let point = touch.location(in: host)
            guard host.bounds.contains(point),
                  DrawerSwipePolicy.canStart(x: point.x, viewportWidth: host.bounds.width, isOpen: configuration.isOpen) else { return false }
            if !configuration.isOpen {
                var responder: UIResponder? = touchedView
                while let current = responder {
                    if let controller = current as? UIViewController,
                       (controller.navigationController?.viewControllers.count ?? 0) > 1 { return false }
                    responder = current.next
                }
            }
            var candidate: UIView? = touchedView
            while let view = candidate {
                // Text editing, sliders, horizontal content and pushed navigation
                // keep their gestures. A drag on a drawer row cancels its tap.
                if view is UITextField || view is UITextView || view is UISlider
                    || view.accessibilityTraits.contains(.adjustable) { return false }
                if !configuration.isOpen {
                    if view is UIControl || view.accessibilityTraits.contains(.button)
                        || view.accessibilityTraits.contains(.link) { return false }
                    if let scroll = view as? UIScrollView,
                       scroll.contentSize.width > scroll.bounds.width + 1 { return false }
                }
                if view === host { break }
                candidate = view.superview
            }
            return true
        }

        func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
            let translation = pan.translation(in: anchor)
            guard configuration.enabled,
                  DrawerSwipePolicy.isHorizontal(CGSize(width: translation.x, height: translation.y), isOpen: configuration.isOpen) else { return false }
            initiallyOpen = configuration.isOpen
            width = configuration.drawerWidth
            return true
        }

        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                               shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool {
            guard let scroll = other.view as? UIScrollView else { return false }
            return scroll.contentSize.width <= scroll.bounds.width + 1
        }

        @objc private func handle(_ recognizer: UIPanGestureRecognizer) {
            let dx = recognizer.translation(in: anchor).x
            switch recognizer.state {
            case .began, .changed:
                tracking = true
                configuration.changed(DrawerSwipePolicy.offset(translation: dx, width: width, isOpen: initiallyOpen))
            case .ended:
                tracking = false
                configuration.ended(DrawerSwipePolicy.destination(
                    translation: dx, velocity: recognizer.velocity(in: anchor).x,
                    width: width, isOpen: initiallyOpen))
            case .cancelled, .failed:
                if tracking { tracking = false; configuration.cancelled() }
            default: break
            }
        }
    }
}
