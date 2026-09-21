#if os(iOS)
import SwiftUI
import UIKit

enum LiveGesturePhase {
    case began
    case changed
    case ended
}

/// The gesture surface of live mode.
///
/// SwiftUI can tell a pinch from a drag but not a one-finger drag from a
/// two-finger one, and live 3D turns on exactly that distinction: one finger
/// turns the model, two slide it. Three UIKit recognizers say it plainly, and
/// they report *incremental* deltas so the canvas can forward them straight to
/// the orbit camera without tracking a gesture origin.
struct LiveGestureView: UIViewRepresentable {
    /// Translation since the last callback, in points, with the number of
    /// touches the recognizer is configured for (1 or 2).
    var onPan: (CGSize, Int, LiveGesturePhase) -> Void
    /// Scale since the last callback (1 = unchanged).
    var onPinch: (CGFloat, LiveGesturePhase) -> Void
    var onTap: () -> Void
    var onDoubleTap: () -> Void

    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        view.backgroundColor = .clear
        let coordinator = context.coordinator

        let panOne = UIPanGestureRecognizer(target: coordinator, action: #selector(Coordinator.handlePan(_:)))
        panOne.minimumNumberOfTouches = 1
        panOne.maximumNumberOfTouches = 1

        let panTwo = UIPanGestureRecognizer(target: coordinator, action: #selector(Coordinator.handlePan(_:)))
        panTwo.minimumNumberOfTouches = 2
        panTwo.maximumNumberOfTouches = 2

        let pinch = UIPinchGestureRecognizer(target: coordinator, action: #selector(Coordinator.handlePinch(_:)))

        let doubleTap = UITapGestureRecognizer(target: coordinator, action: #selector(Coordinator.handleDoubleTap))
        doubleTap.numberOfTapsRequired = 2

        let singleTap = UITapGestureRecognizer(target: coordinator, action: #selector(Coordinator.handleTap))
        singleTap.numberOfTapsRequired = 1
        singleTap.require(toFail: doubleTap)

        for recognizer in [panOne, panTwo, pinch, doubleTap, singleTap] as [UIGestureRecognizer] {
            recognizer.delegate = coordinator
            view.addGestureRecognizer(recognizer)
        }
        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        context.coordinator.callbacks = self
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(callbacks: self)
    }

    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        var callbacks: LiveGestureView

        init(callbacks: LiveGestureView) {
            self.callbacks = callbacks
        }

        @objc func handlePan(_ recognizer: UIPanGestureRecognizer) {
            guard let phase = Self.phase(for: recognizer.state), let view = recognizer.view else { return }
            let translation = recognizer.translation(in: view)
            recognizer.setTranslation(.zero, in: view)
            // `numberOfTouches` is already 0 by the time the gesture ends, so
            // the recognizer's own configuration is what identifies it.
            let touches = recognizer.maximumNumberOfTouches
            callbacks.onPan(CGSize(width: translation.x, height: translation.y), touches, phase)
        }

        @objc func handlePinch(_ recognizer: UIPinchGestureRecognizer) {
            guard let phase = Self.phase(for: recognizer.state) else { return }
            let scale = recognizer.scale
            recognizer.scale = 1
            callbacks.onPinch(scale, phase)
        }

        @objc func handleTap() {
            callbacks.onTap()
        }

        @objc func handleDoubleTap() {
            callbacks.onDoubleTap()
        }

        /// Pinching while dragging with two fingers is one continuous motion,
        /// not a conflict.
        func gestureRecognizer(
            _ gestureRecognizer: UIGestureRecognizer,
            shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer
        ) -> Bool {
            true
        }

        private static func phase(for state: UIGestureRecognizer.State) -> LiveGesturePhase? {
            switch state {
            case .began: .began
            case .changed: .changed
            case .ended, .cancelled, .failed: .ended
            default: nil
            }
        }
    }
}
#endif
