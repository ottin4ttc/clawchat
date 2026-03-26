import SwiftUI
import UIKit
import ClawChatKit
import MessagingUI
import PhotosUI
import UniformTypeIdentifiers
import Speech

@MainActor
struct ChatView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss
    let session: Session
    @State private var inputText = ""
    @State private var selectedModel = ""
    
    @State private var showPhotoPicker = false
    @State private var showFileImporter = false
    @State private var selectedPhotoItems: [PhotosPickerItem] = []
    @State private var composerAttachments: [ComposerAttachment] = []
    @State private var attachmentErrorMessage: String?
    @State private var isVoiceRecording = false
    @State private var isVoiceStarting = false
    @State private var isVoiceCancelActive = false
    @State private var speechService = SpeechRecognitionService()
    @State private var showSpeechPermissionAlert = false
    @State private var speechPermissionMessage = ""
    @State private var isVoiceFinalizing = false
    @State private var voiceFinalizeTask: Task<Void, Never>?
    @State private var isWalkieTalkieRecording = false
    @FocusState private var isInputFocused: Bool
    @State private var messageDataSource = ListDataSource<MessageBubbleItem>()
    @State private var renderedMessages: [MessageBubbleItem] = []
    @State private var tiledScrollPosition = TiledScrollPosition(
        autoScrollsToBottomOnAppend: true,
        scrollsToBottomOnReplace: true
    )
    @State private var isNearBottom = true

    private let hapticRigid = UIImpactFeedbackGenerator(style: .rigid)
    private let hapticSoft = UIImpactFeedbackGenerator(style: .soft)
    private let maxAttachmentBytes = 5 * 1024 * 1024
    private let composerRowMinHeight: CGFloat = 24
    private let voiceComposerHeight: CGFloat = 64
    private let voiceActionButtonHeight: CGFloat = 36
    private let voiceActionExpandedWidth: CGFloat = 82
    private let voiceActionCollapsedWidth: CGFloat = 36
    private let voiceActionAnimation: Animation = .snappy(
        duration: 0.14,
        extraBounce: 0.02
    )

    private enum VoiceActionVisualState: Equatable {
        case idle
        case starting
        case recording
        case finalizing
    }

    private struct RenderSyncSignature: Equatable {
        let storedCount: Int
        let lastStoredItem: MessageBubbleItem?
        let livePreviewItem: MessageBubbleItem?
    }

    private var agent: Agent? {
        appState.agent(for: session.agentId)
    }

    private var chatManager: ClawChatManager {
        appState.clawChatManager
    }

    private var hasTextInput: Bool {
        !inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var hasDraftContent: Bool {
        hasTextInput || !composerAttachments.isEmpty
    }

    private var currentTheme: AppVisualTheme {
        appState.currentVisualTheme
    }

    private var resolvedModels: [String] {
        if let models = agent?.availableModels?.filter({ !$0.isEmpty }), !models.isEmpty {
            return models
        }
        if let model = agent?.model, !model.isEmpty {
            return [model]
        }
        return []
    }

    private var storedMessages: [StoredMessage] {
        appState.messages(for: session.id)
    }

    private var sessionLiveMessages: [ChatMessage] {
        chatManager.liveMessages(for: session.agentId, sessionKey: session.sessionKey)
    }

    private var isSessionTyping: Bool {
        chatManager.isTyping(for: session.agentId, sessionKey: session.sessionKey)
    }

    private var renderSyncSignature: RenderSyncSignature {
        let livePreview = ChatRenderPipeline.previewAssistantMessage(
            storedMessages: storedMessages,
            liveMessages: sessionLiveMessages
        )
        return RenderSyncSignature(
            storedCount: storedMessages.count,
            lastStoredItem: storedMessages.last.map(MessageBubbleItem.init(storedMessage:)),
            livePreviewItem: livePreview.map(MessageBubbleItem.init(chatMessage:))
        )
    }

    private var isEmpty: Bool {
        renderedMessages.isEmpty
    }

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [currentTheme.pageGradientTop, currentTheme.pageGradientBottom],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            VStack(spacing: 0) {
                connectionBanner
                messageArea
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                inputBar
            }

            if isEmpty {
                emptyStateOverlay
                    .allowsHitTesting(false)
                    .ignoresSafeArea(.keyboard, edges: .bottom)
            }
        }
        .background(
            SiriGlowWindowPresenter(
                isActive: isVoiceRecording || isVoiceStarting,
                dimmed: isVoiceCancelActive,
                prefersKeyboardTopLayout: false
            )
        )
        .background(InteractivePopGestureEnabler())
        .navigationBarBackButtonHidden(true)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button {
                    dismiss()
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 17, weight: .semibold))

                        AgentAvatarView(
                            agentId: agent?.id,
                            avatar: agent?.avatar,
                            theme: currentTheme,
                            size: 20,
                            showsBackground: false
                        )
                    }
                }
                .tint(.primary)
            }
        }
        .toolbarBackgroundVisibility(.visible, for: .navigationBar)
        .toolbar(.hidden, for: .tabBar)
        .onAppear {
            syncSelectedModel()
            refreshMessageSnapshot()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                hapticRigid.prepare()
                hapticSoft.prepare()
            }
            Task {
                try? await Task.sleep(for: .seconds(1.5))
                await speechService.prepareFastStartIfAuthorized()
            }
        }
        .onChange(of: agent?.id) { _, _ in
            syncSelectedModel()
        }
        .onChange(of: renderSyncSignature) { _, _ in
            refreshMessageSnapshot()
        }
        .photosPicker(
            isPresented: $showPhotoPicker,
            selection: $selectedPhotoItems,
            maxSelectionCount: 8,
            matching: .any(of: [.images])
        )
        .fileImporter(
            isPresented: $showFileImporter,
            allowedContentTypes: [.item],
            allowsMultipleSelection: true
        ) { result in
            handleImportedFiles(result)
        }
        .onChange(of: selectedPhotoItems) { _, items in
            guard !items.isEmpty else { return }
            Task {
                await importPhotoAttachments(from: items)
                await MainActor.run {
                    selectedPhotoItems = []
                }
            }
        }
        .alert("无法添加附件", isPresented: Binding(
            get: { attachmentErrorMessage != nil },
            set: { newValue in
                if !newValue { attachmentErrorMessage = nil }
            }
        )) {
            Button("知道了", role: .cancel) { }
        } message: {
            Text(attachmentErrorMessage ?? "")
        }
        .alert("语音识别不可用", isPresented: $showSpeechPermissionAlert) {
            Button("前往设置") {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            }
            Button("取消", role: .cancel) { }
        } message: {
            Text(speechPermissionMessage)
        }
        .onDisappear {
            voiceFinalizeTask?.cancel()
            isWalkieTalkieRecording = false
            isVoiceStarting = false
            if speechService.isRecording {
                speechService.stopRecording()
            }
        }
    }

    // MARK: - Connection Status

    @ViewBuilder
    private var connectionBanner: some View {
        switch chatManager.linkState {
        case .connecting:
            HStack(spacing: 6) {
                ProgressView().controlSize(.mini)
                Text("正在连接 Gateway…")
                    .font(.caption)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 6)
            .background(Color.orange.opacity(0.15))

        case .disconnected, .error:
            HStack(spacing: 6) {
                Image(systemName: "wifi.slash")
                    .font(.caption)
                Text("连接已断开")
                    .font(.caption)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 6)
            .background(Color.red.opacity(0.12))

        default:
            EmptyView()
        }
    }

    // MARK: - Messages

    private var messageArea: some View {
        TiledView(
            dataSource: messageDataSource,
            scrollPosition: $tiledScrollPosition
        ) { item in
            MessageBubbleTiledCell(item: item, theme: currentTheme)
        }
        .typingIndicator(.indicator(isVisible: isSessionTyping) {
            HStack(alignment: .bottom) {
                TypingBreathingDotsView()
                    .padding(.horizontal, 16)
                    .padding(.vertical, 14)
                    .background(
                        RoundedRectangle(cornerRadius: 22, style: .continuous)
                            .fill(Color(.systemGray5))
                    )
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 6)
        })
        .onTapBackground {
            isInputFocused = false
        }
        .onDragIntoBottomSafeArea {
            isInputFocused = false
        }
        .onTiledScrollGeometryChange { geometry in
            let nearBottom = geometry.pointsFromBottom < 100
            isNearBottom = nearBottom
            tiledScrollPosition.autoScrollsToBottomOnAppend = nearBottom
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onChange(of: sessionLiveMessages.count) { _, _ in
            syncLiveMessages()
        }
        .onChange(of: sessionLiveMessages.last?.isStreaming) { _, isStreaming in
            if isStreaming == false {
                syncLiveMessages()
            }
        }
    }

    private func refreshMessageSnapshot(forceScrollToBottom: Bool = false, animated: Bool = false) {
        let newMessages = ChatRenderPipeline.renderedMessages(
            storedMessages: storedMessages,
            liveMessages: sessionLiveMessages
        )
        let previousLastMessage = renderedMessages.last
        let nextLastMessage = newMessages.last
        let didTailMessageChange = previousLastMessage?.id == nextLastMessage?.id
            && previousLastMessage != nextLastMessage
        let didSnapshotChange = newMessages != renderedMessages

        guard forceScrollToBottom || didSnapshotChange else { return }

        if didSnapshotChange {
            renderedMessages = newMessages
            messageDataSource.apply(newMessages)
        }

        if forceScrollToBottom {
            tiledScrollPosition.scrollTo(edge: .bottom, animated: animated)
            return
        }

        guard didSnapshotChange, isNearBottom, didTailMessageChange, nextLastMessage?.isStreaming == true else { return }
        tiledScrollPosition.scrollTo(edge: .bottom, animated: false)
    }

    private func syncLiveMessages() {
        let live = sessionLiveMessages
        let stored = appState.messages(for: session.id)
        let storedIds = Set(stored.map(\.id))
        var newlyPersistedIds = Set<String>()

        for msg in live {
            if msg.isStreaming { continue }
            if msg.role == .user { continue }

            if storedIds.contains(msg.id) {
                appState.updateMessage(in: session.id, messageId: msg.id, text: msg.text)
                newlyPersistedIds.insert(msg.id)
            } else {
                let stored = StoredMessage(
                    id: msg.id,
                    role: .assistant,
                    text: msg.text,
                    reasoning: msg.reasoning,
                    timestamp: msg.timestamp
                )
                appState.appendMessage(to: session.id, message: stored)
                newlyPersistedIds.insert(msg.id)
            }
        }

        // Clean up persisted messages from live state to prevent replay
        if !newlyPersistedIds.isEmpty {
            chatManager.chatState?.clearCompletedMessages(persistedIds: newlyPersistedIds)
        }

        refreshMessageSnapshot()
    }

    private var emptyStateOverlay: some View {
        GeometryReader { geo in
            let logoY = isInputFocused ? geo.size.height * 0.24 : geo.size.height * 0.34

            Group {
                if let themeLogo = currentTheme.themeLogoAssetName {
                    Image(themeLogo)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 100, height: 100)
                        .opacity(0.35)
                } else {
                    Image("clawos_watermark")
                        .resizable()
                        .renderingMode(.template)
                        .scaledToFit()
                        .frame(width: 72, height: 72)
                        .foregroundStyle(currentTheme.logoTint)
                }
            }
            .position(x: geo.size.width / 2, y: logoY)
            .animation(.easeOut(duration: 0.22), value: isInputFocused)
        }
    }

    // MARK: - Input Bar

    private var inputBar: some View {
        standardInputBar
            .fixedSize(horizontal: false, vertical: true)
        .padding(.horizontal, 12)
        .padding(.bottom, 8)
    }

    private var standardInputBar: some View {
        VStack(spacing: 0) {
            if !isVoiceActive && !composerAttachments.isEmpty {
                composerAttachmentStrip
            }

            HStack(alignment: .center, spacing: 0) {
                composerFieldSurface
                
                if isVoiceActive {
                    voiceActionButton
                        .padding(.trailing, 10)
                }
            }

            if !isVoiceActive {
                HStack(spacing: 8) {
                    attachmentButton
                    modelMenu
                    Spacer()
                    if hasDraftContent {
                        sendButton
                    } else {
                        voiceActionButton
                    }
                }
                .padding(.horizontal, 12)
                .padding(.bottom, 10)
            }
        }
        .background(inputBarBackground)
    }

    private let voiceCancelDragThreshold: CGFloat = 50

    private var inputBarBackground: some View {
        Color.clear
            .adaptiveGlass(in: .rect(cornerRadius: 24))
            .shadow(color: .black.opacity(0.06), radius: 12, x: 0, y: 4)
            .shadow(color: .black.opacity(0.04), radius: 24, x: 0, y: 12)
    }

    private var attachmentButton: some View {
        Menu {
            Button {
                showPhotoPicker = true
            } label: {
                Label("照片", systemImage: "photo.on.rectangle")
            }
            Button {
                showFileImporter = true
            } label: {
                Label("文件", systemImage: "doc")
            }
        } label: {
            Image(systemName: "paperclip")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(currentTheme.accent)
                .frame(width: 32, height: 32)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .adaptiveGlass(in: .circle)
    }

    // MARK: - Input Field

    private var composerFieldSurface: some View {
        ZStack(alignment: .topLeading) {
            textField
                .opacity(isVoiceCancelActive ? 0 : 1)

            if isVoiceActive {
                activeRecordingField
            }
        }
        .overlay {
            WalkieTalkieGestureView(
                isEnabled: ChatVoiceOverlayPolicy.isWalkieTalkieOverlayEnabled(
                    isInputFocused: isInputFocused,
                    isVoiceRecording: isVoiceRecording,
                    isVoiceFinalizing: isVoiceFinalizing,
                    isWalkieTalkieRecording: isWalkieTalkieRecording
                ) && !isVoiceStarting,
                onTap: { isInputFocused = true },
                onRecordStart: {
                    guard !isVoiceStarting, !isVoiceRecording else { return }
                    isVoiceStarting = true
                    isWalkieTalkieRecording = true
                    hapticRigid.impactOccurred()
                    Task { await beginRecording() }
                },
                onDragChanged: { dy in
                    guard isVoiceRecording else { return }
                    let shouldCancel = dy < -voiceCancelDragThreshold
                    if shouldCancel != isVoiceCancelActive {
                        withAnimation(.easeInOut(duration: 0.12)) {
                            isVoiceCancelActive = shouldCancel
                        }
                        if shouldCancel {
                            hapticSoft.impactOccurred()
                        }
                    }
                },
                onRecordEnd: {
                    guard isWalkieTalkieRecording else { return }
                    isWalkieTalkieRecording = false
                    endRecording()
                }
            )
        }
    }

    private var composerAttachmentStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(composerAttachments) { attachment in
                    HStack(spacing: 8) {
                        Image(systemName: attachment.iconName)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(currentTheme.accent)

                        VStack(alignment: .leading, spacing: 2) {
                            Text(attachment.filename)
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.primary)
                                .lineLimit(1)
                            Text(attachment.displaySize)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }

                        Button {
                            composerAttachments.removeAll { $0.id == attachment.id }
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    .background(Color(.systemGray6), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
            }
            .padding(.horizontal, 12)
            .padding(.top, 12)
        }
    }

    private var activeRecordingField: some View {
        HStack(spacing: 6) {
            Spacer(minLength: 0)
            Image(systemName: "arrow.uturn.left.circle.fill")
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(Color.red.opacity(0.85))

            Text("松开以取消")
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(Color.red.opacity(0.85))

            Spacer(minLength: 0)
        }
        .opacity(isVoiceCancelActive ? 1 : 0)
        .padding(.horizontal, 16)
        .padding(.top, 14)
        .padding(.bottom, isVoiceActive ? 14 : 2)
        .frame(minHeight: composerRowMinHeight, alignment: .topLeading)
        .frame(maxWidth: .infinity, alignment: .leading)
        .animation(.easeInOut(duration: 0.15), value: isVoiceCancelActive)
    }

    private var isVoiceActive: Bool {
        isVoiceStarting || isVoiceRecording || isVoiceFinalizing
    }

    private var textField: some View {
        let placeholder = isVoiceActive ? "正在聆听…" : "输入消息或长按录音..."
        return TextField(placeholder, text: $inputText, axis: .vertical)
            .lineLimit(isVoiceActive ? 1...1 : 1...6)
            .textFieldStyle(.plain)
            .font(.system(size: 16, weight: .regular, design: .default))
            .foregroundStyle(isVoiceActive ? AnyShapeStyle(Color.secondary) : AnyShapeStyle(Color.primary))
            .tint(currentTheme.accent)
            .focused($isInputFocused)
            .padding(.horizontal, 18)
            .padding(.top, 14)
            .padding(.bottom, isVoiceActive ? 14 : 4)
            .frame(minHeight: composerRowMinHeight, alignment: .topLeading)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func endRecording() {
        guard isVoiceRecording else { return }
        hapticSoft.impactOccurred()
        let wasCancelled = isVoiceCancelActive

        let finalText = speechService.stopRecording()
            .trimmingCharacters(in: .whitespacesAndNewlines)

        voiceFinalizeTask?.cancel()

        withAnimation(voiceActionAnimation) {
            isVoiceStarting = false
            isVoiceRecording = false
            isVoiceCancelActive = false
            isVoiceFinalizing = !wasCancelled && !finalText.isEmpty
        }

        guard !wasCancelled, !finalText.isEmpty else {
            return
        }

        voiceFinalizeTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(45))
            guard !Task.isCancelled else { return }

            inputText = finalText
            withAnimation(voiceActionAnimation) {
                isVoiceFinalizing = false
            }
            voiceFinalizeTask = nil
        }
    }

    // MARK: - Model Menu (native)

    @ViewBuilder
    private var modelMenu: some View {
        if resolvedModels.count > 1 {
            Menu {
                ForEach(resolvedModels, id: \.self) { model in
                    Button {
                        selectedModel = model
                    } label: {
                        Label {
                            VStack(alignment: .leading) {
                                Text(modelDisplayTitle(for: model))
                                Text(modelSubtitle(for: model))
                            }
                        } icon: {
                            if model == selectedModel {
                                Image(systemName: "checkmark")
                            } else {
                                Image(systemName: modelIcon(for: model))
                            }
                        }
                    }
                }
            } label: {
                modelChip(showChevron: true)
            }
            .adaptiveGlass(in: .capsule)
        } else {
            modelChip(showChevron: false)
                .adaptiveGlass(in: .capsule)
        }
    }

    private func modelChip(showChevron: Bool) -> some View {
        HStack(spacing: 4) {
            Text(modelDisplayTitle(for: selectedModel))
                .font(.system(size: 12, weight: .medium))
                .lineLimit(1)
            if showChevron {
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 9, weight: .semibold))
            }
        }
        .foregroundStyle(.secondary)
        .padding(.horizontal, 10)
        .frame(height: 30)
        .contentShape(Capsule())
    }

    private func modelDisplayTitle(for model: String) -> String {
        var name = model
        if let lastSlash = model.lastIndex(of: "/") {
            name = String(model[model.index(after: lastSlash)...])
        }

        name = name
            .replacingOccurrences(of: "-preview", with: "")
            .replacingOccurrences(of: "-latest", with: "")

        let parts = name.split(separator: "-")
        if parts.isEmpty { return model }

        var result: [String] = []
        for part in parts {
            let s = String(part)
            if s.allSatisfy({ $0.isNumber || $0 == "." }) {
                result.append(s)
            } else {
                result.append(s.prefix(1).uppercased() + s.dropFirst())
            }
        }
        return result.joined(separator: " ")
    }

    private func modelSubtitle(for model: String) -> String {
        let lower = model.lowercased()
        if lower.contains("opus") { return "Most capable model" }
        if lower.contains("sonnet") { return "Balanced speed and quality" }
        if lower.contains("haiku") { return "Fastest responses" }
        if lower.contains("gpt") { return "General purpose" }
        if lower.contains("minimax") { return "Balanced speed and reasoning" }
        if lower.contains("deepseek") { return "Open source reasoning" }
        return model
    }

    private func modelIcon(for model: String) -> String {
        let lower = model.lowercased()
        if lower.contains("claude") { return "brain.head.profile" }
        if lower.contains("gpt") { return "sparkles" }
        if lower.contains("gemini") { return "wand.and.stars" }
        if lower.contains("minimax") { return "bolt" }
        if lower.contains("deepseek") { return "magnifyingglass" }
        return "cpu"
    }

    // MARK: - Buttons

    private var sendButton: some View {
        Button {
            sendCurrentMessage()
        } label: {
            Image(systemName: "arrow.up")
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(Color(.systemBackground))
                .frame(width: 32, height: 32)
                .background(Color(.label), in: Circle())
        }
        .buttonStyle(.plain)
    }

    private var voiceActionState: VoiceActionVisualState {
        if isVoiceFinalizing { return .finalizing }
        if isVoiceRecording { return .recording }
        if isVoiceStarting { return .starting }
        return .idle
    }

    private var canStartVoiceFromTap: Bool {
        ChatVoiceOverlayPolicy.allowsDirectSpeakTap(
            isInputFocused: isInputFocused,
            isVoiceRecording: isVoiceRecording,
            isVoiceFinalizing: isVoiceFinalizing,
            isWalkieTalkieRecording: isWalkieTalkieRecording
        ) && !isVoiceStarting
    }

    private var voiceActionButton: some View {
        let state = voiceActionState

        return Button {
            handleVoiceActionTap(for: state)
        } label: {
            ZStack {
                HStack(spacing: 4) {
                    Image(systemName: "waveform")
                        .font(.system(size: 13, weight: .bold))
                    Text("Speak")
                        .font(.system(size: 14, weight: .bold))
                }
                .opacity(state == .idle ? 1 : 0)
                .scaleEffect(state == .idle ? 1 : 0.93)
                .blur(radius: state == .idle ? 0 : 1)

                Image(systemName: voiceActionSymbolName(for: state))
                    .font(.system(size: 14, weight: .bold))
                    .opacity(state == .idle ? 0 : 1)
                    .scaleEffect(state == .idle ? 0.72 : 1)
            }
            .foregroundStyle(Color.white)
            .frame(
                width: state == .idle ? voiceActionExpandedWidth : voiceActionCollapsedWidth,
                height: voiceActionButtonHeight
            )
            .background(voiceActionBackground(for: state), in: Capsule())
            .overlay {
                Capsule()
                    .stroke(Color.white.opacity(state == .idle ? 0.08 : 0.18), lineWidth: 0.8)
            }
            .shadow(
                color: voiceActionShadowColor(for: state),
                radius: state == .idle ? 0 : 8,
                y: state == .idle ? 0 : 3
            )
            .scaleEffect(state == .starting ? 0.985 : 1)
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .allowsHitTesting(voiceActionAllowsHitTesting(for: state))
        .animation(voiceActionAnimation, value: state)
    }

    private func handleVoiceActionTap(for state: VoiceActionVisualState) {
        switch state {
        case .idle:
            guard canStartVoiceFromTap else { return }
            isVoiceStarting = true
            hapticRigid.impactOccurred()
            Task { await beginRecording() }
        case .recording:
            endRecording()
        case .starting, .finalizing:
            break
        }
    }

    private func voiceActionAllowsHitTesting(for state: VoiceActionVisualState) -> Bool {
        switch state {
        case .idle:
            canStartVoiceFromTap
        case .recording:
            true
        case .starting, .finalizing:
            false
        }
    }

    private func voiceActionSymbolName(for state: VoiceActionVisualState) -> String {
        switch state {
        case .idle:
            return "waveform"
        case .starting:
            return "stop.fill"
        case .recording:
            return "stop.fill"
        case .finalizing:
            return "checkmark"
        }
    }

    private func voiceActionBackground(for state: VoiceActionVisualState) -> Color {
        switch state {
        case .idle:
            return currentTheme.accent
        case .starting:
            return Color.red.opacity(0.92)
        case .recording:
            return .red
        case .finalizing:
            return currentTheme.accent
        }
    }

    private func voiceActionShadowColor(for state: VoiceActionVisualState) -> Color {
        switch state {
        case .recording, .starting:
            return Color.red.opacity(0.22)
        case .finalizing:
            return currentTheme.accent.opacity(0.18)
        case .idle:
            return .clear
        }
    }

    private func sendCurrentMessage() {
        let text = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        let attachments = composerAttachments
        guard !text.isEmpty || !attachments.isEmpty else { return }

        let userMsg = StoredMessage(
            id: UUID().uuidString,
            role: .user,
            text: text,
            attachments: attachments.map(\.storedAttachment),
            timestamp: Date()
        )
        appState.appendMessage(to: session.id, message: userMsg)
        refreshMessageSnapshot(forceScrollToBottom: true, animated: true)

        chatManager.sendMessage(
            text: text,
            agentId: session.agentId,
            sessionKey: session.sessionKey,
            attachments: attachments.map(\.protocolAttachment)
        )
        inputText = ""
        composerAttachments.removeAll()
    }

    private func beginRecording() async {
        guard isVoiceStarting, !isVoiceRecording else { return }

        isVoiceCancelActive = false

        if ChatVoiceOverlayPolicy.shouldDismissKeyboardBeforeRecording {
            isInputFocused = false
        }
        voiceFinalizeTask?.cancel()
        voiceFinalizeTask = nil
        isVoiceFinalizing = false

        let permissions = await SpeechRecognitionService.requestPermissionsIfNeeded()

        guard permissions.mic else {
            withAnimation(voiceActionAnimation) {
                isVoiceStarting = false
            }
            speechPermissionMessage = SpeechRecognitionService.SpeechError.microphoneDenied.localizedDescription
            showSpeechPermissionAlert = true
            return
        }
        guard permissions.speech else {
            withAnimation(voiceActionAnimation) {
                isVoiceStarting = false
            }
            speechPermissionMessage = SpeechRecognitionService.SpeechError.recognitionDenied.localizedDescription
            showSpeechPermissionAlert = true
            return
        }

        do {
            try speechService.startRecording()
            withAnimation(voiceActionAnimation) {
                isVoiceStarting = false
                isVoiceRecording = true
                isVoiceCancelActive = false
            }
        } catch {
            withAnimation(voiceActionAnimation) {
                isVoiceStarting = false
            }
            speechPermissionMessage = error.localizedDescription
            showSpeechPermissionAlert = true
        }
    }

    private func syncSelectedModel() {
        if let first = resolvedModels.first {
            selectedModel = first
        } else {
            selectedModel = agent?.model ?? "未识别"
        }
    }

    private func handleImportedFiles(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            Task {
                await importFileAttachments(from: urls)
            }
        case .failure(let error):
            attachmentErrorMessage = error.localizedDescription
        }
    }

    private func importPhotoAttachments(from items: [PhotosPickerItem]) async {
        for item in items {
            do {
                guard let data = try await item.loadTransferable(type: Data.self) else {
                    throw ComposerAttachmentPreparationError.unreadable("无法读取所选图片。")
                }

                let contentType = item.supportedContentTypes.first ?? .image
                let attachment = try await prepareComposerAttachmentInBackground(
                    data: data,
                    filename: "image-\(UUID().uuidString.prefix(8)).\(contentType.preferredFilenameExtension ?? "bin")",
                    mimeType: contentType.preferredMIMEType ?? "application/octet-stream",
                    type: Self.attachmentType(for: contentType)
                )
                await MainActor.run {
                    composerAttachments.append(attachment)
                }
            } catch {
                await MainActor.run {
                    attachmentErrorMessage = error.localizedDescription
                }
            }
        }
    }

    private func importFileAttachments(from urls: [URL]) async {
        for url in urls {
            do {
                let attachment = try await prepareFileAttachment(from: url)
                await MainActor.run {
                    composerAttachments.append(attachment)
                }
            } catch {
                await MainActor.run {
                    attachmentErrorMessage = error.localizedDescription
                }
            }
        }
    }

    private func prepareComposerAttachmentInBackground(
        data: Data,
        filename: String,
        mimeType: String,
        type: MessageAttachmentType
    ) async throws -> ComposerAttachment {
        try await Task.detached(priority: .userInitiated) { [maxAttachmentBytes] in
            try ComposerAttachment.prepared(
                data: data,
                filename: filename,
                mimeType: mimeType,
                type: type,
                maxBytes: maxAttachmentBytes
            )
        }.value
    }

    private func prepareFileAttachment(from url: URL) async throws -> ComposerAttachment {
        try await Task.detached(priority: .userInitiated) { [maxAttachmentBytes] in
            let scoped = url.startAccessingSecurityScopedResource()
            defer {
                if scoped {
                    url.stopAccessingSecurityScopedResource()
                }
            }

            let data = try Data(contentsOf: url, options: [.mappedIfSafe])
            let resourceValues = try url.resourceValues(forKeys: [.contentTypeKey, .nameKey])
            let contentType = resourceValues.contentType ?? UTType(filenameExtension: url.pathExtension) ?? .data
            let filename = resourceValues.name ?? url.lastPathComponent

            return try ComposerAttachment.prepared(
                data: data,
                filename: filename,
                mimeType: contentType.preferredMIMEType ?? "application/octet-stream",
                type: Self.attachmentType(for: contentType),
                maxBytes: maxAttachmentBytes
            )
        }.value
    }

    nonisolated private static func attachmentType(for contentType: UTType) -> MessageAttachmentType {
        if contentType.conforms(to: .image) {
            return .image
        }
        if contentType.conforms(to: .movie) || contentType.conforms(to: .video) {
            return .video
        }
        if contentType.conforms(to: .audio) {
            return .audio
        }
        return .file
    }
}

// MARK: - Walkie-Talkie Long-Press Gesture (UIKit)

private struct WalkieTalkieGestureView: UIViewRepresentable {
    var isEnabled: Bool
    var onTap: () -> Void
    var onRecordStart: () -> Void
    var onDragChanged: (CGFloat) -> Void
    var onRecordEnd: () -> Void

    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        view.backgroundColor = .clear

        let tap = UITapGestureRecognizer(
            target: context.coordinator,
            action: #selector(Coordinator.handleTap)
        )
        let longPress = UILongPressGestureRecognizer(
            target: context.coordinator,
            action: #selector(Coordinator.handleLongPress(_:))
        )
        longPress.minimumPressDuration = 0.4
        tap.cancelsTouchesInView = false
        longPress.cancelsTouchesInView = false
        longPress.delaysTouchesBegan = false

        view.addGestureRecognizer(tap)
        view.addGestureRecognizer(longPress)
        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        uiView.isUserInteractionEnabled = isEnabled
        context.coordinator.onTap = onTap
        context.coordinator.onRecordStart = onRecordStart
        context.coordinator.onDragChanged = onDragChanged
        context.coordinator.onRecordEnd = onRecordEnd
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject {
        var onTap: () -> Void
        var onRecordStart: () -> Void
        var onDragChanged: (CGFloat) -> Void
        var onRecordEnd: () -> Void
        private var startY: CGFloat = 0
        private var lastLongPressEndedAt: TimeInterval = -.greatestFiniteMagnitude

        init(_ parent: WalkieTalkieGestureView) {
            self.onTap = parent.onTap
            self.onRecordStart = parent.onRecordStart
            self.onDragChanged = parent.onDragChanged
            self.onRecordEnd = parent.onRecordEnd
        }

        @objc func handleTap() {
            let now = ProcessInfo.processInfo.systemUptime
            guard now - lastLongPressEndedAt > 0.1 else { return }
            onTap()
        }

        @objc func handleLongPress(_ gesture: UILongPressGestureRecognizer) {
            switch gesture.state {
            case .began:
                startY = gesture.location(in: gesture.view).y
                onRecordStart()
            case .changed:
                let dy = gesture.location(in: gesture.view).y - startY
                onDragChanged(dy)
            case .ended, .cancelled, .failed:
                lastLongPressEndedAt = ProcessInfo.processInfo.systemUptime
                onRecordEnd()
            default:
                break
            }
        }
    }
}

// MARK: - Re-enable interactive pop gesture when back button is hidden

enum InteractivePopGestureBehavior {
    static func configureIfNeeded(
        recognizer: UIGestureRecognizer?,
        hasConfigured: inout Bool
    ) {
        guard !hasConfigured, let recognizer else { return }
        recognizer.isEnabled = true
        recognizer.delegate = nil
        hasConfigured = true
    }
}

struct InteractivePopGestureEnabler: UIViewControllerRepresentable {
    func makeUIViewController(context: Context) -> UIViewController {
        InteractivePopController()
    }
    func updateUIViewController(_ uiViewController: UIViewController, context: Context) {}

    final class InteractivePopController: UIViewController {
        private var hasConfiguredInteractivePop = false

        override func viewDidAppear(_ animated: Bool) {
            super.viewDidAppear(animated)
            InteractivePopGestureBehavior.configureIfNeeded(
                recognizer: navigationController?.interactivePopGestureRecognizer,
                hasConfigured: &hasConfiguredInteractivePop
            )
        }
    }
}
