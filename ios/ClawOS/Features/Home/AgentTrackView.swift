import SwiftUI

enum AgentTrackMetrics {
    static let trackWidth: CGFloat = 66
    static let collapsedHeight: CGFloat = 66
    static let avatarDiameter: CGFloat = 40
    static let controlDiameter: CGFloat = avatarDiameter
    static let addButtonDiameter: CGFloat = avatarDiameter
    static let rowWidth: CGFloat = 52
    static let rowHeight: CGFloat = 48
    static let statusDotDiameter: CGFloat = 10
}

struct AgentTrackOverlay: View {
    @Binding var isExpanded: Bool
    
    var body: some View {
        ZStack(alignment: .bottomLeading) {
            if isExpanded {
                Color.black.opacity(0.15)
                    .ignoresSafeArea()
                    .onTapGesture {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
                            isExpanded = false
                        }
                    }
                    .transition(.opacity)
            }
            
            AgentTrackView(isExpanded: $isExpanded)
                .padding(.leading, 16)
                .padding(.bottom, 60)
        }
    }
}

struct AgentTrackView: View {
    @Environment(AppState.self) private var appState
    @Binding var isExpanded: Bool
    @State private var showAddAgent = false
    
    private var isConnected: Bool {
        appState.clawChatManager.isConnected
    }
    
    var body: some View {
        VStack(spacing: 0) {
            if isExpanded {
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
                .frame(maxHeight: UIScreen.main.bounds.height * 0.7)
                .transition(.opacity.combined(with: .scale(scale: 0.8, anchor: .bottom)))
            } else {
                collapsedButton
                    .transition(.opacity.combined(with: .scale(scale: 0.8, anchor: .bottom)))
            }
        }
        .frame(width: AgentTrackMetrics.trackWidth)
        .frame(height: isExpanded ? nil : AgentTrackMetrics.collapsedHeight)
        .glassEffect(.regular, in: isExpanded ? AnyShape(.capsule) : AnyShape(.circle))
        .shadow(color: .black.opacity(isExpanded ? 0.1 : 0.05), radius: 16, y: isExpanded ? -4 : 0)
        .sensoryFeedback(.impact(flexibility: .soft), trigger: isExpanded)
        .sheet(isPresented: $showAddAgent) {
            AgentEditorView()
                .environment(appState)
        }
    }
    
    // MARK: - Collapsed State
    
    private var collapsedButton: some View {
        Button {
            withAnimation(.spring(response: 0.4, dampingFraction: 0.78)) {
                isExpanded = true
            }
        } label: {
            ZStack {
                if let currentAgent = appState.currentGatewayAgents.first(where: { $0.id == appState.selectedAgentId }) {
                    agentAvatarView(currentAgent, size: AgentTrackMetrics.avatarDiameter)
                } else {
                    Image("clawos_svg_logo")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 24, height: 24)
                }
                
                // Status dot
                Circle()
                    .fill(gatewayStatusColor)
                    .frame(width: AgentTrackMetrics.statusDotDiameter, height: AgentTrackMetrics.statusDotDiameter)
                    .overlay(Circle().stroke(.background, lineWidth: 2))
                    .offset(x: 14, y: 14)
            }
            .frame(width: AgentTrackMetrics.trackWidth, height: AgentTrackMetrics.collapsedHeight)
        }
        .buttonStyle(.plain)
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
                .frame(width: AgentTrackMetrics.controlDiameter, height: AgentTrackMetrics.controlDiameter)
                .glassEffect(.regular, in: .circle)
            
            Circle()
                .fill(gatewayStatusColor)
                .frame(width: AgentTrackMetrics.statusDotDiameter, height: AgentTrackMetrics.statusDotDiameter)
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
                withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
                    isExpanded = false
                }
            }
        } label: {
            HStack(spacing: 0) {
                Capsule()
                    .fill(Color(.label))
                    .frame(width: 2, height: isSelected ? 16 : 0)
                    .opacity(isSelected ? 1 : 0)
                    .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isSelected)
                
                Spacer(minLength: 0)
                
                agentAvatarView(agent, size: AgentTrackMetrics.avatarDiameter)
                    .scaleEffect(isSelected ? 1.05 : 1.0)
                
                Spacer(minLength: 0)
            }
            .frame(width: AgentTrackMetrics.rowWidth, height: AgentTrackMetrics.rowHeight)
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
                .frame(width: AgentTrackMetrics.addButtonDiameter, height: AgentTrackMetrics.addButtonDiameter)
                .glassEffect(.regular, in: .circle)
        }
        .buttonStyle(.plain)
    }
}
