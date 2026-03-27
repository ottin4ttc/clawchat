import SwiftUI
import ClawChatKit

struct HomeView: View {
    @Environment(AppState.self) private var appState
    @State private var searchText = ""
    @State private var isSearchExpanded = false
    @State private var folderOverlayActive = false
    @State private var folderPopoverGroupId: String?
    @State private var dragCoordinator = AgentDragCoordinator()
    @FocusState private var isSearchFocused: Bool

    var body: some View {
        ZStack {
            SessionListView(searchText: $searchText)
                .safeAreaInset(edge: .top, spacing: 0) {
                    topChrome
                }
                .allowsHitTesting(!folderOverlayActive)
                .onTapGesture {
                    isSearchFocused = false
                    isSearchExpanded = false
                    if dragCoordinator.isEditMode {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                            dragCoordinator.isEditMode = false
                        }
                    }
                }

            if folderOverlayActive,
               let groupId = folderPopoverGroupId,
               let item = appState.agentStripItems.first(where: { $0.id == groupId }),
               case .group(let group) = item {
                folderPopoverOverlay(group: group)
            }
        }
        .environment(dragCoordinator)
        .background {
            LinearGradient(
                colors: [appState.currentVisualTheme.pageGradientTop,
                         appState.currentVisualTheme.pageGradientBottom],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()
        }
        .toolbar(.hidden, for: .navigationBar)
    }

    private var topChrome: some View {
        VStack(spacing: 0) {
            headerBar
            AgentStripView(folderOverlayActive: $folderOverlayActive, folderPopoverGroupId: $folderPopoverGroupId)
                .padding(.bottom, 8)
        }
        .background(Color.clear)
        .zIndex(20)
    }

    // MARK: - Header Bar

    private var headerBar: some View {
        HStack(spacing: 8) {
            gatewayPicker

            if !isSearchExpanded {
                Spacer()
            }

            if isSearchExpanded {
                HStack(spacing: 6) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(.secondary)

                    TextField("搜索", text: $searchText)
                        .focused($isSearchFocused)
                        .textFieldStyle(.plain)
                        .font(.system(size: 14))

                    Button {
                        searchText = ""
                        isSearchExpanded = false
                        isSearchFocused = false
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 14))
                            .foregroundStyle(.tertiary)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 12)
                .frame(maxWidth: .infinity)
                .frame(height: AppTheme.Chrome.controlDiameter)
                .adaptiveGlass(in: .capsule)
                .transition(.opacity.combined(with: .scale(scale: 0.9, anchor: .trailing)))
            }

            if !isSearchExpanded {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(.primary)
                    .frame(
                        width: AppTheme.Chrome.controlDiameter,
                        height: AppTheme.Chrome.controlDiameter
                    )
                    .contentShape(Circle())
                    .adaptiveGlass(in: .circle)
                    .onTapGesture {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                            isSearchExpanded = true
                        }
                    }
                    .transition(.opacity.combined(with: .scale(scale: 0.9)))
            }

            Image(systemName: "square.and.pencil")
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(.primary)
                .frame(
                    width: AppTheme.Chrome.controlDiameter,
                    height: AppTheme.Chrome.controlDiameter
                )
                .contentShape(Circle())
                .adaptiveGlass(in: .circle)
                .onTapGesture {
                    _ = appState.startNewSession()
                }
        }
        .padding(.horizontal, 16)
        .padding(.top, AppTheme.Chrome.headerTopInset)
        .padding(.bottom, AppTheme.Chrome.headerBottomInset)
        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: isSearchExpanded)
        .onChange(of: isSearchExpanded) { _, expanded in
            guard expanded else { return }
            Task { @MainActor in
                isSearchFocused = true
            }
        }
    }

    // MARK: - Gateway Picker

    private var gatewayPicker: some View {
        Menu {
            if appState.gateways.isEmpty {
                Button {
                    appState.showPairing = true
                } label: {
                    Label("连接 Gateway", systemImage: "antenna.radiowaves.left.and.right")
                }
            } else {
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
                                Image(systemName: gatewayIcon(gw.type))
                            }
                            if gw.id == appState.selectedGatewayId {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                }

                Divider()

                Button {
                    appState.showPairing = true
                } label: {
                    Label("添加 Gateway", systemImage: "plus")
                }
            }
        } label: {
            Image(systemName: gwTypeIcon)
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(.primary)
                .frame(
                    width: AppTheme.Chrome.controlDiameter,
                    height: AppTheme.Chrome.controlDiameter
                )
                .adaptiveGlass(in: .circle)
                .overlay(alignment: .topTrailing) {
                    connectionDot
                        .offset(x: 0, y: 0)
                }
        }
    }

    private var connectionDot: some View {
        let color: Color = switch appState.clawChatManager.linkState {
        case .connected: .green
        case .connecting: .orange
        default: appState.currentVisualTheme.softStroke
        }
        return Circle()
            .fill(color)
            .frame(width: 8, height: 8)
    }

    private var gwTypeIcon: String {
        guard let gw = appState.currentGateway else { return "antenna.radiowaves.left.and.right" }
        return gatewayIcon(gw.type)
    }

    private func gatewayIcon(_ type: GatewayType) -> String {
        switch type {
        case .local: "desktopcomputer"
        case .cloud: "cloud.fill"
        case .custom: "server.rack"
        }
    }

    // MARK: - Folder Popover (elevated z-level)

    private func folderPopoverOverlay(group: AgentGroup) -> some View {
        let groupItemId = "group_\(group.id)"

        return ZStack {
            Color.black.opacity(0.01)
                .ignoresSafeArea()
                .onTapGesture {
                    withAnimation(.easeOut(duration: 0.2)) {
                        folderOverlayActive = false
                        folderPopoverGroupId = nil
                    }
                }

            AgentFolderPopoverView(
                group: group,
                isEditMode: dragCoordinator.isEditMode,
                onSelectAgent: { agentId in
                    appState.selectAgentInGroup(agentId, groupItemId: groupItemId)
                    withAnimation(.easeOut(duration: 0.2)) {
                        folderOverlayActive = false
                    }
                },
                onDismiss: {
                    withAnimation(.easeOut(duration: 0.2)) {
                        folderOverlayActive = false
                        folderPopoverGroupId = nil
                    }
                }
            )
            .transition(.scale(scale: 0.9, anchor: .top).combined(with: .opacity))
            .padding(.top, 140)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
        .zIndex(200)
    }
}
