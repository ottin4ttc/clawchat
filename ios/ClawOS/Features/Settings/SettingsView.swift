import SwiftUI
import ClawChatKit

enum LegalDocumentKind {
    case privacyPolicy
    case termsOfService
}

struct LegalDocumentSection: Identifiable, Equatable {
    let title: String
    let body: String

    var id: String { title }
}

struct LegalDocumentContent: Equatable {
    let title: String
    let summary: String
    let effectiveDate: String
    let sections: [LegalDocumentSection]
}

enum LegalDocumentContentProvider {
    static let appName = "ClawOS"
    static let operatorName = "ClawOS 团队"
    static let effectiveDate = "2026年3月26日"

    static func document(for kind: LegalDocumentKind) -> LegalDocumentContent {
        switch kind {
        case .privacyPolicy:
            privacyPolicy
        case .termsOfService:
            termsOfService
        }
    }

    private static var privacyPolicy: LegalDocumentContent {
        LegalDocumentContent(
            title: "隐私政策",
            summary: """
            欢迎使用 \(appName)。本隐私政策说明我们在你使用 AI 会话、Gateway 配对、头像和本地设置等功能时，如何收集、使用、存储和保护相关信息。
            """,
            effectiveDate: effectiveDate,
            sections: [
                LegalDocumentSection(
                    title: "我们收集的信息",
                    body: """
                    1. 你主动提供的信息：包括你输入的消息、Agent 配置、Gateway 地址、配对信息，以及你主动上传的头像、图片或其他内容。
                    2. 设备与本地数据：包括登录状态、会话历史、主题设置、已选择模型、缓存图片，以及为保持连接安全而生成或保存的设备标识。
                    3. 权限信息：当你主动使用相关功能时，应用可能请求麦克风、语音识别或照片访问权限。
                    4. 运行与诊断信息：为排查崩溃、连接异常和性能问题，我们可能处理必要的错误日志、状态信息和基础网络诊断数据。
                    """
                ),
                LegalDocumentSection(
                    title: "我们如何使用信息",
                    body: """
                    我们使用上述信息来提供消息会话、Gateway 连接、设备配对、个性化设置与头像管理等功能，并用于保存你的本地偏好、提升稳定性与安全性，以及在适用法律要求范围内履行合规义务。
                    """
                ),
                LegalDocumentSection(
                    title: "第三方服务与数据共享",
                    body: """
                    \(appName) 不会以出售个人信息为目的向第三方提供你的数据。
                    当你主动连接第三方 Gateway、Relay 或由其配置的模型服务时，你提交的消息、附件、连接标识及相关请求数据可能会由这些服务处理，并适用它们各自的隐私政策。
                    此外，应用可能调用 Apple 提供的系统能力，例如 Keychain、照片选择器、语音识别或网络服务，以实现对应功能。
                    """
                ),
                LegalDocumentSection(
                    title: "数据存储与安全",
                    body: """
                    你的大部分偏好、会话和缓存内容会保存在你的设备本地。用于配对、凭证或设备身份的敏感信息会尽量存储在系统安全能力（如 Keychain）中。
                    我们会采取合理措施保护数据安全，但你仍应自行确保所连接 Gateway 的网络环境、访问控制和传输协议安全。
                    """
                ),
                LegalDocumentSection(
                    title: "你的权利与选择",
                    body: """
                    你可以随时删除本地会话、移除头像、断开 Gateway 连接，或通过卸载应用清除本地存储数据。
                    对于由第三方 Gateway 或模型服务处理的数据，请直接向相应服务提供方行使访问、更正、删除或撤回同意等权利。
                    """
                ),
                LegalDocumentSection(
                    title: "未成年人保护",
                    body: """
                    如你未满适用法律规定的年龄，请在监护人陪同和同意下使用本应用。我们不以明知方式主动收集未成年人的敏感信息。
                    """
                ),
                LegalDocumentSection(
                    title: "政策更新与联系我们",
                    body: """
                    我们可能根据产品功能、法律要求或运营变化更新本政策。更新后的版本会在应用内展示并标注生效日期。
                    若你对本政策有疑问，可通过应用后续公布的官方联系渠道与 \(operatorName) 联系。
                    """
                )
            ]
        )
    }

    private static var termsOfService: LegalDocumentContent {
        LegalDocumentContent(
            title: "服务条款",
            summary: """
            欢迎使用 \(appName)。你访问或使用本应用，即表示你已阅读、理解并同意遵守以下服务条款；如你不同意，请停止使用本应用及相关服务。
            """,
            effectiveDate: effectiveDate,
            sections: [
                LegalDocumentSection(
                    title: "服务说明",
                    body: """
                    \(appName) 提供 AI 会话、Gateway 配对与连接、Agent 管理、头像设置和个性化配置等功能。应用内部分能力依赖你自行选择并连接的 Gateway、Relay 或第三方模型服务。
                    """
                ),
                LegalDocumentSection(
                    title: "使用资格与连接安全",
                    body: """
                    你应确保自己具备使用本服务的法律资格，并对自己提供的连接信息、账号凭证、设备安全和使用行为负责。
                    你应妥善保管与 Gateway、Relay 或其他第三方服务相关的访问方式，不得冒用、盗用或未经授权访问他人资源。
                    """
                ),
                LegalDocumentSection(
                    title: "可接受使用规则",
                    body: """
                    你不得利用本服务从事任何违法、侵权、骚扰、诈骗、传播恶意代码、攻击系统、规避安全限制或侵犯他人合法权益的行为。
                    你也不得将本服务用于生成、传播或协助传播适用法律禁止的内容。
                    """
                ),
                LegalDocumentSection(
                    title: "用户内容与 AI 生成内容",
                    body: """
                    你对自己输入、上传、配置或分享的内容负责，并保证其来源合法且不侵犯第三方权利。
                    为向你提供功能，你授予我们在必要范围内处理这些内容的权限。AI 生成内容可能存在不准确、不完整或不适合特定场景的情况，重要决策前请你自行核验并独立判断。
                    """
                ),
                LegalDocumentSection(
                    title: "知识产权",
                    body: """
                    除用户依法享有权利的内容外，\(appName) 应用程序本身及其界面设计、文本、图形、代码和相关标识受知识产权法律保护。未经许可，你不得复制、反向工程、再发布或商业化利用。
                    """
                ),
                LegalDocumentSection(
                    title: "服务可用性与变更",
                    body: """
                    我们可根据产品演进、维护、安全或合规要求，对功能、界面、支持方式或可用性进行更新、限制、暂停或终止。
                    对于因网络条件、设备环境、第三方 Gateway 或模型服务异常导致的中断、延迟或失败，我们不保证服务始终连续、稳定或无错误。
                    """
                ),
                LegalDocumentSection(
                    title: "免责声明与责任限制",
                    body: """
                    在适用法律允许的最大范围内，本服务按“现状”和“可用”基础提供。我们不对适销性、特定用途适用性、连续可用性或结果准确性作明示或默示保证。
                    对于因你使用或无法使用本服务、依赖 AI 输出、连接第三方 Gateway 或模型服务、或因第三方行为导致的间接、附带、特殊或后果性损失，我们在法律允许范围内不承担责任。
                    """
                ),
                LegalDocumentSection(
                    title: "条款更新与终止",
                    body: """
                    我们可能更新本条款，并在应用内展示最新版本及生效日期。更新后你继续使用本服务，即视为接受更新后的条款。
                    如你违反本条款或适用法律，我们有权在必要时限制、暂停或终止你对相关功能的访问。你也可以随时停止使用本服务并卸载应用。
                    """
                ),
                LegalDocumentSection(
                    title: "适用法律与争议处理",
                    body: """
                    本条款受适用法律约束。因本条款或本服务引起的争议，双方应优先通过友好协商解决；协商不成的，按适用法律和有管辖权的争议解决机构处理。
                    """
                ),
                LegalDocumentSection(
                    title: "联系我们",
                    body: """
                    如你对本条款有疑问、建议或投诉，可通过应用后续公布的官方联系渠道与 \(operatorName) 联系。
                    """
                )
            ]
        )
    }
}

struct LegalDocumentSheet: View {
    let document: LegalDocumentContent
    let onClose: () -> Void

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(document.title)
                            .font(.title2.weight(.bold))
                            .foregroundStyle(Color(.label))
                        Text("生效日期：\(document.effectiveDate)")
                            .font(.footnote)
                            .foregroundStyle(Color(.secondaryLabel))
                        Text(verbatim: document.summary)
                            .font(.body)
                            .foregroundStyle(Color(.label))
                            .lineSpacing(4)
                    }

                    ForEach(document.sections) { section in
                        VStack(alignment: .leading, spacing: 8) {
                            Text(section.title)
                                .font(.headline)
                                .foregroundStyle(Color(.label))
                            Text(verbatim: section.body)
                                .font(.body)
                                .foregroundStyle(Color(.secondaryLabel))
                                .lineSpacing(5)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(16)
                        .background(
                            Color(.secondarySystemGroupedBackground),
                            in: RoundedRectangle(cornerRadius: 16, style: .continuous)
                        )
                    }
                }
                .padding(20)
            }
            .background(Color(.systemBackground))
            .navigationTitle(document.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("完成", action: onClose)
                }
            }
        }
    }
}

// MARK: - Settings View

struct SettingsView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @AppStorage("isDarkMode") private var isDarkMode = false
    @State private var showLinkStart = false
    @State private var showPrivacyPolicy = false
    @State private var showTermsOfService = false

    private var theme: AppVisualTheme { appState.currentVisualTheme }

    private var currentAgent: Agent? {
        appState.selectedAgent
    }

    private let bottomSafeAreaSpacing: CGFloat = 12

    private var settingsHeader: some View {
        HStack {
            Button { dismiss() } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(theme.accent)
                    .frame(width: 36, height: 36)
                    .contentShape(Circle())
            }

            Spacer()

            Text("设置")
                .font(.system(size: 17, weight: .semibold))

            Spacer()

            Color.clear
                .frame(width: 36, height: 36)
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .padding(.bottom, 4)
    }

    var body: some View {
        VStack(spacing: 0) {
            settingsHeader

            ScrollView(showsIndicators: false) {
                LazyVStack(alignment: .leading, spacing: 28) {
                    profileCard
                    sectionBlock(title: "通用设置", cells: generalCells)
                    sectionBlock(title: "Gateway 连接", cells: connectionCells)
                    sectionBlock(title: "法律与隐私", cells: legalCells)
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 20)
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            Color.clear
                .frame(height: bottomSafeAreaSpacing)
                .allowsHitTesting(false)
        }
        .background {
            LinearGradient(
                colors: [theme.pageGradientTop, theme.pageGradientBottom],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .navigationBar)
        .toolbar(.hidden, for: .tabBar)
        .background(InteractivePopGestureEnabler())
        .sheet(isPresented: $showLinkStart) {
            LoginView { showLinkStart = false }
                .environment(appState)
                .presentationDetents([.large])
                .presentationDragIndicator(.hidden)
                .presentationBackground(Color(.systemBackground))
        }
        .sheet(isPresented: $showPrivacyPolicy) {
            LegalDocumentSheet(
                document: LegalDocumentContentProvider.document(for: .privacyPolicy),
                onClose: { showPrivacyPolicy = false }
            )
            .presentationDetents([.medium, .large])
        }
        .sheet(isPresented: $showTermsOfService) {
            LegalDocumentSheet(
                document: LegalDocumentContentProvider.document(for: .termsOfService),
                onClose: { showTermsOfService = false }
            )
            .presentationDetents([.medium, .large])
        }
    }

    // MARK: - Profile Card

    private var profileCard: some View {
        Button { showLinkStart = true } label: {
            HStack(spacing: 14) {
                Image(systemName: "person.crop.circle.fill")
                    .resizable()
                    .frame(width: 52, height: 52)
                    .foregroundStyle(theme.accent.opacity(0.6))

                VStack(alignment: .leading, spacing: 3) {
                    Text("LINK START")
                        .font(.system(size: 17, weight: .bold, design: .monospaced))
                        .foregroundStyle(Color(.label))
                    Text("点击进入 ClawOS")
                        .font(.system(size: 13))
                        .foregroundStyle(Color(.secondaryLabel))
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Color(.tertiaryLabel))
            }
            .padding(16)
            .background(cardBackground, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    // MARK: - Section Block

    private func sectionBlock(title: String, cells: [SettingsCellDescriptor]) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title)
                .font(.system(size: 20, weight: .bold))
                .foregroundStyle(Color(.label))
                .padding(.leading, 16)
                .padding(.top, 16)
                .padding(.bottom, 8)

            ForEach(Array(cells.enumerated()), id: \.element.id) { index, cell in
                if index > 0 {
                    Divider().padding(.leading, 52)
                }
                cellRow(cell)
            }

            Spacer().frame(height: 4)
        }
        .background(cardBackground, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    // MARK: - Cell Row

    @ViewBuilder
    private func cellRow(_ cell: SettingsCellDescriptor) -> some View {
        switch cell.kind {
        case .navigation(let destination):
            NavigationLink { destination } label: {
                cellContent(cell)
            }
        case .toggle(let binding):
            HStack(spacing: 0) {
                cellContent(cell, showsRightSpace: false)
                Toggle("", isOn: binding)
                    .labelsHidden()
                    .tint(theme.accent)
                    .padding(.trailing, 16)
            }
        case .button(let action):
            Button(action: action) {
                cellContent(cell)
            }
            .buttonStyle(.plain)
        case .destructiveButton(let action):
            Button(role: .destructive, action: action) {
                cellContent(cell)
                    .foregroundStyle(.red)
            }
            .buttonStyle(.plain)
        case .info:
            cellContent(cell)
        }
    }

    private func cellContent(_ cell: SettingsCellDescriptor, showsRightSpace: Bool = true) -> some View {
        HStack(spacing: 16) {
            Image(systemName: cell.icon)
                .font(.system(size: 20, weight: .regular))
                .foregroundStyle(theme.accent)
                .frame(width: 24, height: 24)

            Text(cell.title)
                .font(.system(size: 16))
                .foregroundStyle(Color(.label))

            Spacer()

            if let value = cell.value {
                Text(value)
                    .font(.system(size: 14))
                    .foregroundStyle(Color(.secondaryLabel))
            }

            if cell.showsExternalLink {
                Image(systemName: "arrow.up.right")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Color(.tertiaryLabel))
            }

            if case .navigation = cell.kind {
                Image(systemName: "chevron.right")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Color(.tertiaryLabel))
            }
        }
        .padding(.leading, 16)
        .padding(.trailing, showsRightSpace ? 16 : 0)
        .padding(.vertical, 14)
    }

    // MARK: - Card Background

    private var cardBackground: some ShapeStyle {
        Color(.secondarySystemGroupedBackground)
    }

    // MARK: - Connection Helpers

    private var connectionIcon: String {
        switch appState.clawChatManager.linkState {
        case .connected: "wifi"
        case .connecting: "wifi.exclamationmark"
        case .disconnected: "wifi.slash"
        case .unpaired: "link.badge.plus"
        case .error: "exclamationmark.triangle"
        }
    }

    private var connectionLabel: String {
        switch appState.clawChatManager.linkState {
        case .connected: "已连接"
        case .connecting: "连接中…"
        case .disconnected: "已断开"
        case .unpaired: "未连接"
        case .error(let msg): "错误: \(msg)"
        }
    }

    private var connectionColor: Color {
        switch appState.clawChatManager.linkState {
        case .connected: .green
        case .connecting: .orange
        case .disconnected, .unpaired: .secondary
        case .error: .red
        }
    }

    // MARK: - Cell Data

    private var generalCells: [SettingsCellDescriptor] {
        [
            SettingsCellDescriptor(
                id: "theme", icon: "circle.lefthalf.filled", title: "视觉主题",
                value: theme.displayName,
                kind: .navigation(AnyView(ThemeSelectionView().environment(appState)))
            ),
            SettingsCellDescriptor(
                id: "model", icon: "cpu", title: "默认大语言模型",
                value: currentModelDisplayValue,
                kind: .info
            ),
            SettingsCellDescriptor(
                id: "darkmode", icon: "moon", title: "暗色模式",
                kind: .toggle($isDarkMode)
            ),
        ]
    }

    private var currentModelDisplayValue: String {
        if let model = currentAgent?.model, !model.isEmpty {
            return model
        }
        if appState.clawChatManager.connectedMethod == .direct {
            return "由 Gateway 决定"
        }
        return "未连接"
    }

    private var connectionCells: [SettingsCellDescriptor] {
        var cells: [SettingsCellDescriptor] = [
            SettingsCellDescriptor(
                id: "conn_status", icon: connectionIcon, title: "连接状态",
                value: connectionLabel,
                iconColor: connectionColor,
                kind: .info
            )
        ]

        if appState.clawChatManager.hasSavedConnection {
            cells.append(SettingsCellDescriptor(
                id: "unpair", icon: "link.badge.plus", title: "断开连接",
                kind: .destructiveButton { Task { await appState.clawChatManager.unpair() } }
            ))
        } else {
            cells.append(SettingsCellDescriptor(
                id: "pair", icon: "antenna.radiowaves.left.and.right", title: "连接 Gateway",
                kind: .button { withAnimation { appState.showPairing = true } }
            ))
        }

        return cells
    }

    private var legalCells: [SettingsCellDescriptor] {
        [
            SettingsCellDescriptor(
                id: "privacy", icon: "hand.raised", title: "隐私政策",
                showsExternalLink: true,
                kind: .button { showPrivacyPolicy = true }
            ),
            SettingsCellDescriptor(
                id: "tos", icon: "doc.text", title: "服务条款",
                showsExternalLink: true,
                kind: .button { showTermsOfService = true }
            ),
            SettingsCellDescriptor(
                id: "memory", icon: "brain.head.profile", title: "长期记忆管理",
                kind: .navigation(AnyView(Text("Memory Management")))
            ),
        ]
    }
}

// MARK: - Cell Descriptor

private struct SettingsCellDescriptor: Identifiable {
    let id: String
    let icon: String
    let title: String
    var value: String? = nil
    var iconColor: Color? = nil
    var showsExternalLink: Bool = false
    var kind: CellKind = .info

    enum CellKind {
        case navigation(AnyView)
        case toggle(Binding<Bool>)
        case button(() -> Void)
        case destructiveButton(() -> Void)
        case info
    }
}

// MARK: - Sub Views

struct ModelSelectionView: View {
    @Environment(AppState.self) private var appState
    @Binding var selectedModel: String
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        Form {
            Section {
                ForEach(appState.allAvailableModels, id: \.self) { model in
                    Button {
                        selectedModel = model
                        dismiss()
                    } label: {
                        HStack {
                            Text(model)
                                .foregroundStyle(.primary)
                            Spacer()
                            if model == selectedModel {
                                Image(systemName: "checkmark")
                                    .fontWeight(.semibold)
                                    .foregroundStyle(appState.currentVisualTheme.accent)
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle("选择默认模型")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .tabBar)
    }
}

struct ThemeSelectionView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        Form {
            Section {
                ForEach(AppVisualThemeID.allCases) { themeId in
                    let theme = AppVisualTheme.theme(for: themeId)
                    Button {
                        withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                            appState.selectedVisualThemeID = themeId
                        }
                        UIApplication.shared.setAlternateIconName(themeId.alternateIconName)
                        dismiss()
                    } label: {
                        HStack {
                            Text(theme.displayName)
                                .foregroundStyle(.primary)
                            Spacer()
                            if themeId == appState.selectedVisualThemeID {
                                Image(systemName: "checkmark")
                                    .fontWeight(.semibold)
                                    .foregroundStyle(appState.currentVisualTheme.accent)
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle("选择视觉主题")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .tabBar)
    }
}
