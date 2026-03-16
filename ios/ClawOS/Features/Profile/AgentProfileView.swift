import SwiftUI
import PhotosUI

struct AgentProfileView: View {
    @Environment(AppState.self) private var appState
    @State private var showAvatarPicker = false
    @State private var selectedPhotoItem: PhotosPickerItem?
    @State private var avatarRefreshToken = UUID()

    private var currentAgent: Agent? {
        appState.selectedAgent
    }

    private var currentTheme: AppVisualTheme {
        appState.currentVisualTheme
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                banner
                if currentAgent != nil {
                    profileContent
                } else {
                    emptyState
                }
            }
        }
        .ignoresSafeArea(edges: .top)
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
        .navigationBarTitleDisplayMode(.inline)
        .scrollIndicators(.hidden)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                NavigationLink {
                    SettingsView()
                } label: {
                    Image(systemName: "gearshape")
                        .font(.system(size: 14, weight: .regular))
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var emptyState: some View {
        ContentUnavailableView(
            "暂无 Agent",
            systemImage: "person.crop.circle.badge.questionmark",
            description: Text("连接 Gateway 后将自动加载 Agent 列表")
        )
        .padding(.top, 60)
    }

    // MARK: - Banner

    private var banner: some View {
        GeometryReader { geo in
            let minY = geo.frame(in: .global).minY
            let height = max(AppTheme.bannerHeight, AppTheme.bannerHeight + minY)

            ZStack {
                LinearGradient(
                    colors: currentTheme.bannerGradient,
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )

                if let bannerAssetName = currentTheme.bannerAssetName {
                    Image(bannerAssetName)
                        .resizable()
                        .scaledToFill()
                        .opacity(0.34)
                        .overlay(Color.white.opacity(0.12))
                }
            }
            .frame(width: geo.size.width, height: height)
            .offset(y: minY > 0 ? -minY : 0)
        }
        .frame(height: AppTheme.bannerHeight)
    }

    // MARK: - Profile Content

    private var profileContent: some View {
        VStack(alignment: .leading, spacing: 0) {
            avatarRow
            nameSection
            infoCards
        }
        .padding(.horizontal, AppTheme.Spacing.lg)
        .padding(.bottom, 100)
    }

    private var avatarRow: some View {
        HStack(alignment: .bottom) {
            if let agent = currentAgent {
                Button {
                    showAvatarPicker = true
                } label: {
                    ZStack(alignment: .bottomTrailing) {
                        agentAvatarImage(agent, size: AppTheme.largeAvatarSize)
                            .overlay(Circle().stroke(.background, lineWidth: 4))

                        Image(systemName: "camera.fill")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(.white)
                            .frame(width: 24, height: 24)
                            .background(.tint, in: Circle())
                            .overlay(Circle().stroke(.background, lineWidth: 2))
                            .offset(x: 2, y: 2)
                    }
                }
                .buttonStyle(.plain)
                .contextMenu {
                    Button {
                        showAvatarPicker = true
                    } label: {
                        Label("更换头像", systemImage: "photo.on.rectangle")
                    }
                    if AvatarStorage.load(for: agent.id) != nil {
                        Button(role: .destructive) {
                            AvatarStorage.remove(for: agent.id)
                            avatarRefreshToken = UUID()
                        } label: {
                            Label("移除头像", systemImage: "trash")
                        }
                    }
                }
            }

            Spacer()

            Button { } label: {
                HStack(spacing: 4) {
                    Image(systemName: "plus.circle.fill")
                        .font(.caption)
                    Text("添加状态")
                        .font(.caption)
                        .fontWeight(.semibold)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
            }
            .buttonStyle(.glass)
        }
        .offset(y: -28)
        .padding(.bottom, -12)
        .photosPicker(
            isPresented: $showAvatarPicker,
            selection: $selectedPhotoItem,
            matching: .images,
            photoLibrary: .shared()
        )
        .onChange(of: selectedPhotoItem) { _, newItem in
            guard let item = newItem, let agentId = currentAgent?.id else { return }
            selectedPhotoItem = nil
            Task {
                if let data = try? await item.loadTransferable(type: Data.self),
                   let image = UIImage(data: data) {
                    let cropped = image.croppedToSquare(maxSize: 256)
                    AvatarStorage.save(cropped, for: agentId)
                    avatarRefreshToken = UUID()
                }
            }
        }
    }

    private var nameSection: some View {
        Menu {
            ForEach(appState.agents) { agent in
                Button {
                    appState.selectedAgentId = agent.id
                } label: {
                    if agent.id == currentAgent?.id {
                        Label(agent.name, systemImage: "checkmark")
                    } else {
                        Text(agent.name)
                    }
                }
            }
        } label: {
            HStack(spacing: 6) {
                Text(currentAgent?.name ?? "Agent")
                    .font(.title)
                    .fontWeight(.bold)
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize()
            }
        }
        .padding(.bottom, AppTheme.Spacing.xl)
        .id(currentAgent?.id)
    }

    private func agentAvatarImage(_ agent: Agent, size: CGFloat) -> some View {
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
        .id(avatarRefreshToken)
    }

    // MARK: - Info Cards

    private var infoCards: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("快速信息")
                .font(.headline)
                .padding(.horizontal, 4)

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                quickInfoCard(
                    title: "默认模型",
                    value: currentAgent?.model ?? "未设定",
                    icon: "cpu"
                )
                quickInfoCard(
                    title: "所在网关",
                    value: appState.gateways.first(where: { $0.id == currentAgent?.gatewayId })?.name ?? "未连接",
                    icon: "point.3.connected.trianglepath.dotted"
                )
            }

            skillsCard
            themeCard
        }
    }

    private func quickInfoCard(title: String, value: String, icon: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                Text(title)
            }
            .font(.caption)
            .foregroundStyle(.secondary)

            Text(value)
                .font(.subheadline)
                .fontWeight(.semibold)
                .foregroundStyle(.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .glassEffect(.regular, in: .rect(cornerRadius: AppTheme.Radius.lg))
    }

    private var skillsCard: some View {
        let enabledCount = appState.skills.filter(\.isEnabled).count
        let totalCount = appState.skills.count

        return HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("已启用 Skills")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(totalCount > 0 ? "\(enabledCount) / \(totalCount) 个已启用" : "暂无")
                    .font(.subheadline)
                    .fontWeight(.semibold)
            }
            Spacer()
            Image(systemName: "puzzlepiece.extension")
                .font(.system(size: 16))
                .foregroundStyle(.tertiary)
        }
        .padding(16)
        .glassEffect(.regular, in: .rect(cornerRadius: AppTheme.Radius.lg))
    }

    private var themeCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "text.quote")
                Text("系统设定")
            }
            .font(.caption)
            .foregroundStyle(.secondary)

            Text(currentAgent?.theme ?? "You are a helpful AI assistant.")
                .font(.subheadline)
                .foregroundStyle(.primary)
                .lineLimit(3)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .glassEffect(.regular, in: .rect(cornerRadius: AppTheme.Radius.lg))
    }
}
