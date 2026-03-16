import SwiftUI

extension View {
    func avatarStyle(size: CGFloat = AppTheme.avatarSize, cornerRadius: CGFloat? = nil) -> some View {
        self
            .frame(width: size, height: size)
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius ?? size / 2))
    }
}
