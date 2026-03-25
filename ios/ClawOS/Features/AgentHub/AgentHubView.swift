import SwiftUI

struct AgentHubView: View {
    @Environment(AppState.self) private var appState
    @State private var navigateToAgentId: String?

    private var accent: Color {
        appState.currentVisualTheme.accent
    }

    private var stripItems: [AgentStripItem] {
        appState.agentStripItems
    }

    private var allAgents: [Agent] {
        appState.currentGatewayAgents
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            if stripItems.isEmpty && allAgents.isEmpty {
                emptyState
            } else {
                carousel
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background {
            LinearGradient(
                colors: [
                    appState.currentVisualTheme.pageGradientTop,
                    appState.currentVisualTheme.pageGradientBottom
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .overlay {
                if let name = appState.currentVisualTheme.ambientAssetName {
                    Image(name)
                        .resizable()
                        .scaledToFill()
                        .opacity(appState.currentVisualTheme.ambientOpacity)
                        .blur(radius: 0.5)
                }
            }
            .ignoresSafeArea()
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .navigationBar)
        .navigationDestination(item: $navigateToAgentId) { agentId in
            AgentProfileView(agentId: agentId)
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(alignment: .center) {
            gatewayPicker

            Text("Agents")
                .font(.system(size: 32, weight: .bold))
                .foregroundStyle(.primary)

            Spacer()

            NavigationLink {
                SettingsView()
            } label: {
                Image(systemName: "gearshape")
                    .font(.system(size: 22, weight: .regular))
                    .foregroundStyle(.primary)
            }
        }
        .padding(.horizontal, AppTheme.Spacing.xl)
        .padding(.top, 16)
        .padding(.bottom, 8)
    }

    private var gatewayPicker: some View {
        Menu {
            ForEach(appState.gateways) { gw in
                Button {
                    appState.selectGateway(gw.id)
                } label: {
                    HStack {
                        Label {
                            VStack(alignment: .leading) {
                                Text(gw.name)
                                Text(gw.url)
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                        } icon: {
                            Image(systemName: gwIcon(gw.type))
                        }
                        if gw.id == appState.selectedGatewayId {
                            Image(systemName: "checkmark")
                        }
                    }
                }
            }
        } label: {
            Image(systemName: currentGwIcon)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.primary)
                .frame(width: 32, height: 32)
                .adaptiveGlass(in: .circle)
        }
    }

    private var gwStatusDot: some View {
        let color: Color = switch appState.currentGateway?.status {
        case .online: .green
        case .error: .red
        default: Color(.systemGray3)
        }
        return Circle()
            .fill(color)
            .frame(width: 7, height: 7)
    }

    private var currentGwIcon: String {
        guard let gw = appState.currentGateway else { return "antenna.radiowaves.left.and.right" }
        return gwIcon(gw.type)
    }

    private func gwIcon(_ type: GatewayType) -> String {
        switch type {
        case .local: "desktopcomputer"
        case .cloud: "cloud.fill"
        case .custom: "server.rack"
        }
    }

    // MARK: - Snap-to-card Carousel

    private var carousel: some View {
        GeometryReader { geo in
            let cardWidth = geo.size.width * 0.82
            let hMargin = (geo.size.width - cardWidth) / 2

            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 16) {
                    let items = displayItems
                    ForEach(Array(items.enumerated()), id: \.element.id) { _, item in
                        cardForItem(item)
                            .frame(width: cardWidth)
                    }
                }
                .scrollTargetLayout()
                .padding(.vertical, 20)
            }
            .scrollTargetBehavior(.viewAligned)
            .contentMargins(.horizontal, hMargin, for: .scrollContent)
        }
    }

    private var displayItems: [AgentStripItem] {
        if stripItems.isEmpty {
            return allAgents.map { .single(agentId: $0.id) }
        }
        return stripItems
    }

    @ViewBuilder
    private func cardForItem(_ item: AgentStripItem) -> some View {
        switch item {
        case .single(let agentId):
            if let agent = appState.agent(for: agentId) {
                AgentCardView(
                    agent: agent,
                    isLeader: agent.id == appState.selectedAgentId,
                    accent: accent,
                    onAgentTapped: { id in navigateToAgentId = id }
                )
            }
        case .group(let group):
            let agents = group.agentIds.compactMap { appState.agent(for: $0) }
            AgentGroupCardView(
                group: group,
                agents: agents,
                accent: accent,
                onAgentTapped: { id in navigateToAgentId = id }
            )
        }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "person.crop.circle.badge.questionmark")
                .resizable()
                .scaledToFit()
                .frame(width: 44, height: 44)
                .foregroundStyle(Color(.systemGray3))
            VStack(spacing: 6) {
                Text("暂无 Agent")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(Color(.secondaryLabel))
                Text("连接 Gateway 后将自动加载 Agent 列表")
                    .font(.caption)
                    .foregroundStyle(Color(.tertiaryLabel))
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .offset(y: -40)
    }
}
