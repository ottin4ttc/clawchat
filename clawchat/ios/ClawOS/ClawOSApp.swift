import SwiftUI
import UIKit

enum KeyboardPrewarmer {
    static func warmUp() {
        guard let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
              let window = windowScene.windows.first else { return }

        let field = UITextField(frame: CGRect(x: 0, y: -200, width: 1, height: 1))
        field.autocorrectionType = .no
        window.addSubview(field)
        field.becomeFirstResponder()

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            field.resignFirstResponder()
            field.removeFromSuperview()
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
    @AppStorage("clawos_logged_in_v4") private var hasLoggedIn = false

    var body: some Scene {
        WindowGroup {
            ZStack {
                ContentView()
                    .environment(appState)
                    .allowsHitTesting(!appState.showPairing)
                    .opacity(isSplashDone ? 1 : 0)

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
                    withAnimation { appState.showPairing = false }
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
                checkPairingState()
            }
        }
    }

    private func checkPairingState() {
        if appState.clawChatManager.linkState == .unpaired {
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
        case .gateway(let gatewayUrl, let token):
            NotificationCenter.default.post(
                name: .clawChatDeepLink,
                object: nil,
                userInfo: ["gatewayUrl": gatewayUrl, "gatewayToken": token]
            )
        }
    }
}

extension Notification.Name {
    static let clawChatDeepLink = Notification.Name("clawChatDeepLink")
}
