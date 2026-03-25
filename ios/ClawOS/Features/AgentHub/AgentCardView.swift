import SwiftUI

struct AgentCardView: View {
    let agent: Agent
    let isLeader: Bool
    let accent: Color
    var onAgentTapped: (String) -> Void = { _ in }

    private var modelShortName: String {
        guard let model = agent.model, !model.isEmpty, model != "unknown" else {
            return "AI"
        }
        let lower = model.lowercased()
        if lower.contains("gemini") { return "GEMINI" }
        if lower.contains("gpt") { return "GPT" }
        if lower.contains("claude") { return "CLAUDE" }
        if lower.contains("llama") { return "LLAMA" }
        if lower.contains("qwen") { return "QWEN" }
        if lower.contains("deepseek") { return "DSEEK" }
        let base = model.components(separatedBy: CharacterSet.alphanumerics.inverted).first ?? model
        return String(base.prefix(6)).uppercased()
    }

    private var formattedTokens: String {
        guard let count = agent.totalTokens, count > 0 else { return "—" }
        if count >= 1_000_000 {
            return String(format: "%.1fM", Double(count) / 1_000_000)
        } else if count >= 1_000 {
            return String(format: "%.1fK", Double(count) / 1_000)
        }
        return "\(count)"
    }

    var body: some View {
        ZStack {
            // Main Avatar (Huge & Centered)
            VStack {
                AvatarViewHelper.avatarView(for: agent)
                    .frame(width: 260, height: 260)
                    .clipShape(Circle())
                    .overlay(
                        Circle()
                            .strokeBorder(
                                LinearGradient(
                                    colors: [.white.opacity(0.6), .white.opacity(0.1)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ),
                                lineWidth: 2
                            )
                    )
                    .shadow(color: .black.opacity(0.4), radius: 25, x: 0, y: 15)
                    .padding(.top, 40)
                    .onTapGesture {
                        onAgentTapped(agent.id)
                    }
                
                Spacer()
            }
            
            // Bottom Info Panel
            VStack {
                Spacer()
                infoPanel
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .aspectRatio(0.65, contentMode: .fit)
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(.thinMaterial)
        )
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.1), lineWidth: 0.5)
        )
        .contentShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
    }

    // MARK: - Info Panel
    
    private var infoPanel: some View {
        VStack(spacing: 16) {
            VStack(spacing: 8) {
                Text(agent.name)
                    .font(.system(size: 28, weight: .bold))
                    .foregroundStyle(.white)
                    .shadow(color: .black.opacity(0.3), radius: 2, x: 0, y: 1)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                
                HStack(spacing: 8) {
                    roleBadge
                    modelBadge
                }
            }
            
            Divider()
                .background(Color.white.opacity(0.2))
                .padding(.horizontal, 20)
            
            HStack(spacing: 0) {
                statItem(label: "STATUS", value: agent.status.label.uppercased(), dot: agent.status.color)
                
                Divider()
                    .frame(height: 30)
                    .background(Color.white.opacity(0.2))
                    .padding(.horizontal, 20)
                
                statItem(label: "TOKENS", value: formattedTokens)
            }
        }
        .padding(.horizontal, 24)
        .padding(.bottom, 32)
        .padding(.top, 20)
        .background(
            LinearGradient(
                stops: [
                    .init(color: .clear, location: 0),
                    .init(color: .clear, location: 0.2),
                    .init(color: .black.opacity(0.15), location: 0.6),
                    .init(color: .black.opacity(0.4), location: 1.0)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        )
        .onTapGesture {
            onAgentTapped(agent.id)
        }
    }

    private var roleBadge: some View {
        HStack(spacing: 4) {
            Image(systemName: isLeader ? "star.fill" : "person.fill")
                .font(.system(size: 10, weight: .black))
            Text(isLeader ? "LEADER" : "MEMBER")
                .font(.system(size: 11, weight: .black, design: .monospaced))
                .tracking(1)
        }
        .foregroundStyle(.white.opacity(0.8))
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(
            Capsule()
                .fill(Color.white.opacity(0.1))
                .overlay(Capsule().strokeBorder(Color.white.opacity(0.2), lineWidth: 1))
        )
        .shadow(color: .black.opacity(0.1), radius: 2, x: 0, y: 1)
    }

    private var modelBadge: some View {
        Text(modelShortName)
            .font(.system(size: 11, weight: .bold, design: .monospaced))
            .tracking(0.5)
            .foregroundStyle(.white.opacity(0.8))
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(
                Capsule()
                    .fill(Color.white.opacity(0.1))
                    .overlay(Capsule().strokeBorder(Color.white.opacity(0.2), lineWidth: 1))
            )
            .shadow(color: .black.opacity(0.1), radius: 2, x: 0, y: 1)
    }

    private func statItem(label: String, value: String, dot: Color? = nil) -> some View {
        VStack(spacing: 6) {
            Text(label)
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                .foregroundStyle(.white.opacity(0.7))
                .shadow(color: .black.opacity(0.2), radius: 1, x: 0, y: 1)
                .tracking(1)

            HStack(spacing: 6) {
                if let dot {
                    Circle()
                        .fill(dot)
                        .frame(width: 8, height: 8)
                        .shadow(color: dot.opacity(0.6), radius: 4)
                }

                Text(value)
                    .font(.system(size: 18, weight: .heavy, design: .rounded))
                    .foregroundStyle(.white)
                    .shadow(color: .black.opacity(0.3), radius: 1, x: 0, y: 1)
            }
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Group Stack Card

struct AgentGroupCardView: View {
    let group: AgentGroup
    let agents: [Agent]
    let accent: Color
    var onAgentTapped: (String) -> Void = { _ in }

    @State private var frontAgentId: String?

    private var frontAgent: Agent? {
        agents.first(where: { $0.id == frontAgentId }) ?? agents.first
    }

    var body: some View {
        ZStack {
            // Main Avatar (Huge & Centered)
            VStack {
                if let front = frontAgent {
                    AvatarViewHelper.avatarView(for: front)
                        .frame(width: 260, height: 260)
                        .clipShape(Circle())
                        .overlay(
                            Circle()
                                .strokeBorder(
                                    LinearGradient(
                                        colors: [.white.opacity(0.6), .white.opacity(0.1)],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    ),
                                    lineWidth: 2
                                )
                        )
                        .shadow(color: .black.opacity(0.4), radius: 25, x: 0, y: 15)
                        .id("front_\(front.id)")
                        .transition(.asymmetric(
                            insertion: .scale(scale: 0.9).combined(with: .opacity),
                            removal: .scale(scale: 1.1).combined(with: .opacity)
                        ))
                        .padding(.top, 40)
                        .onTapGesture {
                            onAgentTapped(front.id)
                        }
                }
                Spacer()
            }
            .zIndex(1)
            
            // Bottom Info Panel
            VStack {
                Spacer()
                groupInfoPanel
            }
            .zIndex(2) // Info panel below roster so roster can be tapped
            
            // Vertical Roster on the Right
            HStack {
                Spacer()
                rosterView
            }
            .padding(.top, 20)
            .padding(.trailing, 16)
            .zIndex(3) // Roster on top to ensure taps are caught
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .aspectRatio(0.65, contentMode: .fit)
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(.thinMaterial)
        )
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.1), lineWidth: 0.5)
        )
        .contentShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .onAppear {
            if frontAgentId == nil {
                frontAgentId = agents.first?.id
            }
        }
    }
    
    // MARK: - Roster View
    
    private var rosterView: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(spacing: 16) {
                ForEach(agents) { agent in
                    if agent.id != frontAgentId {
                            AvatarViewHelper.avatarView(for: agent)
                                .frame(width: 48, height: 48)
                                .clipShape(Circle())
                                .overlay(Circle().strokeBorder(Color.white.opacity(0.3), lineWidth: 1.5))
                                .background(Circle().fill(Color.black)) // Make roster avatars opaque
                                .contentShape(Circle()) // Ensure tap area is exactly the circle
                            .onTapGesture {
                                withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                                    frontAgentId = agent.id
                                }
                            }
                    }
                }
            }
            .padding(.vertical, 16) // Added vertical padding inside scroll to allow items to be fully visible before fading
        }
        .frame(maxHeight: 320) // Limit height so it doesn't overlap info panel
        .mask(
            LinearGradient(
                stops: [
                    .init(color: .clear, location: 0),
                    .init(color: .black, location: 0.15),
                    .init(color: .black, location: 0.85),
                    .init(color: .clear, location: 1.0)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        )
    }

    // MARK: - Group Info Panel
    
    private var groupInfoPanel: some View {
        VStack(spacing: 16) {
            VStack(spacing: 8) {
                Text(frontAgent?.name ?? group.displayName)
                    .font(.system(size: 28, weight: .bold))
                    .foregroundStyle(.white)
                    .shadow(color: .black.opacity(0.3), radius: 2, x: 0, y: 1)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .id(frontAgent?.id ?? group.id)
                    .transition(.opacity.combined(with: .scale(scale: 0.95)))
                
                HStack(spacing: 8) {
                    Text(group.displayName)
                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                        .tracking(1)
                        .foregroundStyle(.white.opacity(0.8))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(Color.white.opacity(0.1), in: Capsule())
                        .overlay(Capsule().strokeBorder(Color.white.opacity(0.2), lineWidth: 1))
                        .shadow(color: .black.opacity(0.1), radius: 2, x: 0, y: 1)
                    
                    Text("TEAM OF \(agents.count)")
                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.8))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(Color.white.opacity(0.1), in: Capsule())
                        .overlay(Capsule().strokeBorder(Color.white.opacity(0.2), lineWidth: 1))
                        .shadow(color: .black.opacity(0.1), radius: 2, x: 0, y: 1)
                }
            }
            
            Divider()
                .background(Color.white.opacity(0.2))
                .padding(.horizontal, 20)
            
            HStack(spacing: 0) {
                let onlineCount = agents.filter { $0.status == .online }.count
                statItem(label: "ONLINE", value: "\(onlineCount)/\(agents.count)", dot: .green)
                
                Divider()
                    .frame(height: 30)
                    .background(Color.white.opacity(0.2))
                    .padding(.horizontal, 20)
                
                let totalTokens = agents.compactMap { $0.totalTokens }.reduce(0, +)
                statItem(label: "TOKENS", value: formatTokenCount(totalTokens))
            }
        }
        .padding(.horizontal, 24)
        .padding(.bottom, 32)
        .padding(.top, 20)
        .background(
            LinearGradient(
                stops: [
                    .init(color: .clear, location: 0),
                    .init(color: .clear, location: 0.2),
                    .init(color: .black.opacity(0.15), location: 0.6),
                    .init(color: .black.opacity(0.4), location: 1.0)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        )
        .onTapGesture {
            if let front = frontAgent {
                onAgentTapped(front.id)
            }
        }
    }

    private func statItem(label: String, value: String, dot: Color? = nil) -> some View {
        VStack(spacing: 6) {
            Text(label)
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                .foregroundStyle(.white.opacity(0.7))
                .shadow(color: .black.opacity(0.2), radius: 1, x: 0, y: 1)
                .tracking(1)

            HStack(spacing: 6) {
                if let dot {
                    Circle()
                        .fill(dot)
                        .frame(width: 8, height: 8)
                        .shadow(color: dot.opacity(0.6), radius: 4)
                }

                Text(value)
                    .font(.system(size: 18, weight: .heavy, design: .rounded))
                    .foregroundStyle(.white)
                    .shadow(color: .black.opacity(0.3), radius: 1, x: 0, y: 1)
            }
        }
        .frame(maxWidth: .infinity)
    }
    
    private func formatTokenCount(_ count: Int) -> String {
        if count >= 1_000_000 {
            return String(format: "%.1fM", Double(count) / 1_000_000)
        } else if count >= 1_000 {
            return String(format: "%.1fK", Double(count) / 1_000)
        } else if count > 0 {
            return "\(count)"
        }
        return "—"
    }
}

// MARK: - Shared Avatar Helper

enum AvatarViewHelper {
    @ViewBuilder
    static func avatarView(for agent: Agent) -> some View {
        if let custom = AvatarStorage.load(for: agent.id) {
            Image(uiImage: custom)
                .resizable()
                .scaledToFill()
        } else if !agent.avatar.isEmpty, UIImage(named: agent.avatar) != nil {
            Image(agent.avatar)
                .resizable()
                .scaledToFill()
        } else {
            ZStack {
                Color(.systemGray4)
                Image("default_agent_avatar")
                    .resizable()
                    .scaledToFill()
                    .foregroundStyle(.white)
            }
        }
    }
}
