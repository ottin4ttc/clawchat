import SwiftUI
import UIKit

struct LongPressGestureOverlay: UIViewRepresentable {
    let minimumDuration: TimeInterval
    let onBegan: () -> Void
    let onDrag: (CGFloat) -> Void
    let onEnded: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onBegan: onBegan, onDrag: onDrag, onEnded: onEnded)
    }

    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        view.backgroundColor = .clear

        let longPress = UILongPressGestureRecognizer(
            target: context.coordinator,
            action: #selector(Coordinator.handleGesture(_:))
        )
        longPress.minimumPressDuration = minimumDuration
        longPress.cancelsTouchesInView = false
        longPress.delaysTouchesBegan = false
        view.addGestureRecognizer(longPress)

        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        context.coordinator.onBegan = onBegan
        context.coordinator.onDrag = onDrag
        context.coordinator.onEnded = onEnded
    }

    class Coordinator {
        var onBegan: () -> Void
        var onDrag: (CGFloat) -> Void
        var onEnded: () -> Void
        private var startLocation: CGPoint = .zero

        init(onBegan: @escaping () -> Void, onDrag: @escaping (CGFloat) -> Void, onEnded: @escaping () -> Void) {
            self.onBegan = onBegan
            self.onDrag = onDrag
            self.onEnded = onEnded
        }

        @objc func handleGesture(_ gesture: UILongPressGestureRecognizer) {
            switch gesture.state {
            case .began:
                startLocation = gesture.location(in: gesture.view)
                onBegan()
            case .changed:
                let current = gesture.location(in: gesture.view)
                let yOffset = current.y - startLocation.y
                onDrag(yOffset)
            case .ended, .cancelled, .failed:
                onEnded()
            default:
                break
            }
        }
    }
}
