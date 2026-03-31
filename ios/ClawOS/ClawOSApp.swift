import SwiftUI
import UIKit

enum KeyboardPrewarmer {
    static let isEnabled = true

    static func warmUp() {
        guard isEnabled else { return }
        guard let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene else { return }

        let prewarmWindow = UIWindow(windowScene: windowScene)
        prewarmWindow.windowLevel = .init(rawValue: -1)
        prewarmWindow.frame = CGRect(x: 0, y: -200, width: 1, height: 1)

        let field = UITextField()
        field.autocorrectionType = .no
        prewarmWindow.rootViewController = UIViewController()
        prewarmWindow.rootViewController?.view.addSubview(field)
        prewarmWindow.isHidden = false

        field.becomeFirstResponder()

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            field.resignFirstResponder()
            prewarmWindow.isHidden = true
        }
    }
}

enum AppLaunchPresentation {
    static func initialVisibility(hasLoggedIn: Bool) -> (
        showSplash: Bool,
        showLogin: Bool,
        isSplashDone: Bool
    ) {
        return (showSplash: false, showLogin: true, isSplashDone: false)
    }
}

@main
struct ClawOSApp: App {
    @Environment(\.scenePhase) private var scenePhase
    @State private var appState = AppState()
    @State private var isSplashDone = false
    @State private var showSplash = false
    @State private var showLogin: Bool?
    @State private var shouldPromptForPairingAfterLinkStart = false
    @AppStorage("clawos_logged_in_v4") private var hasLoggedIn = false

    var body: some Scene {
        WindowGroup {
            ZStack {
                ContentView()
                    .environment(appState)
                    .allowsHitTesting(!appState.showPairing && appState.effectiveSettingsProgress == 0)
                    .opacity(isSplashDone ? 1 : 0)
                    .blur(radius: 10 * max(0, (appState.effectiveSettingsProgress - 0.3) / 0.7))
                    .gesture(
                        DragGesture()
                            .onChanged { value in
                                guard !appState.showSettingsDrawer else { return }
                                let startX = value.startLocation.x
                                let screenWidth = UIScreen.main.bounds.width
                                if startX > screenWidth - 40 {
                                    let translation = -value.translation.width
                                    if translation > 0 {
                                        appState.interactiveSettingsProgress = min(1.0, translation / screenWidth)
                                    }
                                }
                            }
                            .onEnded { value in
                                guard !appState.showSettingsDrawer else { return }
                                let startX = value.startLocation.x
                                let screenWidth = UIScreen.main.bounds.width
                                if startX > screenWidth - 40 {
                                    let velocity = -value.velocity.width
                                    let translation = -value.translation.width
                                    if velocity > 500 || translation > screenWidth * 0.3 {
                                        let generator = UIImpactFeedbackGenerator(style: .medium)
                                        generator.impactOccurred()
                                        withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                                            appState.interactiveSettingsProgress = nil
                                            appState.showSettingsDrawer = true
                                        }
                                    } else {
                                        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                                            appState.interactiveSettingsProgress = nil
                                            appState.showSettingsDrawer = false
                                        }
                                    }
                                }
                            }
                    )

                if showSplash {
                    SplashView()
                        .environment(appState)
                        .zIndex(1)
                }

                if showLogin == true {
                    LoginView {
                        handleLoginComplete()
                    }
                    .environment(appState)
                    .zIndex(2)
                }

                PairingOverlay()
                    .environment(appState)
                    .zIndex(3)

                SettingsDrawerOverlay()
                    .environment(appState)
                    .zIndex(4)
            }
            .background {
                LinearGradient(
                    colors: [
                        appState.currentVisualTheme.pageGradientTop,
                        appState.currentVisualTheme.pageGradientBottom,
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .ignoresSafeArea()
            }
            .onAppear {
                guard showLogin == nil else { return }

                let visibility = AppLaunchPresentation.initialVisibility(hasLoggedIn: hasLoggedIn)
                showSplash = visibility.showSplash
                showLogin = visibility.showLogin
                isSplashDone = visibility.isSplashDone

                if visibility.showSplash {
                    finishSplashAfterDelay()
                }
            }
            .task {
                appState.clawChatManager.appState = appState
                await appState.clawChatManager.autoConnect()
                if isSplashDone {
                    checkPairingState()
                }
            }
            .onChange(of: appState.clawChatManager.linkState) { _, newState in
                if case .connected = newState {
                    shouldPromptForPairingAfterLinkStart = false
                    withAnimation { appState.showPairing = false }
                    return
                }

                if case .unpaired = newState {
                    appState.clearAllGatewayData()
                }

                guard isSplashDone, showLogin != true else { return }
                if PairingPresentationBehavior.shouldAutoPresent(for: newState) {
                    withAnimation { appState.showPairing = true }
                }
            }
            .onChange(of: isSplashDone) { _, done in
                guard done else { return }
                if shouldPromptForPairingAfterLinkStart {
                    presentPairingAfterLinkStartIfNeeded()
                } else {
                    checkPairingState()
                }
            }
            .onOpenURL { url in
                handleDeepLink(url)
            }
            .onChange(of: scenePhase) { _, phase in
                guard phase == .background else { return }
                appState.flushAllPendingPersistence()
            }
        }
    }

    private func handleLoginComplete() {
        hasLoggedIn = true
        shouldPromptForPairingAfterLinkStart = true

        showSplash = true

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            withAnimation(.easeOut(duration: 0.35)) {
                showLogin = false
            }
        }

        finishSplashAfterDelay()
    }

    private func finishSplashAfterDelay() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.2) {
            withAnimation(.easeOut(duration: 0.4)) {
                showSplash = false
                isSplashDone = true
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                KeyboardPrewarmer.warmUp()
            }
        }
    }

    private func checkPairingState() {
        if PairingPresentationBehavior.shouldAutoPresent(for: appState.clawChatManager.linkState) {
            withAnimation { appState.showPairing = true }
        }
    }

    private func presentPairingAfterLinkStartIfNeeded() {
        guard shouldPromptForPairingAfterLinkStart else { return }
        defer { shouldPromptForPairingAfterLinkStart = false }

        if PairingPresentationBehavior.shouldPresentSheet(
            for: appState.clawChatManager.linkState,
            isSplashDone: isSplashDone,
            isLoginVisible: showLogin == true
        ) {
            withAnimation { appState.showPairing = true }
        }
    }

    private func handleDeepLink(_ url: URL) {
        guard let parsed = PairingDeepLink.parse(url) else { return }
        withAnimation { appState.showPairing = true }

        switch parsed {
        case .relay(let relay, let code):
            NotificationCenter.default.post(
                name: .clawChatDeepLink,
                object: nil,
                userInfo: ["relay": relay, "code": code]
            )
        case .gateway(let gatewayUrl, let token, let bootstrap):
            var info: [String: Any] = ["gatewayUrl": gatewayUrl, "gatewayToken": token]
            if let bootstrap { info["bootstrapToken"] = bootstrap }
            NotificationCenter.default.post(
                name: .clawChatDeepLink,
                object: nil,
                userInfo: info
            )
        }
    }
}

extension Notification.Name {
    static let clawChatDeepLink = Notification.Name("clawChatDeepLink")
}
