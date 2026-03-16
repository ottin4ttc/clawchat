import SwiftUI

struct SessionListView: View {
    @Environment(AppState.self) private var appState
    @State private var searchText = ""
    @FocusState private var isSearchFocused: Bool
    var isSidebarDragging = false
    var onMenuTap: () -> Void = {}

    private var filteredSessions: [Session] {
        let visibleAgentIds = Set(appState.currentGatewayAgents.map(\.id))
        let gatewaySessions = appState.sessions.filter { visibleAgentIds.contains($0.agentId) }

        let sortedSessions = gatewaySessions.sorted { s1, s2 in
            if s1.isPinned != s2.isPinned {
                return s1.isPinned
            }
            return (s1.lastMessageTime ?? Date.distantPast) > (s2.lastMessageTime ?? Date.distantPast)
        }

        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        if query.isEmpty {
            return sortedSessions
        }
        return sortedSessions.filter { session in
            let agent = appState.agent(for: session.agentId)
            if session.title.localizedCaseInsensitiveContains(query) { return true }
            if agent?.name.localizedCaseInsensitiveContains(query) ?? false { return true }
            if session.lastMessage?.localizedCaseInsensitiveContains(query) ?? false { return true }

            let messages = appState.messages(for: session.id)
            return messages.contains { $0.text.localizedCaseInsensitiveContains(query) }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            searchBar
            sessionList
        }
        .onTapGesture {
            isSearchFocused = false
        }
        .background {
            LinearGradient(
                colors: [appState.currentVisualTheme.pageGradientTop, appState.currentVisualTheme.pageGradientBottom],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            Button(action: onMenuTap) {
                Image("clawos_svg_logo")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 22, height: 22)
                    .frame(width: 36, height: 36)
                    .contentShape(Circle())
            }
            .glassEffect(.regular, in: .circle)

            Spacer()

            Text("Chat")
                .font(.headline)
                .fontWeight(.bold)

            Spacer()

            Button {
                _ = appState.startNewSession()
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: 18, weight: .medium))
                    .foregroundStyle(.secondary)
                    .frame(width: 36, height: 36)
                    .contentShape(Circle())
            }
            .glassEffect(.regular, in: .circle)
        }
        .padding(.horizontal, AppTheme.Spacing.lg)
        .padding(.top, 2)
        .padding(.bottom, 10)
    }

    // MARK: - Search Bar

    private var searchBar: some View {
        HStack {
            Image(systemName: "magnifyingglass")
                .foregroundColor(.secondary)
            TextField("搜索会话", text: $searchText)
                .textFieldStyle(.plain)
                .focused($isSearchFocused)
            if !searchText.isEmpty {
                Button {
                    searchText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
                .transition(.scale.combined(with: .opacity))
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Color(.systemGray6))
        .cornerRadius(20)
        .padding(.horizontal, AppTheme.Spacing.lg)
        .padding(.bottom, 12)
        .animation(.easeInOut(duration: 0.2), value: searchText.isEmpty)
    }

    // MARK: - List

    @State private var selectedSession: Session?
    @State private var activeSwipeId: String?

    private var sessionList: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(filteredSessions) { session in
                    SessionRowContainer(
                        session: session,
                        activeSwipeId: $activeSwipeId
                    ) {
                        selectedSession = session
                    }
                    .disabled(isSidebarDragging)
                }

                if filteredSessions.isEmpty {
                    emptyState
                }
            }
        }
        .scrollDisabled(isSidebarDragging)
        .scrollDismissesKeyboard(.immediately)
        .navigationDestination(item: $selectedSession) { session in
            ChatView(session: session)
        }
    }

    private var emptyState: some View {
        let isSearching = !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        return VStack(spacing: 16) {
            Image(systemName: isSearching ? "magnifyingglass" : "bubble.left.and.bubble.right")
                .resizable()
                .scaledToFit()
                .frame(width: isSearching ? 36 : 64, height: isSearching ? 36 : 64)
                .foregroundStyle(Color(.systemGray4))

            VStack(spacing: 4) {
                Text(isSearching ? "无搜索结果" : "暂无会话")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.secondary)
                Text(isSearching ? "试试其他关键词" : "开始一段新的对话")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 120)
    }
}

// MARK: - Session Row Container with Custom Swipe

struct SessionRowContainer: View {
    @Environment(AppState.self) private var appState
    let session: Session
    @Binding var activeSwipeId: String?
    var onTap: () -> Void = {}

    @State private var offset: CGFloat = 0
    @State private var initialDragOffset: CGFloat = 0
    @State private var isDragging = false
    @State private var showDeleteConfirm = false
    @State private var lastHapticStage: SessionSwipeStage = .closed

    private let selectionHaptic = UISelectionFeedbackGenerator()
    private let rigidHaptic = UIImpactFeedbackGenerator(style: .rigid)
    private let heavyHaptic = UIImpactFeedbackGenerator(style: .heavy)

    private var metrics: SessionSwipeMetrics {
        SessionSwipeBehavior.metrics(for: offset)
    }

    private var settleAnimation: Animation {
        .interactiveSpring(response: 0.26, dampingFraction: 0.88, blendDuration: 0.08)
    }

    private var resetAnimation: Animation {
        .interactiveSpring(response: 0.22, dampingFraction: 0.92, blendDuration: 0.04)
    }

    var body: some View {
        ZStack(alignment: .trailing) {
            actionButtons
            foregroundRow
        }
        .frame(height: 64)
        .clipped()
        .contextMenu {
            Button {
                selectionHaptic.selectionChanged()
                togglePin()
            } label: {
                Label(
                    session.isPinned ? "取消置顶" : "置顶会话",
                    systemImage: session.isPinned ? "pin.slash" : "pin"
                )
            }

            Divider()

            Button(role: .destructive) {
                armDeleteAndConfirm()
            } label: {
                Label("删除会话", systemImage: "trash")
            }
        } preview: {
            SessionPreviewView(
                session: session,
                agent: appState.agent(for: session.agentId),
                messages: Array(appState.messages(for: session.id).suffix(6)),
                theme: appState.currentVisualTheme
            )
        }
        .alert("删除会话？", isPresented: $showDeleteConfirm) {
            Button("删除", role: .destructive) {
                withAnimation(.interactiveSpring(response: 0.2, dampingFraction: 0.96)) {
                    appState.deleteSession(id: session.id)
                }
            }
        } message: {
            Text("该会话将被永久删除，无法恢复。")
        }
        .onChange(of: showDeleteConfirm) { _, isPresented in
            if !isPresented {
                closeSwipe(animated: true)
            }
        }
        .onChange(of: activeSwipeId) { _, newId in
            if newId != session.id && offset != 0 {
                closeSwipe(animated: true)
            }
        }
    }

    // MARK: - Action Buttons

    private var actionButtons: some View {
        let railWidth = max(0, metrics.railWidth)
        let pinOpacity = min(1, max(0, metrics.pinWidth / max(SessionSwipeBehavior.pinBaseWidth, 1)))
        let deleteIconSize = 18 + (metrics.deleteIconScale - 1) * 10

        return HStack(spacing: 0) {
            Button {
                selectionHaptic.selectionChanged()
                togglePin()
            } label: {
                ZStack {
                    Color.indigo
                    Image(systemName: session.isPinned ? "pin.slash.fill" : "pin.fill")
                        .font(.system(size: 18, weight: .medium))
                        .foregroundStyle(.white)
                        .opacity(pinOpacity)
                }
                .frame(width: max(0, metrics.pinWidth))
            }
            .buttonStyle(.plain)
            .opacity(metrics.pinWidth > 2 ? 1 : 0.001)

            Button {
                armDeleteAndConfirm()
            } label: {
                ZStack {
                    Color.red
                    Image(systemName: "trash")
                        .font(.system(size: deleteIconSize, weight: .medium))
                        .foregroundStyle(.white)
                }
                .frame(width: max(0, metrics.deleteWidth))
            }
            .buttonStyle(.plain)
            .opacity(metrics.deleteWidth > 2 ? 1 : 0.001)
        }
        .frame(width: railWidth, alignment: .trailing)
        .clipped()
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .trailing)
        .opacity(metrics.stage == .closed ? 0 : 1)
    }

    // MARK: - Foreground Row

    private var foregroundRow: some View {
        SessionRowView(session: session)
            .background(Color(.systemBackground).opacity(0.001))
            .contentShape(Rectangle())
            .offset(x: offset)
            .gesture(
                DragGesture(minimumDistance: 14)
                    .onChanged { value in
                        let dx = value.translation.width
                        let dy = value.translation.height

                        if !isDragging {
                            guard abs(dx) > abs(dy) * 1.3 else { return }
                            isDragging = true
                            initialDragOffset = offset
                            lastHapticStage = SessionSwipeBehavior.stage(for: offset)
                            selectionHaptic.prepare()
                            rigidHaptic.prepare()
                            heavyHaptic.prepare()
                            activeSwipeId = session.id
                        }

                        let nextOffset = SessionSwipeBehavior.interactiveOffset(
                            initialOffset: initialDragOffset,
                            translation: dx
                        )
                        offset = nextOffset
                        updateHaptics(for: nextOffset)
                    }
                    .onEnded { value in
                        isDragging = false
                        let predictedOffset = SessionSwipeBehavior.interactiveOffset(
                            initialOffset: initialDragOffset,
                            translation: value.predictedEndTranslation.width
                        )
                        let target = SessionSwipeBehavior.settleTarget(
                            currentOffset: offset,
                            predictedEndOffset: predictedOffset,
                            velocity: value.velocity.width
                        )
                        settle(to: target)
                    }
            )
            .onTapGesture {
                if offset < -10 {
                    closeSwipe(animated: true)
                } else if !isDragging {
                    onTap()
                }
            }
    }

    private func togglePin() {
        withAnimation(settleAnimation) {
            appState.togglePinSession(id: session.id)
        }
        closeSwipe(animated: true)
    }

    private func armDeleteAndConfirm() {
        let armedOffset = SessionSwipeBehavior.targetOffset(for: .armedForDelete)
        withAnimation(settleAnimation) {
            offset = armedOffset
        }
        activeSwipeId = session.id
        lastHapticStage = .armedForDelete
        showDeleteConfirm = true
    }

    private func closeSwipe(animated: Bool) {
        let closeBlock = {
            offset = 0
            activeSwipeId = nil
            lastHapticStage = .closed
        }

        if animated {
            withAnimation(resetAnimation, closeBlock)
        } else {
            closeBlock()
        }
    }

    private func settle(to target: SessionSwipeSettleTarget) {
        let targetOffset = SessionSwipeBehavior.targetOffset(for: target)

        withAnimation(settleAnimation) {
            offset = targetOffset
            if target == .closed {
                activeSwipeId = nil
            }
        }

        lastHapticStage = SessionSwipeBehavior.stage(for: targetOffset)

        if target == .armedForDelete {
            showDeleteConfirm = true
        }
    }

    private func updateHaptics(for offset: CGFloat) {
        let nextStage = SessionSwipeBehavior.stage(for: offset)
        guard nextStage != lastHapticStage else { return }

        switch nextStage {
        case .actionsRevealed:
            if lastHapticStage == .closed {
                selectionHaptic.selectionChanged()
            }
        case .deleteDominant:
            if lastHapticStage == .closed || lastHapticStage == .actionsRevealed {
                rigidHaptic.impactOccurred(intensity: 0.82)
            }
        case .armedForDelete:
            heavyHaptic.impactOccurred(intensity: 0.96)
        case .closed:
            break
        }

        lastHapticStage = nextStage
    }
}

// MARK: - Session Context-Menu Preview

struct SessionPreviewView: View {
    let session: Session
    let agent: Agent?
    let messages: [StoredMessage]
    let theme: AppVisualTheme

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            previewHeader
            Divider()

            if messages.isEmpty {
                emptyPlaceholder
            } else {
                messageList
            }
        }
        .frame(width: 320)
        .background(
            LinearGradient(
                colors: [theme.pageGradientTop, theme.pageGradientBottom],
                startPoint: .top,
                endPoint: .bottom
            )
        )
    }

    private var previewHeader: some View {
        HStack(spacing: 10) {
            AgentAvatarView(
                agentId: agent?.id,
                avatar: agent?.avatar,
                theme: theme,
                size: 32
            )
            VStack(alignment: .leading, spacing: 2) {
                Text(agent?.name ?? "Unknown")
                    .font(.subheadline.weight(.semibold))
                Text(session.timeAgo)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private var messageList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(spacing: 0) {
                    ForEach(messages) { msg in
                        previewBubble(msg)
                            .id(msg.id)
                    }
                }
                .padding(.vertical, 8)
            }
            .frame(maxHeight: 360)
            .task(id: SessionPreviewScrollAnchorResolver.initialAnchorMessageID(in: messages)) {
                guard let anchorId = SessionPreviewScrollAnchorResolver.initialAnchorMessageID(in: messages) else {
                    return
                }

                try? await Task.sleep(for: .milliseconds(24))

                await MainActor.run {
                    var transaction = Transaction()
                    transaction.animation = nil
                    withTransaction(transaction) {
                        proxy.scrollTo(anchorId, anchor: .bottom)
                    }
                }
            }
        }
    }

    private func previewBubble(_ msg: StoredMessage) -> some View {
        let isUser = msg.role == .user
        return HStack {
            if isUser { Spacer(minLength: 48) }

            Text(msg.previewText)
                .font(.caption)
                .lineSpacing(2)
                .lineLimit(4)
                .foregroundStyle(isUser ? .white : .primary)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(isUser ? theme.accent : Color(.systemGray5))
                )

            if !isUser { Spacer(minLength: 48) }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 3)
    }

    private var emptyPlaceholder: some View {
        Text("暂无消息")
            .font(.caption)
            .foregroundStyle(.tertiary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 40)
    }
}

enum SessionPreviewScrollAnchorResolver {
    static func initialAnchorMessageID(in messages: [StoredMessage]) -> String? {
        messages.last?.id
    }
}

// MARK: - Session Row

struct SessionRowView: View {
    @Environment(AppState.self) private var appState
    let session: Session

    private var agent: Agent? {
        appState.agent(for: session.agentId)
    }

    var body: some View {
        HStack(spacing: 12) {
            agentAvatar(agent, size: 44)

            VStack(alignment: .leading, spacing: 3) {
                HStack {
                    Text(agent?.name ?? "Unknown")
                        .font(.body)
                        .fontWeight(.semibold)
                        .foregroundStyle(.primary)
                    Spacer()
                    Text(session.timeAgo)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }

                if let lastMessage = session.lastMessage {
                    Text(lastMessage)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            if session.isPinned {
                Image(systemName: "pin.fill")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .rotationEffect(.degrees(45))
            }

            if session.unreadCount > 0 {
                Text("\(session.unreadCount)")
                    .font(.caption2)
                    .fontWeight(.bold)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 6)
                    .frame(minWidth: 20, minHeight: 20)
                    .background(Color(.label), in: Capsule())
            }
        }
        .padding(.horizontal, AppTheme.Spacing.lg)
        .padding(.vertical, 10)
        .contentShape(Rectangle())
    }

    private func agentAvatar(_ agent: Agent?, size: CGFloat) -> some View {
        Group {
            if let agentId = agent?.id, let custom = AvatarStorage.load(for: agentId) {
                Image(uiImage: custom)
                    .resizable()
                    .scaledToFill()
            } else if let avatar = agent?.avatar, !avatar.isEmpty, UIImage(named: avatar) != nil {
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
}
