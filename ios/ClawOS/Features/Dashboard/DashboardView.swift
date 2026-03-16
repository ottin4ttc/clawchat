import SwiftUI

struct DashboardView: View {
    @Environment(AppState.self) private var appState
    @State private var selectedPeriod = 0

    private var currentTheme: AppVisualTheme {
        appState.currentVisualTheme
    }

    var body: some View {
        List {
            if appState.clawChatManager.isConnected {
                tokenUsageSection
                    .listRowInsets(EdgeInsets())
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)

                configSection

                diagnosticsSection

                maintenanceSection
            }
        }
        .listStyle(.insetGrouped)
        .scrollIndicators(.hidden)
        .scrollContentBackground(.hidden)
        .background {
            LinearGradient(
                colors: [currentTheme.pageGradientTop, currentTheme.pageGradientBottom],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .overlay {
                if let name = currentTheme.ambientAssetName {
                    Image(name)
                        .resizable()
                        .scaledToFill()
                        .opacity(currentTheme.ambientOpacity)
                        .blur(radius: 0.5)
                }
            }
            .ignoresSafeArea()
        }
        .toolbar(.hidden, for: .navigationBar)
    }

    // MARK: - Connection Status

    private var connectionSection: some View {
        Section("CLAWCHAT 连接") {
            HStack(spacing: 12) {
                Image(systemName: linkIcon)
                    .font(.system(size: 22))
                    .foregroundStyle(linkColor)
                    .frame(width: 32)

                VStack(alignment: .leading, spacing: 2) {
                    Text(linkLabel)
                        .font(.subheadline.weight(.semibold))
                    if appState.clawChatManager.isConnected {
                        Text("Gateway \(appState.clawChatManager.gatewayOnline ? "在线" : "离线")")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer()

                if case .connecting = appState.clawChatManager.linkState {
                    ProgressView().controlSize(.small)
                }
            }
            .padding(.vertical, 4)
        }
    }

    private var linkIcon: String {
        switch appState.clawChatManager.linkState {
        case .connected: "checkmark.circle.fill"
        case .connecting: "arrow.triangle.2.circlepath"
        case .disconnected: "wifi.slash"
        case .unpaired: "link.badge.plus"
        case .error: "exclamationmark.triangle.fill"
        }
    }

    private var linkLabel: String {
        switch appState.clawChatManager.linkState {
        case .connected: "已连接"
        case .connecting: "连接中…"
        case .disconnected: "已断开"
        case .unpaired: "未配对"
        case .error(let msg): msg
        }
    }

    private var linkColor: Color {
        switch appState.clawChatManager.linkState {
        case .connected: .green
        case .connecting: .orange
        case .disconnected, .unpaired: .secondary
        case .error: .red
        }
    }

    // MARK: - Token Usage

    private var tokenUsageSection: some View {
        Section {
            VStack(alignment: .leading, spacing: AppTheme.Spacing.lg) {
                HStack {
                    Text("Token 用量")
                        .font(.headline)
                    Spacer()
                    Picker("", selection: $selectedPeriod) {
                        Text("7天").tag(0)
                        Text("30天").tag(1)
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 120)
                }

                Text("0")
                    .font(.system(size: 40, weight: .bold, design: .rounded))

                Text("tokens - 过去 7 天")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                HStack(spacing: 0) {
                    tokenStat(label: "输入", value: "0")
                    Spacer()
                    tokenStat(label: "输出", value: "0")
                    Spacer()
                    tokenStat(label: "缓存", value: "0")
                }
                .padding(12)
                .background(.quaternary, in: RoundedRectangle(cornerRadius: AppTheme.Radius.md))
            }
            .padding(AppTheme.Spacing.lg)
            .background {
                ZStack {
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [
                                    currentTheme.softFill.opacity(0.95),
                                    Color(.systemBackground).opacity(0.68),
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )

                    if let bannerAssetName = currentTheme.bannerAssetName {
                        Image(bannerAssetName)
                            .resizable()
                            .scaledToFill()
                            .opacity(0.08)
                            .rotationEffect(.degrees(-12))
                            .scaleEffect(1.4)
                            .blendMode(.multiply)
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
            }
            .overlay(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .stroke(currentTheme.softStroke.opacity(0.9), lineWidth: 0.9)
            )
        }
    }

    private func tokenStat(label: String, value: String) -> some View {
        VStack(spacing: 4) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.subheadline)
                .fontWeight(.semibold)
        }
    }

    // MARK: - Config

    private var configSection: some View {
        Section("OPENCLAW 配置") {
            NavigationLink { Text("查看配置") } label: {
                Label("查看配置", systemImage: "doc.text")
            }
            NavigationLink { Text("恢复配置备份") } label: {
                Label("恢复配置备份", systemImage: "arrow.clockwise")
            }
            NavigationLink { Text("开启 Skills Watch") } label: {
                Label("开启 Skills Watch", systemImage: "eye")
            }
        }
    }

    // MARK: - Diagnostics

    private var diagnosticsSection: some View {
        Section("诊断与日志") {
            NavigationLink { Text("运行诊断") } label: {
                Label("运行诊断", systemImage: "cross.case")
            }
            NavigationLink { Text("查看日志") } label: {
                Label("查看日志", systemImage: "list.bullet")
            }
        }
    }

    // MARK: - Maintenance

    private var maintenanceSection: some View {
        Section("系统维护") {
            NavigationLink { Text("工具权限修复") } label: {
                Label("工具权限修复", systemImage: "wrench.and.screwdriver")
            }
            Button(role: .destructive) { } label: {
                Label("重启 Gateway", systemImage: "power")
            }
            NavigationLink { Text("更新 openclaw") } label: {
                Label("更新 openclaw", systemImage: "arrow.up.circle")
            }
        }
    }
}
