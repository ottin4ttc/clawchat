import SwiftUI

enum HomeSidebarMetrics {
    static let sidebarWidth: CGFloat = 66
    static let sidebarLeadingPadding: CGFloat = 10
    static let hiddenCompensation: CGFloat = 2
    static let travelWidth: CGFloat = sidebarWidth + sidebarLeadingPadding + hiddenCompensation

    static let avatarDiameter: CGFloat = 40
    static let controlDiameter: CGFloat = avatarDiameter
    static let addButtonDiameter: CGFloat = avatarDiameter
    static let rowWidth: CGFloat = 52
    static let rowHeight: CGFloat = 48
    static let statusDotDiameter: CGFloat = 10
}

struct AgentSidebarView: View {
    @Environment(AppState.self) private var appState
    @State private var showAddAgent = false
    var onDismiss: () -> Void = {}

    private var isConnected: Bool {
        appState.clawChatManager.isConnected
    }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView(showsIndicators: false) {
                VStack(spacing: 14) {
                    gatewayButton
                        .padding(.top, 24)

                    pillDivider

                    VStack(spacing: 14) {
                        ForEach(appState.currentGatewayAgents) { agent in
                            agentRow(agent)
                                .transition(.asymmetric(
                                    insertion: .scale(scale: 0.6).combined(with: .opacity),
                                    removal: .scale(scale: 0.6).combined(with: .opacity)
                                ))
                        }
                    }
                    .animation(.spring(response: 0.35, dampingFraction: 0.8), value: appState.selectedGatewayId)

                    pillDivider

                    addButton
                        .padding(.bottom, 24)
                }
                .frame(maxWidth: .infinity)
            }
            .mask(RoundedRectangle(cornerRadius: 24, style: .continuous))
        }
        .frame(maxHeight: .infinity)
        .glassEffect(.regular, in: .rect(cornerRadius: 24))
        .sheet(isPresented: $showAddAgent) {
            AgentEditorView()
                .environment(appState)
        }
    }

    // MARK: - Gateway

    private var gatewayIcon: String {
        if !isConnected { return "antenna.radiowaves.left.and.right.slash" }
        switch appState.currentGatewayType {
        case .local: return "desktopcomputer"
        case .cloud: return "cloud"
        case .custom: return "server.rack"
        }
    }

    private var gatewayStatusColor: Color {
        switch appState.clawChatManager.linkState {
        case .connected: .green
        case .connecting: .orange
        default: Color(.systemGray3)
        }
    }

    private var gatewayLabel: String {
        switch appState.clawChatManager.linkState {
        case .connected:
            appState.currentGateway?.name ?? "已连接"
        case .connecting:
            "连接中"
        default:
            "未连接"
        }
    }

    private var gatewayButton: some View {
        Group {
            if isConnected && !appState.gateways.isEmpty {
                connectedGatewayMenu
            } else {
                disconnectedGatewayButton
            }
        }
    }

    private var connectedGatewayMenu: some View {
        Menu {
            ForEach(appState.gateways) { gw in
                Button {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                        appState.selectGateway(gw.id)
                    }
                } label: {
                    Label {
                        Text(gw.name)
                    } icon: {
                        if gw.id == appState.selectedGatewayId {
                            Image(systemName: "checkmark")
                        }
                    }
                }
            }
        } label: {
            gatewayIconView
        }
        .sensoryFeedback(.selection, trigger: appState.selectedGatewayId)
    }

    private var disconnectedGatewayButton: some View {
        Button {
            withAnimation { appState.showPairing = true }
        } label: {
            gatewayIconView
        }
        .buttonStyle(.plain)
    }

    private var gatewayIconView: some View {
        ZStack(alignment: .bottomTrailing) {
            Image(systemName: gatewayIcon)
                .font(.system(size: 18, weight: .medium))
                .foregroundStyle(isConnected ? .primary : .secondary)
                .frame(width: HomeSidebarMetrics.controlDiameter, height: HomeSidebarMetrics.controlDiameter)
                .glassEffect(.regular, in: .circle)

            Circle()
                .fill(gatewayStatusColor)
                .frame(width: HomeSidebarMetrics.statusDotDiameter, height: HomeSidebarMetrics.statusDotDiameter)
                .overlay(Circle().stroke(.background, lineWidth: 2))
        }
    }

    // MARK: - Divider

    private var pillDivider: some View {
        Capsule()
            .fill(.quaternary)
            .frame(width: 24, height: 1)
            .padding(.vertical, 2)
    }

    // MARK: - Agent Row

    private func agentRow(_ agent: Agent) -> some View {
        let isSelected = appState.selectedAgentId == agent.id
        return Button {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                appState.selectedAgentId = agent.id
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                onDismiss()
            }
        } label: {
            HStack(spacing: 0) {
                Capsule()
                    .fill(Color(.label))
                    .frame(width: 2, height: isSelected ? 16 : 0)
                    .opacity(isSelected ? 1 : 0)
                    .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isSelected)

                Spacer(minLength: 0)

                agentAvatarView(agent, size: HomeSidebarMetrics.avatarDiameter)
                    .scaleEffect(isSelected ? 1.05 : 1.0)

                Spacer(minLength: 0)
            }
            .frame(width: HomeSidebarMetrics.rowWidth, height: HomeSidebarMetrics.rowHeight)
        }
        .buttonStyle(.plain)
        .sensoryFeedback(.selection, trigger: isSelected)
    }

    // MARK: - Avatar

    private func agentAvatarView(_ agent: Agent, size: CGFloat) -> some View {
        Group {
            if let custom = AvatarStorage.load(for: agent.id) {
                Image(uiImage: custom)
                    .resizable()
                    .scaledToFill()
            } else if !agent.avatar.isEmpty, UIImage(named: agent.avatar) != nil {
                Image(agent.avatar)
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

    // MARK: - Add

    private var addButton: some View {
        Button {
            showAddAgent = true
        } label: {
            Image(systemName: "plus")
                .font(.system(size: 18, weight: .semibold))
                .fontWeight(.semibold)
                .foregroundStyle(.secondary)
                .frame(width: HomeSidebarMetrics.addButtonDiameter, height: HomeSidebarMetrics.addButtonDiameter)
                .glassEffect(.regular, in: .circle)
        }
        .buttonStyle(.plain)
    }
}
