import SwiftUI

struct ThemeBackgroundView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let theme = appState.currentVisualTheme
        let isDark = colorScheme == .dark

        ZStack {
            LinearGradient(
                colors: [theme.pageGradientTop, theme.pageGradientBottom],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            if let ambientAssetName = theme.ambientAssetName {
                Image(ambientAssetName)
                    .resizable()
                    .scaledToFill()
                    .opacity(theme.ambientOpacity)
                    .blur(radius: 0.5)
            }

            RadialGradient(
                colors: [theme.pageGlow.opacity(0.22), .clear],
                center: .topLeading,
                startRadius: 40,
                endRadius: 440
            )
            .blendMode(.plusLighter)

            LinearGradient(
                colors: [
                    (isDark ? Color.white.opacity(0.04) : Color.white.opacity(0.16)),
                    Color.clear,
                    (isDark ? Color.white.opacity(0.02) : Color.white.opacity(0.06)),
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        }
        .ignoresSafeArea()
    }
}
