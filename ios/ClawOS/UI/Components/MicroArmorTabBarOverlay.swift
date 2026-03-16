import SwiftUI

struct MicroArmorTabBarOverlay: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        let theme = appState.currentVisualTheme

        VStack {
            Spacer()
            
            ZStack(alignment: .bottom) {
                // 左侧机甲角标与编号
                HStack(alignment: .bottom, spacing: 4) {
                    Path { path in
                        path.move(to: CGPoint(x: 0, y: 10))
                        path.addLine(to: CGPoint(x: 0, y: 0))
                        path.addLine(to: CGPoint(x: 10, y: 0))
                    }
                    .stroke(theme.accent.opacity(0.5), lineWidth: 1.5)
                    .frame(width: 10, height: 10)
                    
                    Text("EVA-00")
                        .font(.system(size: 8, weight: .bold, design: .monospaced))
                        .foregroundStyle(theme.accent.opacity(0.6))
                        .padding(.bottom, -2)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.leading, 24)
                .padding(.bottom, 88) // 悬浮在 Tab Bar 左上方

                // 右侧机甲角标与状态
                HStack(alignment: .bottom, spacing: 4) {
                    Text("SYNC.100")
                        .font(.system(size: 8, weight: .bold, design: .monospaced))
                        .foregroundStyle(theme.accent.opacity(0.6))
                        .padding(.bottom, -2)
                        
                    Path { path in
                        path.move(to: CGPoint(x: 10, y: 10))
                        path.addLine(to: CGPoint(x: 10, y: 0))
                        path.addLine(to: CGPoint(x: 0, y: 0))
                    }
                    .stroke(theme.accent.opacity(0.5), lineWidth: 1.5)
                    .frame(width: 10, height: 10)
                }
                .frame(maxWidth: .infinity, alignment: .trailing)
                .padding(.trailing, 24)
                .padding(.bottom, 88) // 悬浮在 Tab Bar 右上方
                
                // 底部极浅的装甲接缝线
                Rectangle()
                    .fill(
                        LinearGradient(
                            colors: [.clear, theme.accent.opacity(0.25), .clear],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .frame(height: 1)
                    .padding(.bottom, 12)
            }
        }
        .allowsHitTesting(false) // 绝对不能阻挡用户的点击交互
        .ignoresSafeArea(.keyboard)
    }
}
