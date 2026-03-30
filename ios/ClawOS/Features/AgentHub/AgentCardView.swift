import SwiftUI

struct AgentCardView: View {
    let agent: Agent
    let isLeader: Bool
    let accent: Color
    var onAgentTapped: (String) -> Void = { _ in }

    var body: some View {
        VStack(spacing: 0) {
            // 顶部留白，让头像固定在偏上位置
            Spacer()
                .frame(height: 60)

            avatarSection
            
            Text(agent.name)
                .font(.system(size: 28, weight: .bold))
                .foregroundStyle(Color(.label)) // 自适应黑白模式
                .shadow(color: .white.opacity(0.8), radius: 6, x: 0, y: 0) // 添加反色发光增强对比度
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .padding(.top, 24)
                .padding(.horizontal, 24)

            // 中间使用 Spacer 顶开，使头像名字保持靠上，标签保持靠底
            Spacer()

            if let caps = agent.capabilities, !caps.isEmpty {
                capabilitiesGrid(caps)
                    .padding(.horizontal, 20)
                    .padding(.bottom, 32)
            } else {
                Spacer()
                    .frame(height: 32)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .aspectRatio(0.6, contentMode: .fit)
        .background(cardBackground)
        .adaptiveGlass(in: .rect(cornerRadius: 24, style: .continuous))
        .onTapGesture {
            onAgentTapped(agent.id)
        }
    }

    // MARK: - Avatar

    private var avatarSection: some View {
        AvatarViewHelper.avatarView(for: agent)
            .frame(width: 240, height: 240) // 从 200 增大到 240
            .clipShape(Circle())
            .overlay(
                Circle()
                    .strokeBorder(
                        LinearGradient(
                            colors: [.white.opacity(0.5), .white.opacity(0.08)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1.5
                    )
            )
            .shadow(color: .black.opacity(0.35), radius: 20, x: 0, y: 12)
    }

    // MARK: - Capabilities Tags (FlowLayout)

    private func capabilitiesGrid(_ caps: [String]) -> some View {
        FlowLayout(spacing: 8) {
            ForEach(caps, id: \.self) { cap in
                Text(cap)
                    .font(.system(size: 14, weight: .semibold)) // 加粗一点
                    .foregroundStyle(Color(.label)) // 使用主色（黑/白自适应）
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(Color(.systemBackground).opacity(0.6)) // 相比周围玻璃更不透明的一层底色
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .strokeBorder(Color(.separator).opacity(0.3), lineWidth: 0.5)
                    )
                    .shadow(color: .black.opacity(0.05), radius: 2, x: 0, y: 1) // 细微阴影让标签浮起来
            }
        }
    }

    // MARK: - Card Background

    private var cardBackground: some View {
        LinearGradient(
            stops: [
                .init(color: .clear, location: 0.0),
                .init(color: Color(.systemBackground).opacity(0.3), location: 1.0)
            ],
            startPoint: .top,
            endPoint: .bottom
        )
    }
}

// MARK: - FlowLayout (wrapping horizontal layout)

struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = computeRows(proposal: proposal, subviews: subviews)
        var height: CGFloat = 0
        for (i, row) in rows.enumerated() {
            let rowHeight = row.map { $0.sizeThatFits(.unspecified).height }.max() ?? 0
            height += rowHeight
            if i < rows.count - 1 { height += spacing }
        }
        return CGSize(width: proposal.width ?? 0, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let rows = computeRows(proposal: proposal, subviews: subviews)
        var y = bounds.minY

        for row in rows {
            let rowHeight = row.map { $0.sizeThatFits(.unspecified).height }.max() ?? 0
            let totalWidth = row.map { $0.sizeThatFits(.unspecified).width }.reduce(0, +) + CGFloat(max(row.count - 1, 0)) * spacing
            var x = bounds.minX + (bounds.width - totalWidth) / 2

            for subview in row {
                let size = subview.sizeThatFits(.unspecified)
                subview.place(at: CGPoint(x: x, y: y + (rowHeight - size.height) / 2), proposal: .unspecified)
                x += size.width + spacing
            }
            y += rowHeight + spacing
        }
    }

    private func computeRows(proposal: ProposedViewSize, subviews: Subviews) -> [[LayoutSubviews.Element]] {
        let maxWidth = proposal.width ?? .infinity
        var rows: [[LayoutSubviews.Element]] = [[]]
        var currentRowWidth: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if currentRowWidth + size.width + (rows.last!.isEmpty ? 0 : spacing) > maxWidth {
                rows.append([subview])
                currentRowWidth = size.width
            } else {
                currentRowWidth += size.width + (rows.last!.isEmpty ? 0 : spacing)
                rows[rows.count - 1].append(subview)
            }
        }
        return rows
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
            VStack(spacing: 0) {
                // 顶部留白，让头像固定在偏上位置
                Spacer()
                    .frame(height: 60)

                if let front = frontAgent {
                    AvatarViewHelper.avatarView(for: front)
                        .frame(width: 240, height: 240) // 从 200 增大到 240
                        .clipShape(Circle())
                        .overlay(
                            Circle()
                                .strokeBorder(
                                    LinearGradient(
                                        colors: [.white.opacity(0.5), .white.opacity(0.08)],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    ),
                                    lineWidth: 1.5
                                )
                        )
                        .shadow(color: .black.opacity(0.35), radius: 20, x: 0, y: 12)
                        .id("front_\(front.id)")
                        .transition(.asymmetric(
                            insertion: .scale(scale: 0.9).combined(with: .opacity),
                            removal: .scale(scale: 1.1).combined(with: .opacity)
                        ))
                        .onTapGesture {
                            onAgentTapped(front.id)
                        }

                    Text(front.name)
                        .font(.system(size: 28, weight: .bold))
                        .foregroundStyle(Color(.label)) // 自适应黑白模式
                        .shadow(color: .white.opacity(0.8), radius: 6, x: 0, y: 0) // 添加反色发光增强对比度
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                        .padding(.top, 24)
                        .padding(.horizontal, 24)
                        .id(front.id)
                        .transition(.opacity.combined(with: .scale(scale: 0.95)))
                }

                // 中间使用 Spacer 顶开
                Spacer()

                groupInfoFooter
                    .padding(.horizontal, 20)
                    .padding(.bottom, 32)
            }

            HStack {
                Spacer()
                rosterView
            }
            .padding(.top, 20)
            .padding(.trailing, 16)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .aspectRatio(0.6, contentMode: .fit)
        .background(groupCardBackground)
        .adaptiveGlass(in: .rect(cornerRadius: 24, style: .continuous))
        .onAppear {
            if frontAgentId == nil {
                frontAgentId = agents.first?.id
            }
        }
    }

    // MARK: - Roster

    private var rosterView: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(spacing: 16) {
                ForEach(agents) { agent in
                    if agent.id != frontAgentId {
                        AvatarViewHelper.avatarView(for: agent)
                            .frame(width: 44, height: 44)
                            .clipShape(Circle())
                            .overlay(Circle().strokeBorder(Color.white.opacity(0.25), lineWidth: 1.5))
                            .background(Circle().fill(Color.black))
                            .contentShape(Circle())
                            .onTapGesture {
                                withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                                    frontAgentId = agent.id
                                }
                            }
                    }
                }
            }
            .padding(.vertical, 16)
        }
        .frame(maxHeight: 280)
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

    // MARK: - Group Footer

    private var groupInfoFooter: some View {
        HStack(spacing: 8) {
            Text(group.displayName)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Color(.label))
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color(.systemBackground).opacity(0.6))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(Color(.separator).opacity(0.3), lineWidth: 0.5)
                )
                .shadow(color: .black.opacity(0.05), radius: 2, x: 0, y: 1)

            let onlineCount = agents.filter { $0.status == .online }.count
            Text("\(onlineCount)/\(agents.count) Online")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Color(.label))
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color(.systemBackground).opacity(0.6))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(Color(.separator).opacity(0.3), lineWidth: 0.5)
                )
                .shadow(color: .black.opacity(0.05), radius: 2, x: 0, y: 1)
        }
    }

    // MARK: - Background

    private var groupCardBackground: some View {
        LinearGradient(
            stops: [
                .init(color: .clear, location: 0.0),
                .init(color: Color(.systemBackground).opacity(0.3), location: 1.0)
            ],
            startPoint: .top,
            endPoint: .bottom
        )
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
