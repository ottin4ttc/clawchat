import SwiftUI

@main
struct ClawOSApp: App {
    @State private var appState = AppState()
    @State private var isSplashDone = false

    var body: some Scene {
        WindowGroup {
            ZStack {
                ContentView()
                    .environment(appState)
                    .allowsHitTesting(!appState.showPairing)

                if !isSplashDone {
                    SplashView()
                        .environment(appState)
                        .transition(.opacity)
                        .zIndex(1)
                }

                PairingOverlay()
                    .environment(appState)
                    .zIndex(2)
            }
            .animation(.easeOut(duration: 0.4), value: isSplashDone)
            .onAppear {
                DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                    isSplashDone = true
                    checkPairingState()
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
        }
    }

    private func checkPairingState() {
        if appState.clawChatManager.linkState == .unpaired {
            withAnimation { appState.showPairing = true }
        }
    }
}
