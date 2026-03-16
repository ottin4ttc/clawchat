import SwiftUI
import UIKit
import ClawChatKit
import PhotosUI
import UniformTypeIdentifiers
import Speech

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
    @State private var isVoiceCancelActive = false
    @State private var scrollDebounceTask: Task<Void, Never>?
    @State private var speechService = SpeechRecognitionService()
    @State private var showSpeechPermissionAlert = false
    @State private var speechPermissionMessage = ""
    @State private var isVoiceFinalizing = false
    @State private var finalRecordingPreviewText = ""
    @State private var voiceFinalizeTask: Task<Void, Never>?
    @State private var streamingDisplayMessageId: String?
    @State private var streamingDisplayText = ""
    @State private var streamingTargetText = ""
    @State private var streamingDisplayTask: Task<Void, Never>?
    @State private var streamingScrollTask: Task<Void, Never>?
    @State private var scrollRestoreTask: Task<Void, Never>?
    @State private var isTrackingScrollAnchor = false
    @State private var isWalkieTalkieRecording = false
    @FocusState private var isInputFocused: Bool

    private let hapticMedium = UIImpactFeedbackGenerator(style: .medium)
    private let hapticLight = UIImpactFeedbackGenerator(style: .light)
    private let maxAttachmentBytes = 5 * 1024 * 1024
    private let composerRowMinHeight: CGFloat = 24
    private let voiceComposerHeight: CGFloat = 64
    private let recordingPreviewTailCharacterLimit = 40
    private let recordingFadeWidth: CGFloat = 18

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

    private var previewAssistantMessage: ChatMessage? {
        let storedIds = Set(storedMessages.map(\.id))
        return chatManager.liveMessages.last(where: { $0.role == .assistant && !storedIds.contains($0.id) })
    }

    private var renderedMessages: [MessageBubbleItem] {
        var items = storedMessages.map(MessageBubbleItem.init(storedMessage:))
        if let previewAssistantMessage {
            items.append(MessageBubbleItem(chatMessage: previewAssistantMessage))
        }
        return items.map(bufferedMessageItem)
    }

    private var isEmpty: Bool {
        renderedMessages.isEmpty
    }

    private var messageScrollCoordinateSpace: String {
        "chat-scroll-\(session.id)"
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
                inputBar
            }

            if isEmpty {
                emptyStateOverlay
                    .allowsHitTesting(false)
                    .ignoresSafeArea(.keyboard, edges: .bottom)
            }
        }
        .background(SiriGlowWindowPresenter(isActive: isVoiceRecording, dimmed: isVoiceCancelActive))
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
            syncStreamingDisplayState()
            isTrackingScrollAnchor = false
            hapticMedium.prepare()
            hapticLight.prepare()
        }
        .onChange(of: agent?.id) { _, _ in
            syncSelectedModel()
        }
        .onChange(of: previewAssistantMessage?.id) { _, _ in
            syncStreamingDisplayState()
        }
        .onChange(of: previewAssistantMessage?.text) { _, _ in
            syncStreamingDisplayState()
        }
        .onChange(of: previewAssistantMessage?.isStreaming) { _, _ in
            syncStreamingDisplayState()
        }
        .onChange(of: storedMessages.count) { _, _ in
            syncStreamingDisplayState()
        }
        .onDisappear {
            scrollDebounceTask?.cancel()
            scrollRestoreTask?.cancel()
            scrollRestoreTask = nil
            streamingDisplayTask?.cancel()
            streamingDisplayTask = nil
            streamingScrollTask?.cancel()
            streamingScrollTask = nil
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
        ScrollViewReader { proxy in
            GeometryReader { scrollGeometry in
                ScrollView {
                    let msgs = renderedMessages
                    let hasContent = !msgs.isEmpty || chatManager.isTyping
                    if hasContent {
                        VStack(spacing: 0) {
                            ForEach(msgs) { message in
                                MessageBubbleView(
                                    item: message,
                                    theme: currentTheme
                                )
                                .id(message.id)
                                .background(messageFrameReporter(for: message.id))
                            }

                            if chatManager.isTyping {
                                typingIndicator
                            }

                            Color.clear
                                .frame(height: 1)
                                .id("bottom")
                        }
                        .padding(.top, 12)
                        .padding(.bottom, 16)
                    }
                }
                .scrollDismissesKeyboard(.interactively)
                .coordinateSpace(name: messageScrollCoordinateSpace)
                .onAppear {
                    restoreSavedScrollAnchorIfNeeded(proxy: proxy)
                }
                .onChange(of: renderedMessages.map(\.id)) { _, _ in
                    restoreSavedScrollAnchorIfNeeded(proxy: proxy)
                }
                .onPreferenceChange(ChatMessageFramePreferenceKey.self) { frames in
                    updateStoredScrollAnchor(
                        with: frames,
                        viewportHeight: scrollGeometry.size.height
                    )
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(Rectangle())
            .onChange(of: renderedMessages.count) { _, _ in
                proxy.scrollTo("bottom", anchor: .bottom)
            }
            .onChange(of: previewAssistantMessage?.id) { _, _ in
                debouncedScrollToBottom(proxy: proxy)
            }
            .onChange(of: streamingDisplayText) { _, _ in
                scheduleStreamingScrollToBottom(proxy: proxy)
            }
            .onChange(of: chatManager.isTyping) { _, _ in
                debouncedScrollToBottom(proxy: proxy)
            }
            .onTapGesture {
                isInputFocused = false
            }
        }
        .onChange(of: chatManager.liveMessages.count) { _, _ in
            syncLiveMessages()
        }
        .onChange(of: chatManager.liveMessages.last?.isStreaming) { _, isStreaming in
            if isStreaming == false {
                syncLiveMessages()
            }
        }
    }

    private func debouncedScrollToBottom(proxy: ScrollViewProxy) {
        scrollDebounceTask?.cancel()
        scrollDebounceTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(140))
            guard !Task.isCancelled else { return }
            proxy.scrollTo("bottom", anchor: .bottom)
        }
    }

    private func scheduleStreamingScrollToBottom(proxy: ScrollViewProxy) {
        guard streamingScrollTask == nil else { return }

        streamingScrollTask = Task { @MainActor in
            try? await Task.sleep(for: StreamingTypewriter.followScrollDelay)
            guard !Task.isCancelled else { return }

            var transaction = Transaction()
            transaction.animation = nil
            withTransaction(transaction) {
                proxy.scrollTo("bottom", anchor: .bottom)
            }

            streamingScrollTask = nil
        }
    }

    @ViewBuilder
    private func messageFrameReporter(for messageId: String) -> some View {
        GeometryReader { geometry in
            Color.clear
                .preference(
                    key: ChatMessageFramePreferenceKey.self,
                    value: [messageId: geometry.frame(in: .named(messageScrollCoordinateSpace))]
                )
        }
    }

    private func restoreSavedScrollAnchorIfNeeded(proxy: ScrollViewProxy) {
        guard !isTrackingScrollAnchor else { return }
        guard scrollRestoreTask == nil else { return }

        guard let savedAnchorId = appState.chatScrollAnchor(for: session.id) else {
            isTrackingScrollAnchor = true
            return
        }

        scrollRestoreTask = Task { @MainActor in
            defer { scrollRestoreTask = nil }

            try? await Task.sleep(for: .milliseconds(24))
            guard !Task.isCancelled else { return }

            var transaction = Transaction()
            transaction.animation = nil
            withTransaction(transaction) {
                proxy.scrollTo(savedAnchorId, anchor: .top)
            }

            try? await Task.sleep(for: .milliseconds(24))
            guard !Task.isCancelled else { return }
            isTrackingScrollAnchor = true
        }
    }

    private func updateStoredScrollAnchor(
        with frames: [String: CGRect],
        viewportHeight: CGFloat
    ) {
        guard isTrackingScrollAnchor else { return }

        let visibleMessageIds = Set(renderedMessages.map(\.id))
        let visibleFrames = frames.filter { visibleMessageIds.contains($0.key) }
        let anchorId = ChatScrollAnchorResolver.anchorMessageID(
            from: visibleFrames,
            viewportHeight: viewportHeight
        )
        appState.setChatScrollAnchor(anchorId, for: session.id)
    }

    private func bufferedMessageItem(_ item: MessageBubbleItem) -> MessageBubbleItem {
        guard item.role == .assistant,
              item.id == streamingDisplayMessageId else {
            return item
        }

        let shouldKeepTyping = streamingDisplayText != item.text
        return MessageBubbleItem(
            id: item.id,
            role: item.role,
            text: streamingDisplayText,
            reasoning: item.reasoning,
            attachments: item.attachments,
            toolEvents: item.toolEvents,
            isStreaming: item.isStreaming || shouldKeepTyping,
            isError: item.isError
        )
    }

    private func syncStreamingDisplayState() {
        if let previewAssistantMessage {
            bindStreamingDisplay(
                to: previewAssistantMessage.id,
                targetText: previewAssistantMessage.text
            )
            return
        }

        guard let currentMessageId = streamingDisplayMessageId else { return }

        if let persistedMessage = storedMessages.last(where: { $0.id == currentMessageId }) {
            bindStreamingDisplay(to: currentMessageId, targetText: persistedMessage.text)
        } else if let liveMessage = chatManager.liveMessages.last(where: { $0.id == currentMessageId }) {
            bindStreamingDisplay(to: currentMessageId, targetText: liveMessage.text)
        } else if streamingDisplayText == streamingTargetText {
            clearStreamingDisplayState()
        }
    }

    private func bindStreamingDisplay(to messageId: String, targetText: String) {
        if streamingDisplayMessageId != messageId {
            streamingDisplayTask?.cancel()
            streamingDisplayTask = nil
            streamingDisplayMessageId = messageId
            streamingDisplayText = ""
            streamingTargetText = ""
        }

        streamingTargetText = targetText
        startStreamingDisplayTaskIfNeeded()
    }

    private func startStreamingDisplayTaskIfNeeded() {
        guard streamingDisplayText != streamingTargetText else {
            clearStreamingDisplayStateIfCaughtUp()
            return
        }
        guard streamingDisplayTask == nil else { return }

        streamingDisplayTask = Task { @MainActor in
            while !Task.isCancelled {
                let nextText = StreamingTypewriter.nextDisplayText(
                    current: streamingDisplayText,
                    target: streamingTargetText
                )
                guard nextText != streamingDisplayText else { break }

                streamingDisplayText = nextText
                try? await Task.sleep(for: StreamingTypewriter.tickInterval)
            }

            streamingDisplayTask = nil
            clearStreamingDisplayStateIfCaughtUp()
        }
    }

    private func clearStreamingDisplayStateIfCaughtUp() {
        guard let currentMessageId = streamingDisplayMessageId else { return }
        guard streamingDisplayText == streamingTargetText else { return }
        guard previewAssistantMessage?.id != currentMessageId else { return }

        streamingDisplayMessageId = nil
        streamingDisplayText = ""
        streamingTargetText = ""
    }

    private func clearStreamingDisplayState() {
        streamingDisplayTask?.cancel()
        streamingDisplayTask = nil
        streamingScrollTask?.cancel()
        streamingScrollTask = nil
        streamingDisplayMessageId = nil
        streamingDisplayText = ""
        streamingTargetText = ""
    }

    private func syncLiveMessages() {
        let live = chatManager.liveMessages
        let stored = appState.messages(for: session.id)
        let storedIds = Set(stored.map(\.id))

        for msg in live {
            if msg.isStreaming { continue }
            if msg.role == .user { continue }

            if storedIds.contains(msg.id) {
                appState.updateMessage(in: session.id, messageId: msg.id, text: msg.text)
            } else {
                let stored = StoredMessage(
                    id: msg.id,
                    role: .assistant,
                    text: msg.text,
                    reasoning: msg.reasoning,
                    timestamp: msg.timestamp
                )
                appState.appendMessage(to: session.id, message: stored)
            }
        }

        syncStreamingDisplayState()
    }

    private var typingIndicator: some View {
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
        .overlay {
            WalkieTalkieGestureView(
                isEnabled: (!isInputFocused && !isVoiceRecording && !isVoiceFinalizing) || isWalkieTalkieRecording,
                onTap: { isInputFocused = true },
                onRecordStart: {
                    isWalkieTalkieRecording = true
                    hapticMedium.impactOccurred()
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
                            hapticLight.impactOccurred()
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
        .padding(.horizontal, 12)
        .padding(.bottom, 8)
    }

    private var standardInputBar: some View {
        VStack(spacing: 8) {
            inputFieldArea

            HStack(spacing: 8) {
                attachmentButton
                modelMenu

                Spacer()

                if hasDraftContent {
                    sendButton
                } else {
                    if isVoiceFinalizing {
                        Circle()
                            .fill(currentTheme.accent)
                            .frame(width: 36, height: 36)
                            .overlay {
                                Image(systemName: "checkmark")
                                    .font(.system(size: 14, weight: .bold))
                                    .foregroundStyle(.white)
                            }
                            .transition(.scale.combined(with: .opacity))
                    } else if isVoiceRecording {
                        recordingIndicator
                    } else {
                        speakButton
                    }
                }
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 10)
        }
        .background(inputBarBackground)
        .animation(.snappy(duration: 0.22), value: isVoiceRecording)
        .animation(.snappy(duration: 0.22), value: isVoiceFinalizing)
    }

    private let voiceCancelDragThreshold: CGFloat = 50

    private var inputBarBackground: some View {
        RoundedRectangle(cornerRadius: 24)
            .fill(Color(.systemBackground))
            .overlay(
                RoundedRectangle(cornerRadius: 24)
                    .stroke(Color(.systemGray5), lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.05), radius: 10, y: 3)
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
        .glassEffect(.regular, in: .circle)
    }

    // MARK: - Input Field

    private var inputFieldArea: some View {
        VStack(spacing: 10) {
            if !composerAttachments.isEmpty {
                composerAttachmentStrip
            }

            ZStack(alignment: .topLeading) {
                textField
                    .opacity((isVoiceRecording || isVoiceFinalizing) ? 0 : 1)

                if isVoiceRecording || isVoiceFinalizing {
                    activeRecordingField
                        .transition(.opacity)
                }
            }
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

    private var recordingOverlay: some View {
        HStack(spacing: 10) {
            Image(systemName: "mic.fill")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(.red)
                .symbolEffect(.pulse, isActive: isVoiceRecording)

            RecordingPreviewView(
                speechService: speechService,
                frozenText: finalRecordingPreviewText,
                isFinalizing: isVoiceFinalizing,
                minHeight: composerRowMinHeight,
                tailCharacterLimit: recordingPreviewTailCharacterLimit,
                fadeWidth: recordingFadeWidth
            )

            Spacer(minLength: 0)
        }
        .frame(minHeight: composerRowMinHeight, alignment: .leading)
    }

    private var activeRecordingField: some View {
        ZStack(alignment: .leading) {
            HStack(spacing: 8) {
                Spacer(minLength: 0)
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(.red)

                Text("松手取消")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.red)

                Spacer(minLength: 0)
            }
            .opacity(isVoiceCancelActive ? 1 : 0)

            recordingOverlay
                .opacity(isVoiceCancelActive ? 0 : 1)
        }
        .padding(.horizontal, 16)
        .padding(.top, 14)
        .padding(.bottom, 2)
        .frame(minHeight: composerRowMinHeight, alignment: .topLeading)
        .frame(maxWidth: .infinity, alignment: .leading)
        .animation(.easeInOut(duration: 0.15), value: isVoiceCancelActive)
    }

    private var textField: some View {
        TextField("输入文字或长按录音", text: $inputText, axis: .vertical)
            .lineLimit(1...6)
            .textFieldStyle(.plain)
            .font(.body)
            .focused($isInputFocused)
            .padding(.horizontal, 16)
            .padding(.top, 14)
            .padding(.bottom, 2)
            .frame(minHeight: composerRowMinHeight, alignment: .topLeading)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func endRecording() {
        guard isVoiceRecording else { return }
        hapticLight.impactOccurred()
        let wasCancelled = isVoiceCancelActive

        let finalText = speechService.stopRecording()
            .trimmingCharacters(in: .whitespacesAndNewlines)

        voiceFinalizeTask?.cancel()
        finalRecordingPreviewText = finalText

        withAnimation(.snappy(duration: 0.25)) {
            isVoiceRecording = false
            isVoiceCancelActive = false
            isVoiceFinalizing = !wasCancelled && !finalText.isEmpty
        }

        guard !wasCancelled, !finalText.isEmpty else {
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(250))
                finalRecordingPreviewText = ""
            }
            return
        }

        voiceFinalizeTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(140))
            guard !Task.isCancelled else { return }

            var transaction = Transaction()
            transaction.animation = nil
            withTransaction(transaction) {
                inputText = finalText
            }

            withAnimation(.snappy(duration: 0.18)) {
                isVoiceFinalizing = false
            }

            try? await Task.sleep(for: .milliseconds(40))
            guard !Task.isCancelled else { return }
            finalRecordingPreviewText = ""
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
            .glassEffect(.regular, in: .capsule)
        } else {
            modelChip(showChevron: false)
                .glassEffect(.regular, in: .capsule)
        }
    }

    private func modelChip(showChevron: Bool) -> some View {
        HStack(spacing: 4) {
            Image(systemName: "bolt.fill")
                .font(.system(size: 11, weight: .semibold))
            Text(modelDisplayTitle(for: selectedModel))
                .font(.system(size: 13, weight: .medium))
                .lineLimit(1)
                .minimumScaleFactor(0.9)
            if showChevron {
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 10, weight: .bold))
            }
        }
        .foregroundStyle(.secondary)
        .padding(.horizontal, 10)
        .frame(height: 32)
        .frame(minWidth: 106)
        .contentShape(Capsule())
    }

    private func modelDisplayTitle(for model: String) -> String {
        let lower = model.lowercased()
        if lower.contains("minimax") { return "MiniMax" }
        if lower.contains("claude") && lower.contains("opus") { return "Opus" }
        if lower.contains("claude") && lower.contains("sonnet") { return "Sonnet" }
        if lower.contains("claude") && lower.contains("haiku") { return "Haiku" }
        if lower.contains("gpt-4o") { return "GPT-4o" }
        if lower.contains("gpt-4") { return "GPT-4" }
        if lower.contains("gpt") { return "GPT" }
        if lower.contains("gemini") { return "Gemini" }
        if lower.contains("deepseek") { return "DeepSeek" }
        if lower.contains("qwen") { return "Qwen" }
        if lower.contains("llama") { return "Llama" }

        if let lastSlash = model.lastIndex(of: "/") {
            return String(model[model.index(after: lastSlash)...])
        }
        return model
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
        .transition(.scale.combined(with: .opacity))
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

        chatManager.sendMessage(
            text: text,
            agentId: session.agentId,
            attachments: attachments.map(\.protocolAttachment)
        )
        inputText = ""
        composerAttachments.removeAll()
    }

    private var speakButton: some View {
        Button {
            hapticMedium.impactOccurred()
            Task { await beginRecording() }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "waveform")
                    .font(.system(size: 13, weight: .bold))
                Text("Speak")
                    .font(.system(size: 14, weight: .bold))
            }
            .foregroundStyle(Color.white)
            .padding(.horizontal, 16)
            .frame(height: 36)
            .background(currentTheme.accent, in: Capsule())
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .transition(.scale.combined(with: .opacity))
    }

    private func beginRecording() async {
        isInputFocused = false
        voiceFinalizeTask?.cancel()
        voiceFinalizeTask = nil
        isVoiceFinalizing = false
        finalRecordingPreviewText = ""

        let permissions = await SpeechRecognitionService.requestPermissions()

        guard permissions.mic else {
            speechPermissionMessage = SpeechRecognitionService.SpeechError.microphoneDenied.localizedDescription
            showSpeechPermissionAlert = true
            return
        }
        guard permissions.speech else {
            speechPermissionMessage = SpeechRecognitionService.SpeechError.recognitionDenied.localizedDescription
            showSpeechPermissionAlert = true
            return
        }

        do {
            try speechService.startRecording()
            withAnimation(.snappy(duration: 0.25)) {
                isVoiceRecording = true
                isVoiceCancelActive = false
            }
        } catch {
            speechPermissionMessage = error.localizedDescription
            showSpeechPermissionAlert = true
        }
    }

    private var recordingIndicator: some View {
        Button {
            endRecording()
        } label: {
            Circle()
                .fill(Color.red)
                .frame(width: 36, height: 36)
                .overlay {
                    Image(systemName: "stop.fill")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(.white)
                }
        }
        .buttonStyle(.plain)
        .transition(.scale.combined(with: .opacity))
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

    @MainActor
    private func importPhotoAttachments(from items: [PhotosPickerItem]) async {
        for item in items {
            do {
                guard let data = try await item.loadTransferable(type: Data.self) else {
                    throw AttachmentImportError.unreadable("无法读取所选图片。")
                }

                let contentType = item.supportedContentTypes.first ?? .image
                let attachment = try makeComposerAttachment(
                    data: data,
                    filename: "image-\(UUID().uuidString.prefix(8)).\(contentType.preferredFilenameExtension ?? "bin")",
                    mimeType: contentType.preferredMIMEType ?? "application/octet-stream",
                    type: attachmentType(for: contentType)
                )
                composerAttachments.append(attachment)
            } catch {
                attachmentErrorMessage = error.localizedDescription
            }
        }
    }

    @MainActor
    private func importFileAttachments(from urls: [URL]) async {
        for url in urls {
            let scoped = url.startAccessingSecurityScopedResource()
            defer {
                if scoped {
                    url.stopAccessingSecurityScopedResource()
                }
            }

            do {
                let data = try Data(contentsOf: url, options: [.mappedIfSafe])
                let resourceValues = try url.resourceValues(forKeys: [.contentTypeKey, .nameKey])
                let contentType = resourceValues.contentType ?? UTType(filenameExtension: url.pathExtension) ?? .data
                let filename = resourceValues.name ?? url.lastPathComponent
                let attachment = try makeComposerAttachment(
                    data: data,
                    filename: filename,
                    mimeType: contentType.preferredMIMEType ?? "application/octet-stream",
                    type: attachmentType(for: contentType)
                )
                composerAttachments.append(attachment)
            } catch {
                attachmentErrorMessage = error.localizedDescription
            }
        }
    }

    private func makeComposerAttachment(
        data: Data,
        filename: String,
        mimeType: String,
        type: MessageAttachmentType
    ) throws -> ComposerAttachment {
        guard data.count <= maxAttachmentBytes else {
            throw AttachmentImportError.tooLarge("“\(filename)” 超过 5 MB，当前版本暂不支持。")
        }

        return ComposerAttachment(
            id: UUID().uuidString,
            type: type,
            filename: filename,
            mimeType: mimeType,
            size: data.count,
            dataBase64: data.base64EncodedString()
        )
    }

    private func attachmentType(for contentType: UTType) -> MessageAttachmentType {
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

private struct RecordingPreviewView: View {
    let speechService: SpeechRecognitionService
    let frozenText: String
    let isFinalizing: Bool
    let minHeight: CGFloat
    let tailCharacterLimit: Int
    let fadeWidth: CGFloat

    private var sourceText: String {
        isFinalizing ? frozenText : speechService.transcribedText
    }

    private var trimmedText: String {
        sourceText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var displayText: String {
        guard !trimmedText.isEmpty else { return "正在聆听…" }
        guard trimmedText.count > tailCharacterLimit else { return trimmedText }
        return String(trimmedText.suffix(tailCharacterLimit))
    }

    private var isPlaceholder: Bool {
        trimmedText.isEmpty
    }

    var body: some View {
        ZStack {
            Text(displayText)
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(isPlaceholder ? AnyShapeStyle(.secondary) : AnyShapeStyle(.primary))
                .lineLimit(1)
                .frame(maxWidth: .infinity, minHeight: minHeight, alignment: .leading)
                .padding(.horizontal, 8)
                .mask {
                    LinearGradient(
                        stops: [
                            .init(color: .clear, location: 0),
                            .init(color: .black, location: 0.08),
                            .init(color: .black, location: 0.92),
                            .init(color: .clear, location: 1)
                        ],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                }

            HStack(spacing: 0) {
                fadeEdge(startOpacity: 1, endOpacity: 0)
                    .frame(width: fadeWidth)
                Spacer(minLength: 0)
                fadeEdge(startOpacity: 0, endOpacity: 1)
                    .frame(width: fadeWidth)
            }
            .allowsHitTesting(false)
        }
        .frame(maxWidth: .infinity, minHeight: minHeight, alignment: .leading)
        .clipped()
        .animation(.none, value: displayText)
    }

    private func fadeEdge(startOpacity: Double, endOpacity: Double) -> some View {
        LinearGradient(
            colors: [
                Color(.systemBackground).opacity(startOpacity),
                Color(.systemBackground).opacity(endOpacity)
            ],
            startPoint: .leading,
            endPoint: .trailing
        )
    }
}

private enum AttachmentImportError: LocalizedError {
    case unreadable(String)
    case tooLarge(String)

    var errorDescription: String? {
        switch self {
        case .unreadable(let message), .tooLarge(let message):
            message
        }
    }
}

enum ChatScrollAnchorResolver {
    static func anchorMessageID(
        from messageFrames: [String: CGRect],
        viewportHeight: CGFloat
    ) -> String? {
        guard viewportHeight > 0 else { return nil }

        return messageFrames
            .filter { _, frame in
                frame.maxY > 0 && frame.minY < viewportHeight
            }
            .min { lhs, rhs in
                let lhsDistance = abs(lhs.value.minY)
                let rhsDistance = abs(rhs.value.minY)

                if lhsDistance == rhsDistance {
                    return lhs.value.minY < rhs.value.minY
                }

                return lhsDistance < rhsDistance
            }?
            .key
    }
}

private struct ChatMessageFramePreferenceKey: PreferenceKey {
    static var defaultValue: [String: CGRect] = [:]

    static func reduce(value: inout [String: CGRect], nextValue: () -> [String: CGRect]) {
        value.merge(nextValue(), uniquingKeysWith: { _, new in new })
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
        tap.require(toFail: longPress)

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

        init(_ parent: WalkieTalkieGestureView) {
            self.onTap = parent.onTap
            self.onRecordStart = parent.onRecordStart
            self.onDragChanged = parent.onDragChanged
            self.onRecordEnd = parent.onRecordEnd
        }

        @objc func handleTap() { onTap() }

        @objc func handleLongPress(_ gesture: UILongPressGestureRecognizer) {
            switch gesture.state {
            case .began:
                startY = gesture.location(in: gesture.view).y
                onRecordStart()
            case .changed:
                let dy = gesture.location(in: gesture.view).y - startY
                onDragChanged(dy)
            case .ended, .cancelled, .failed:
                onRecordEnd()
            default:
                break
            }
        }
    }
}

// MARK: - Re-enable interactive pop gesture when back button is hidden

private struct InteractivePopGestureEnabler: UIViewControllerRepresentable {
    func makeUIViewController(context: Context) -> UIViewController {
        InteractivePopController()
    }
    func updateUIViewController(_ uiViewController: UIViewController, context: Context) {}

    final class InteractivePopController: UIViewController {
        override func viewDidLayoutSubviews() {
            super.viewDidLayoutSubviews()
            navigationController?.interactivePopGestureRecognizer?.isEnabled = true
            navigationController?.interactivePopGestureRecognizer?.delegate = nil
        }
    }
}
