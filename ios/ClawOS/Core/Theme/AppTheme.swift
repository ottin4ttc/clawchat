import SwiftUI

enum AppTheme {
    static let primary = Color(.label)
    static let success = Color(.secondaryLabel)
    static let danger = Color(.label)
    static let warning = Color(.tertiaryLabel)

    static let bubble = Color(.label)
    static let bubbleText = Color(.systemBackground)

    enum Spacing {
        static let xs: CGFloat = 4
        static let sm: CGFloat = 8
        static let md: CGFloat = 12
        static let lg: CGFloat = 16
        static let xl: CGFloat = 24
        static let xxl: CGFloat = 32
    }

    enum Radius {
        static let sm: CGFloat = 8
        static let md: CGFloat = 12
        static let lg: CGFloat = 16
        static let xl: CGFloat = 24
    }

    static let sidebarWidth: CGFloat = 72
    static let avatarSize: CGFloat = 48
    static let largeAvatarSize: CGFloat = 84
    static let bannerHeight: CGFloat = 180
}

extension AgentStatus {
    var color: Color {
        switch self {
        case .online: Color(.label)
        case .idle: Color(.tertiaryLabel)
        case .dnd: Color(.secondaryLabel)
        case .offline: Color(.quaternaryLabel)
        }
    }
}
