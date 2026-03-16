import SwiftUI

struct SplashView: View {
    @Environment(AppState.self) private var appState
    @State private var rotation: Double = 0

    private let iconAnchor = UnitPoint(x: 0.178, y: 0.502)

    var body: some View {
        GeometryReader { geo in
            let logoSize: CGFloat = 180
            let offsetY = -geo.size.height * 0.08

            Color(.systemBackground)
                .ignoresSafeArea()
                .overlay(
                    ZStack {
                        // 只有纯黑色的文字部分，没有蓝色的六爪
                        Image("clawos_logo_text")
                            .resizable()
                            .scaledToFit()
                            .frame(width: logoSize, height: logoSize)

                        Image("clawos_icon_spin")
                            .resizable()
                            .renderingMode(.template)
                            .scaledToFit()
                            .frame(width: logoSize, height: logoSize)
                            .foregroundStyle(appState.currentVisualTheme.accent)
                            .rotationEffect(.degrees(rotation), anchor: iconAnchor)
                    }
                    .offset(y: offsetY)
                )
        }
        .onAppear {
            // 慢慢旋转一圈
            withAnimation(
                .easeInOut(duration: 2.0)
            ) {
                rotation = 360
            }
        }
    }
}

#Preview {
    SplashView()
        .environment(AppState())
}
