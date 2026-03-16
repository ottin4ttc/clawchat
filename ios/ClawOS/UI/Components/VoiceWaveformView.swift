import SwiftUI
import UIKit

public enum SiriGlowMode: Equatable {
    case fullScreen
    case keyboardTop(frame: CGRect)
}

public enum SiriGlowLayout {
    public static let keyboardHeightThreshold: CGFloat = 80
    public static let keyboardHorizontalInset: CGFloat = 14
    public static let keyboardGlowHeight: CGFloat = 72
    public static let keyboardGlowLift: CGFloat = 34

    public static func mode(for screenBounds: CGRect, keyboardFrame: CGRect?) -> SiriGlowMode {
        guard let keyboardFrame else { return .fullScreen }

        let intersection = screenBounds.intersection(keyboardFrame)
        guard !intersection.isNull,
              !intersection.isEmpty,
              intersection.height >= keyboardHeightThreshold,
              abs(intersection.maxY - screenBounds.maxY) <= 2 else {
            return .fullScreen
        }

        return .keyboardTop(frame: keyboardGlowFrame(for: screenBounds, keyboardFrame: intersection))
    }

    public static func keyboardGlowFrame(for screenBounds: CGRect, keyboardFrame: CGRect) -> CGRect {
        let width = max(0, screenBounds.width - keyboardHorizontalInset * 2)
        let y = max(0, keyboardFrame.minY - keyboardGlowLift)

        return CGRect(
            x: keyboardHorizontalInset,
            y: y,
            width: width,
            height: keyboardGlowHeight
        )
    }
}

struct SiriGlowBorderView: View {
    var isActive: Bool
    var dimmed: Bool = false
    var keyboardFrame: CGRect? = nil

    private let siriColors: [Color] = [
        Color(red: 1.0, green: 0.42, blue: 0.55),
        Color(red: 0.78, green: 0.35, blue: 0.96),
        Color(red: 0.40, green: 0.50, blue: 1.0),
        Color(red: 0.30, green: 0.82, blue: 0.95),
        Color(red: 0.40, green: 0.50, blue: 1.0),
        Color(red: 0.78, green: 0.35, blue: 0.96),
        Color(red: 1.0, green: 0.55, blue: 0.40),
        Color(red: 1.0, green: 0.42, blue: 0.55),
    ]

    private let screenCornerRadius: CGFloat = 47

    var body: some View {
        Group {
            if isActive {
                TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { timeline in
                    let elapsed = timeline.date.timeIntervalSinceReferenceDate
                    let angle = Angle.degrees(elapsed.truncatingRemainder(dividingBy: 5) / 5 * 360)

                    Canvas { context, size in
                        let screenBounds = CGRect(origin: .zero, size: size)
                        let mode = SiriGlowLayout.mode(for: screenBounds, keyboardFrame: keyboardFrame)

                        switch mode {
                        case .fullScreen:
                            drawFullScreenGlow(in: &context, size: size, angle: angle)
                        case .keyboardTop(let glowFrame):
                            drawKeyboardGlow(in: &context, rect: glowFrame)
                        }
                    }
                    .opacity(dimmed ? 0.3 : 1.0)
                }
                .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.3), value: isActive)
        .animation(.easeOut(duration: 0.15), value: dimmed)
        .allowsHitTesting(false)
        .ignoresSafeArea()
    }

    private func drawFullScreenGlow(
        in context: inout GraphicsContext,
        size: CGSize,
        angle: Angle
    ) {
        let rect = CGRect(origin: .zero, size: size)
        let path = RoundedRectangle(cornerRadius: screenCornerRadius, style: .continuous)
            .path(in: rect)

        let gradient = Gradient(colors: siriColors)
        let center = CGPoint(x: size.width / 2, y: size.height / 2)
        let shading = GraphicsContext.Shading.conicGradient(
            gradient,
            center: center,
            angle: angle
        )

        var bloomCtx = context
        bloomCtx.addFilter(.blur(radius: 32))
        bloomCtx.opacity = 0.6
        bloomCtx.stroke(path, with: shading, lineWidth: 14)

        var midCtx = context
        midCtx.addFilter(.blur(radius: 12))
        midCtx.opacity = 0.8
        midCtx.stroke(path, with: shading, lineWidth: 8)

        var coreCtx = context
        coreCtx.addFilter(.blur(radius: 2))
        coreCtx.stroke(path, with: shading, lineWidth: 4)
    }

    private func drawKeyboardGlow(in context: inout GraphicsContext, rect: CGRect) {
        let gradient = Gradient(colors: siriColors)
        let shading = GraphicsContext.Shading.linearGradient(
            gradient,
            startPoint: CGPoint(x: rect.minX, y: rect.midY),
            endPoint: CGPoint(x: rect.maxX, y: rect.midY)
        )
        let path = SiriKeyboardGlowShape().path(in: rect)

        var bloomCtx = context
        bloomCtx.addFilter(.blur(radius: 28))
        bloomCtx.opacity = 0.58
        bloomCtx.stroke(path, with: shading, lineWidth: 16)

        var midCtx = context
        midCtx.addFilter(.blur(radius: 10))
        midCtx.opacity = 0.82
        midCtx.stroke(path, with: shading, lineWidth: 9)

        var coreCtx = context
        coreCtx.addFilter(.blur(radius: 1.5))
        coreCtx.stroke(path, with: shading, lineWidth: 4)

        let centerBloomWidth = min(rect.width * 0.42, 220)
        let centerBloomRect = CGRect(
            x: rect.midX - centerBloomWidth / 2,
            y: rect.minY - 6,
            width: centerBloomWidth,
            height: rect.height * 0.55
        )
        let centerBloomPath = Capsule().path(in: centerBloomRect)

        var fillCtx = context
        fillCtx.addFilter(.blur(radius: 24))
        fillCtx.opacity = 0.28
        fillCtx.fill(centerBloomPath, with: shading)
    }
}

private struct SiriKeyboardGlowShape: Shape {
    func path(in rect: CGRect) -> Path {
        let radius = min(rect.height * 0.42, 28)
        var path = Path()

        path.move(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.minY + radius))
        path.addArc(
            center: CGPoint(x: rect.minX + radius, y: rect.minY + radius),
            radius: radius,
            startAngle: .degrees(180),
            endAngle: .degrees(270),
            clockwise: false
        )
        path.addLine(to: CGPoint(x: rect.maxX - radius, y: rect.minY))
        path.addArc(
            center: CGPoint(x: rect.maxX - radius, y: rect.minY + radius),
            radius: radius,
            startAngle: .degrees(270),
            endAngle: .degrees(0),
            clockwise: false
        )
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))

        return path
    }
}

/// Presents the Siri glow in a dedicated overlay window so it can stay above the system keyboard.
struct SiriGlowWindowPresenter: UIViewRepresentable {
    var isActive: Bool
    var dimmed: Bool

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeUIView(context: Context) -> UIWindowReportingView {
        let view = UIWindowReportingView()
        view.backgroundColor = .clear
        view.isUserInteractionEnabled = false
        view.onWindowSceneChange = { windowScene in
            context.coordinator.updateWindow(
                for: windowScene,
                isActive: isActive,
                dimmed: dimmed
            )
        }
        return view
    }

    func updateUIView(_ uiView: UIWindowReportingView, context: Context) {
        uiView.onWindowSceneChange = { windowScene in
            context.coordinator.updateWindow(
                for: windowScene,
                isActive: isActive,
                dimmed: dimmed
            )
        }

        DispatchQueue.main.async {
            context.coordinator.updateWindow(
                for: uiView.window?.windowScene,
                isActive: isActive,
                dimmed: dimmed
            )
        }
    }

    static func dismantleUIView(_ uiView: UIWindowReportingView, coordinator: Coordinator) {
        coordinator.teardown()
    }

    final class Coordinator {
        private var overlayWindow: PassThroughWindow?
        private var hostingController: UIHostingController<SiriGlowBorderView>?
        private var keyboardObservers: [NSObjectProtocol] = []
        private var keyboardFrame: CGRect?
        private var isActive = false
        private var dimmed = false

        func updateWindow(for windowScene: UIWindowScene?, isActive: Bool, dimmed: Bool) {
            guard let windowScene else {
                teardown()
                return
            }

            self.isActive = isActive
            self.dimmed = dimmed

            if overlayWindow?.windowScene !== windowScene {
                teardown()

                let controller = UIHostingController(
                    rootView: SiriGlowBorderView(
                        isActive: isActive,
                        dimmed: dimmed,
                        keyboardFrame: keyboardFrame
                    )
                )
                controller.view.backgroundColor = .clear
                controller.view.isUserInteractionEnabled = false

                let window = PassThroughWindow(windowScene: windowScene)
                window.rootViewController = controller
                window.backgroundColor = .clear
                window.windowLevel = .alert + 1

                overlayWindow = window
                hostingController = controller
            }

            ensureKeyboardObservers()
            syncRootView()
        }

        private func ensureKeyboardObservers() {
            guard keyboardObservers.isEmpty else { return }

            let center = NotificationCenter.default
            keyboardObservers = [
                center.addObserver(
                    forName: UIResponder.keyboardWillChangeFrameNotification,
                    object: nil,
                    queue: .main
                ) { [weak self] notification in
                    self?.handleKeyboardFrameChange(notification)
                },
                center.addObserver(
                    forName: UIResponder.keyboardWillHideNotification,
                    object: nil,
                    queue: .main
                ) { [weak self] _ in
                    self?.keyboardFrame = nil
                    self?.syncRootView()
                }
            ]
        }

        private func handleKeyboardFrameChange(_ notification: Notification) {
            guard let overlayWindow,
                  let frameValue = notification.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? NSValue else {
                return
            }

            let keyboardFrameInScreen = frameValue.cgRectValue
            let keyboardFrameInWindow = overlayWindow.convert(keyboardFrameInScreen, from: nil)
            let bounds = overlayWindow.bounds
            let intersection = bounds.intersection(keyboardFrameInWindow)

            if keyboardFrameInWindow.minY >= bounds.maxY - 1 || intersection.isNull || intersection.height < 44 {
                keyboardFrame = nil
            } else {
                keyboardFrame = intersection
            }

            syncRootView()
        }

        private func syncRootView() {
            hostingController?.rootView = SiriGlowBorderView(
                isActive: isActive,
                dimmed: dimmed,
                keyboardFrame: keyboardFrame
            )
            if let windowScene = overlayWindow?.windowScene {
                overlayWindow?.frame = windowScene.screen.bounds
            }
            overlayWindow?.isHidden = !isActive
        }

        func teardown() {
            let center = NotificationCenter.default
            keyboardObservers.forEach(center.removeObserver)
            keyboardObservers.removeAll()
            overlayWindow?.isHidden = true
            overlayWindow?.rootViewController = nil
            overlayWindow = nil
            hostingController = nil
            keyboardFrame = nil
        }
    }
}

final class UIWindowReportingView: UIView {
    var onWindowSceneChange: ((UIWindowScene?) -> Void)?

    override func didMoveToWindow() {
        super.didMoveToWindow()
        onWindowSceneChange?(window?.windowScene)
    }
}

final class PassThroughWindow: UIWindow {
    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        nil
    }
}

#Preview {
    ZStack {
        Color(.systemBackground).ignoresSafeArea()
        Text("Hello World")
            .font(.title)
        SiriGlowBorderView(isActive: true)
    }
}
