import SwiftUI

struct GlassCard<Content: View>: View {
    var cornerRadius: CGFloat = AppTheme.Radius.lg
    @ViewBuilder var content: () -> Content

    var body: some View {
        content()
            .padding(AppTheme.Spacing.lg)
            .frame(maxWidth: .infinity, alignment: .leading)
            .glassEffect(.regular, in: .rect(cornerRadius: cornerRadius))
    }
}
