import SwiftUI

enum AppVisualThemeID: String, CaseIterable, Identifiable, Codable {
    case neutral
    case eva00
    case eva01
    case eva02

    var id: String { rawValue }

    var alternateIconName: String? {
        switch self {
        case .neutral: nil
        case .eva00: "AltIcon-EVA00"
        case .eva01: "AltIcon-EVA01"
        case .eva02: "AltIcon-EVA02"
        }
    }
}

struct AppVisualTheme {
    let id: AppVisualThemeID
    let displayName: String
    let accent: Color
    let pageGradientTop: Color
    let pageGradientBottom: Color
    let pageGlow: Color
    let ambientAssetName: String?
    let ambientOpacity: Double
    let bannerAssetName: String?
    let bannerGradient: [Color]
    let tabBarFill: Color
    let softFill: Color
    let softStroke: Color
    let rowFill: Color
    let rowStroke: Color
    let cardTint: Color
    let cardStroke: Color
    let logoTint: Color
    let themeLogoAssetName: String?

    static func theme(for id: AppVisualThemeID, colorScheme: ColorScheme = .light) -> AppVisualTheme {
        let isDark = colorScheme == .dark
        switch id {
        case .neutral:
            return AppVisualTheme(
                id: .neutral,
                displayName: "默认",
                accent: Color(.label),
                pageGradientTop: Color(.systemBackground),
                pageGradientBottom: Color(.systemGray6),
                pageGlow: isDark ? Color.white.opacity(0.06) : Color.white,
                ambientAssetName: nil,
                ambientOpacity: 0,
                bannerAssetName: nil,
                bannerGradient: [Color(.systemGray3), Color(.systemGray5), Color(.systemGray6)],
                tabBarFill: isDark ? Color.black.opacity(0.85) : Color.white.opacity(0.9),
                softFill: Color(.systemGray6),
                softStroke: Color(.systemGray5),
                rowFill: isDark ? Color.white.opacity(0.08) : Color.white.opacity(0.72),
                rowStroke: Color(.systemGray5).opacity(0.65),
                cardTint: isDark ? Color.white.opacity(0.08) : Color.white.opacity(0.06),
                cardStroke: isDark ? Color.white.opacity(0.15) : Color.white.opacity(0.4),
                logoTint: Color(.systemGray3),
                themeLogoAssetName: nil
            )

        case .eva00:
            if isDark {
                return AppVisualTheme(
                    id: .eva00,
                    displayName: "零号机",
                    // 主题色：高亮霓虹蓝，用于关键操作和气泡
                    accent: Color(red: 0.45, green: 0.75, blue: 1.0),
                    // 信息层背景：极深的灰蓝色，保证文字对比度
                    pageGradientTop: Color(white: 0.08),
                    pageGradientBottom: Color(white: 0.02),
                    // 主题光晕：蓝色微光
                    pageGlow: Color(red: 0.2, green: 0.5, blue: 0.9).opacity(0.15),
                    ambientAssetName: "theme_eva00_ambient",
                    ambientOpacity: 0.4, // 调高透明度以展示霓虹线条
                    bannerAssetName: "theme_eva00_banner",
                    bannerGradient: [
                        Color(white: 0.15),
                        Color(white: 0.10),
                        Color(white: 0.05),
                    ],
                    // 信息层卡片：中性深灰，带微弱透明度
                    tabBarFill: Color(white: 0.1).opacity(0.9),
                    softFill: Color.white.opacity(0.08),
                    softStroke: Color.white.opacity(0.15),
                    rowFill: Color.white.opacity(0.05),
                    rowStroke: Color.white.opacity(0.10),
                    cardTint: Color.white.opacity(0.05),
                    cardStroke: Color.white.opacity(0.12),
                    // Logo 颜色：蓝色半透明
                    logoTint: Color(red: 0.45, green: 0.75, blue: 1.0).opacity(0.6),
                    themeLogoAssetName: "theme_eva00_logo"
                )
            }
            return AppVisualTheme(
                id: .eva00,
                displayName: "零号机",
                accent: Color(red: 0.63, green: 0.76, blue: 0.88),
                pageGradientTop: Color(red: 0.965, green: 0.985, blue: 0.995),
                pageGradientBottom: Color(red: 0.925, green: 0.95, blue: 0.978),
                pageGlow: Color(red: 0.98, green: 0.9, blue: 0.76),
                ambientAssetName: "theme_eva00_ambient",
                ambientOpacity: 0.18,
                bannerAssetName: "theme_eva00_banner",
                bannerGradient: [
                    Color(red: 0.89, green: 0.93, blue: 0.97),
                    Color(red: 0.83, green: 0.88, blue: 0.94),
                    Color(red: 0.78, green: 0.84, blue: 0.9),
                ],
                tabBarFill: Color.white.opacity(0.82),
                softFill: Color(red: 0.965, green: 0.978, blue: 0.988),
                softStroke: Color(red: 0.86, green: 0.9, blue: 0.94),
                rowFill: Color.white.opacity(0.62),
                rowStroke: Color(red: 0.84, green: 0.88, blue: 0.93).opacity(0.8),
                cardTint: Color(red: 0.86, green: 0.92, blue: 0.98).opacity(0.14),
                cardStroke: Color.white.opacity(0.62),
                logoTint: Color(red: 0.74, green: 0.83, blue: 0.92),
                themeLogoAssetName: "theme_eva00_logo"
            )

        case .eva01:
            if isDark {
                return AppVisualTheme(
                    id: .eva01,
                    displayName: "初号机",
                    // 主题色：高亮霓虹紫
                    accent: Color(red: 0.75, green: 0.45, blue: 1.0),
                    // 信息层背景：极深的灰紫色
                    pageGradientTop: Color(white: 0.08),
                    pageGradientBottom: Color(white: 0.02),
                    // 主题光晕：紫色微光
                    pageGlow: Color(red: 0.5, green: 0.2, blue: 0.8).opacity(0.15),
                    ambientAssetName: "theme_eva01_ambient",
                    ambientOpacity: 0.4,
                    bannerAssetName: "theme_eva01_banner",
                    bannerGradient: [
                        Color(white: 0.15),
                        Color(white: 0.10),
                        Color(white: 0.05),
                    ],
                    // 信息层卡片：中性深灰
                    tabBarFill: Color(white: 0.1).opacity(0.9),
                    softFill: Color.white.opacity(0.08),
                    softStroke: Color.white.opacity(0.15),
                    rowFill: Color.white.opacity(0.05),
                    rowStroke: Color.white.opacity(0.10),
                    cardTint: Color.white.opacity(0.05),
                    cardStroke: Color.white.opacity(0.12),
                    logoTint: Color(red: 0.75, green: 0.45, blue: 1.0).opacity(0.6),
                    themeLogoAssetName: "theme_eva01_logo"
                )
            }
            return AppVisualTheme(
                id: .eva01,
                displayName: "初号机",
                accent: Color(red: 0.56, green: 0.27, blue: 0.78),
                pageGradientTop: Color(red: 0.97, green: 0.96, blue: 0.99),
                pageGradientBottom: Color(red: 0.94, green: 0.92, blue: 0.97),
                pageGlow: Color(red: 0.72, green: 0.55, blue: 0.92),
                ambientAssetName: "theme_eva01_ambient",
                ambientOpacity: 0.15,
                bannerAssetName: "theme_eva01_banner",
                bannerGradient: [
                    Color(red: 0.90, green: 0.86, blue: 0.96),
                    Color(red: 0.82, green: 0.76, blue: 0.92),
                    Color(red: 0.74, green: 0.66, blue: 0.88),
                ],
                tabBarFill: Color(red: 0.96, green: 0.94, blue: 0.99).opacity(0.88),
                softFill: Color(red: 0.96, green: 0.95, blue: 0.99),
                softStroke: Color(red: 0.84, green: 0.78, blue: 0.92),
                rowFill: Color.white.opacity(0.62),
                rowStroke: Color(red: 0.82, green: 0.76, blue: 0.90).opacity(0.8),
                cardTint: Color(red: 0.80, green: 0.68, blue: 0.96).opacity(0.14),
                cardStroke: Color.white.opacity(0.62),
                logoTint: Color(red: 0.68, green: 0.52, blue: 0.86),
                themeLogoAssetName: "theme_eva01_logo"
            )

        case .eva02:
            if isDark {
                return AppVisualTheme(
                    id: .eva02,
                    displayName: "贰号机",
                    // 主题色：高亮霓虹红
                    accent: Color(red: 1.0, green: 0.45, blue: 0.4),
                    // 信息层背景：极深的灰红色
                    pageGradientTop: Color(white: 0.08),
                    pageGradientBottom: Color(white: 0.02),
                    // 主题光晕：红色微光
                    pageGlow: Color(red: 0.8, green: 0.2, blue: 0.1).opacity(0.15),
                    ambientAssetName: "theme_eva02_ambient",
                    ambientOpacity: 0.4,
                    bannerAssetName: "theme_eva02_banner",
                    bannerGradient: [
                        Color(white: 0.15),
                        Color(white: 0.10),
                        Color(white: 0.05),
                    ],
                    // 信息层卡片：中性深灰
                    tabBarFill: Color(white: 0.1).opacity(0.9),
                    softFill: Color.white.opacity(0.08),
                    softStroke: Color.white.opacity(0.15),
                    rowFill: Color.white.opacity(0.05),
                    rowStroke: Color.white.opacity(0.10),
                    cardTint: Color.white.opacity(0.05),
                    cardStroke: Color.white.opacity(0.12),
                    logoTint: Color(red: 1.0, green: 0.45, blue: 0.4).opacity(0.6),
                    themeLogoAssetName: "theme_eva02_logo"
                )
            }
            return AppVisualTheme(
                id: .eva02,
                displayName: "贰号机",
                accent: Color(red: 0.88, green: 0.28, blue: 0.22),
                pageGradientTop: Color(red: 0.995, green: 0.965, blue: 0.96),
                pageGradientBottom: Color(red: 0.98, green: 0.93, blue: 0.92),
                pageGlow: Color(red: 0.96, green: 0.72, blue: 0.42),
                ambientAssetName: "theme_eva02_ambient",
                ambientOpacity: 0.16,
                bannerAssetName: "theme_eva02_banner",
                bannerGradient: [
                    Color(red: 0.97, green: 0.89, blue: 0.87),
                    Color(red: 0.94, green: 0.82, blue: 0.78),
                    Color(red: 0.90, green: 0.74, blue: 0.70),
                ],
                tabBarFill: Color(red: 0.99, green: 0.96, blue: 0.95).opacity(0.88),
                softFill: Color(red: 0.99, green: 0.96, blue: 0.95),
                softStroke: Color(red: 0.92, green: 0.80, blue: 0.78),
                rowFill: Color.white.opacity(0.62),
                rowStroke: Color(red: 0.90, green: 0.78, blue: 0.76).opacity(0.8),
                cardTint: Color(red: 0.96, green: 0.72, blue: 0.68).opacity(0.14),
                cardStroke: Color.white.opacity(0.62),
                logoTint: Color(red: 0.86, green: 0.48, blue: 0.42),
                themeLogoAssetName: "theme_eva02_logo"
            )
        }
    }
}
