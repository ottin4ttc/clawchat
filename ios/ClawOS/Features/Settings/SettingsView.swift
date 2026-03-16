import SwiftUI

struct SettingsView: View {
    @Environment(AppState.self) private var appState
    @AppStorage("isDarkMode") private var isDarkMode = false
    @State private var skillsWatchEnabled = true
    

    private var currentAgent: Agent? {
        appState.selectedAgent
    }

    var body: some View {
        Form {
            // MARK: - Profile Header
            if let agent = currentAgent {
                Section {
                    HStack(spacing: 16) {
                        agentAvatarView(agent.avatar, size: 56)

                        VStack(alignment: .leading, spacing: 4) {
                            Text(agent.name)
                                .font(.headline)
                            Text("@\(agent.id)_agent")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 4)
                }
            }

            // MARK: - General
            Section(header: Text("通用设置")) {
                NavigationLink {
                    ThemeSelectionView()
                        .environment(appState)
                } label: {
                    settingRow(icon: "circle.lefthalf.filled", title: "视觉主题", value: appState.currentVisualTheme.displayName)
                }
                
                settingRow(icon: "cpu", title: "默认大语言模型", value: currentAgent?.model ?? "未连接")
                
                Toggle(isOn: $isDarkMode) {
                    settingRow(icon: "moon", title: "暗色模式", value: nil)
                }
                .tint(appState.currentVisualTheme.accent)
            }

            // MARK: - Skills & Capabilities
            Section(header: Text("技能与能力")) {
                NavigationLink {
                    Text("Skills Settings")
                } label: {
                    settingRow(icon: "puzzlepiece.extension", title: "Skills 设定", value: "\(appState.skills.filter(\.isEnabled).count) 个已启用")
                }
                
                Toggle(isOn: $skillsWatchEnabled) {
                    settingRow(icon: "arrow.triangle.2.circlepath", title: "Skills 自动重载 (Watch)", value: nil)
                }
                .tint(appState.currentVisualTheme.accent)
            }

            // MARK: - Core Files
            Section(header: Text("核心文件配置")) {
                fileNavRow(icon: "doc.text", title: "soul.md")
                fileNavRow(icon: "person.text.rectangle", title: "agent.md")
                fileNavRow(icon: "person.crop.square", title: "identity.md")
                fileNavRow(icon: "hammer", title: "tools.json")
                fileNavRow(icon: "person.2", title: "users.json")
            }

            // MARK: - Connection
            Section(header: Text("ClawChat 连接")) {
                HStack(spacing: 12) {
                    Image(systemName: connectionIcon)
                        .font(.system(size: 18, weight: .regular))
                        .foregroundStyle(connectionColor)
                        .frame(width: 24)
                    Text("连接状态")
                        .font(.system(size: 17))
                    Spacer()
                    Text(connectionLabel)
                        .font(.subheadline)
                        .foregroundStyle(connectionColor)
                }

                if appState.clawChatManager.isPaired {
                    Button(role: .destructive) {
                        Task { await appState.clawChatManager.unpair() }
                    } label: {
                        settingRow(icon: "link.badge.plus", title: "取消配对", value: nil)
                    }
                } else {
                    Button {
                        withAnimation { appState.showPairing = true }
                    } label: {
                        settingRow(icon: "antenna.radiowaves.left.and.right", title: "配对 Gateway", value: nil)
                    }
                }
            }

            // MARK: - Memory
            Section(header: Text("记忆与上下文")) {
                NavigationLink {
                    Text("Memory Management")
                } label: {
                    settingRow(icon: "brain.head.profile", title: "长期记忆管理", value: nil)
                }
            }
        }
        .navigationTitle("设置")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .tabBar)
        .scrollContentBackground(.hidden)
        .background {
            LinearGradient(
                colors: [appState.currentVisualTheme.pageGradientTop, appState.currentVisualTheme.pageGradientBottom],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()
        }
    }

    // MARK: - Avatar

    private func agentAvatarView(_ avatar: String, size: CGFloat) -> some View {
        Group {
            if !avatar.isEmpty, UIImage(named: avatar) != nil {
                Image(avatar)
                    .resizable()
                    .scaledToFill()
            } else {
                Image(systemName: "person.crop.circle.fill")
                    .resizable()
                    .foregroundStyle(.secondary)
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
    }

    // MARK: - Connection helpers

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
        case .unpaired: "未配对"
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

    // MARK: - Helpers

    private func settingRow(icon: String, title: String, value: String?) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 18, weight: .regular))
                .foregroundStyle(.secondary)
                .frame(width: 24)
            Text(title)
                .foregroundStyle(.primary)
                .font(.system(size: 17))
            Spacer()
            if let value = value {
                Text(value)
                    .foregroundStyle(.secondary)
                    .font(.subheadline)
            }
        }
    }

    private func fileNavRow(icon: String, title: String) -> some View {
        NavigationLink {
            Text("Editing \(title)")
        } label: {
            settingRow(icon: icon, title: title, value: nil)
        }
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
