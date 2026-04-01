import SwiftUI

struct SessionListView: View {
    @Environment(AppState.self) private var appState
    @Binding var searchText: String

    @State private var debouncedQuery = ""
    @State private var searchDebounceTask: Task<Void, Never>?

    private static let searchDebounceMilliseconds = 250
    private static let maxMessageScanPerSession = 200

    private var filteredSessions: [Session] {
        let visibleAgentIds = Set(appState.selectedAgentIds)
        let gatewaySessions = appState.sessions.filter { visibleAgentIds.contains($0.agentId) }

        let sortedSessions = gatewaySessions.sorted { s1, s2 in
            if s1.isPinned != s2.isPinned {
                return s1.isPinned
            }
            return (s1.lastMessageTime ?? Date.distantPast) > (s2.lastMessageTime ?? Date.distantPast)
        }

        let query = debouncedQuery
        if query.isEmpty {
            return sortedSessions
        }
        return sortedSessions.filter { session in
            let agent = appState.agent(for: session.agentId)
            if session.title.localizedCaseInsensitiveContains(query) { return true }
            if agent?.name.localizedCaseInsensitiveContains(query) ?? false { return true }
            if session.lastMessage?.localizedCaseInsensitiveContains(query) ?? false { return true }

            let messages = appState.messages(for: session.id).suffix(Self.maxMessageScanPerSession)
            return messages.contains { $0.text.localizedCaseInsensitiveContains(query) }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            sessionList
        }
        .contentShape(Rectangle())
    }

    // MARK: - List

    @State private var selectedSession: Session?
    @State private var lastVisitedSessionId: String?
    @State private var activeSwipeId: String?

    private var sessionList: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(filteredSessions) { session in
                    SessionRowContainer(
                        session: session,
                        isSelected: lastVisitedSessionId == session.id,
                        activeSwipeId: $activeSwipeId
                    ) {
                        lastVisitedSessionId = session.id
                        selectedSession = session
                    }
                }

                if filteredSessions.isEmpty {
                    emptyState
                }
            }
        }
        .scrollDismissesKeyboard(.immediately)
        .navigationDestination(item: $selectedSession) { session in
            ChatView(session: session)
        }
        .onChange(of: searchText) { _, newText in
            searchDebounceTask?.cancel()
            let trimmed = newText.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty {
                debouncedQuery = ""
                return
            }
            searchDebounceTask = Task {
                try? await Task.sleep(for: .milliseconds(Self.searchDebounceMilliseconds))
                guard !Task.isCancelled else { return }
                debouncedQuery = trimmed
            }
        }
    }

    private var emptyState: some View {
        let isSearching = !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        return GeometryReader { geo in
            VStack(spacing: AppTheme.EmptyState.stackSpacing) {
                if isSearching {
                    Image(systemName: "magnifyingglass")
                        .resizable()
                        .scaledToFit()
                        .frame(
                            width: AppTheme.EmptyState.iconSize,
                            height: AppTheme.EmptyState.iconSize
                        )
                        .foregroundStyle(Color(.systemGray4))

                    VStack(spacing: AppTheme.EmptyState.textSpacing) {
                        Text("无搜索结果")
                            .font(.headline)
                            .foregroundStyle(Color(.secondaryLabel))
                        Text("试试其他关键词")
                            .font(.subheadline)
                            .foregroundStyle(Color(.tertiaryLabel))
                    }
                } else {
                    Image("clawos_svg_logo")
                        .resizable()
                        .renderingMode(.template)
                        .scaledToFit()
                        .frame(
                            width: AppTheme.EmptyState.iconSize,
                            height: AppTheme.EmptyState.iconSize
                        )
                        .foregroundStyle(Color(.systemGray4))

                    VStack(spacing: AppTheme.EmptyState.textSpacing) {
                        Text("暂无会话")
                            .font(.headline)
                            .foregroundStyle(Color(.secondaryLabel))
                        Text("新建一个会话开始聊天")
                            .font(.subheadline)
                            .foregroundStyle(Color(.tertiaryLabel))
                    }
                }
            }
            .frame(maxWidth: .infinity)
            .position(
                x: geo.size.width / 2,
                y: geo.size.height * AppTheme.EmptyState.contentAnchorRatio
            )
        }
        .frame(height: UIScreen.main.bounds.height * AppTheme.EmptyState.frameHeightRatio)
    }
}

// MARK: - Session Row Container with Custom Swipe

struct SessionRowContainer: View {
    @Environment(AppState.self) private var appState
    let session: Session
    var isSelected: Bool = false
    @Binding var activeSwipeId: String?
    var onTap: () -> Void = {}

    @State private var offset: CGFloat = 0
    @State private var initialDragOffset: CGFloat = 0
    @State private var isDragging = false
    @State private var showDeleteConfirm = false
    @State private var showRenameAlert = false
    @State private var newSessionTitle = ""
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
        .padding(.horizontal, 8)
        .padding(.vertical, 2)
        .contextMenu {
            Button {
                selectionHaptic.selectionChanged()
                newSessionTitle = session.title
                showRenameAlert = true
            } label: {
                Label("修改名字", systemImage: "pencil")
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
        .alert("修改名字", isPresented: $showRenameAlert) {
            TextField("会话名称", text: $newSessionTitle)
                .foregroundStyle(.primary)
            Button("取消", role: .cancel) {
                closeSwipe(animated: true)
            }
            Button("保存") {
                let trimmed = newSessionTitle.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty {
                    appState.renameSession(id: session.id, title: trimmed)
                }
                closeSwipe(animated: true)
            }
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
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .trailing)
        .opacity(metrics.stage == .closed ? 0 : 1)
    }

    // MARK: - Foreground Row

    private var foregroundRow: some View {
        Button(action: handleRowTap) {
            SessionRowView(session: session)
        }
        .buttonStyle(SessionRowButtonStyle(offset: offset, isSelected: isSelected))
        .highPriorityGesture(swipeGesture)
        .id(session.id)
    }

    private var swipeGesture: some Gesture {
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
    }

    private func handleRowTap() {
        if offset < -10 {
            closeSwipe(animated: true)
        } else if !isDragging {
            onTap()
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

struct SessionRowButtonStyle: ButtonStyle {
    var offset: CGFloat
    var isSelected: Bool = false
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(configuration.isPressed || isSelected ? Color(.systemGray6).opacity(0.5) : Color.clear)
            )
            .offset(x: offset)
            .animation(.easeInOut(duration: 0.15), value: isSelected)
            .animation(.easeInOut(duration: 0.1), value: configuration.isPressed)
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
                        .fill(isUser ? theme.accent : theme.softFill)
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

    private var theme: AppVisualTheme { appState.currentVisualTheme }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(session.title.isEmpty ? (agent?.name ?? "新会话") : session.title)
                    .font(.system(size: 16, weight: .regular))
                    .foregroundStyle(Color(.label))
                    .lineLimit(1)

                Spacer()

                Text(session.timeAgo)
                    .font(.system(size: 12))
                    .foregroundStyle(Color(.tertiaryLabel))

                if session.isPinned {
                    Image(systemName: "pin.fill")
                        .font(.system(size: 10))
                        .foregroundStyle(Color(.tertiaryLabel))
                        .rotationEffect(.degrees(45))
                }
            }

            HStack {
                if let preview = session.lastMessage, !preview.isEmpty {
                    Text(preview)
                        .font(.system(size: 13))
                        .foregroundStyle(Color(.secondaryLabel))
                        .lineLimit(1)
                } else {
                    Text("暂无消息")
                        .font(.system(size: 13))
                        .foregroundStyle(Color(.tertiaryLabel))
                }

                Spacer()

                if session.unreadCount > 0 {
                    Text("\(String(session.unreadCount))")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 6)
                        .frame(minWidth: 18, minHeight: 18)
                        .background(theme.accent, in: Capsule())
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .contentShape(Rectangle())
    }
}
