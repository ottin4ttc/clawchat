import SwiftUI
import ClawChatKit

struct AgentAvatarView: View {
    var agentId: String?
    var avatar: String?
    var theme: AppVisualTheme
    var size: CGFloat = 28
    var showsBackground: Bool = true

    var body: some View {
        if let agentId, let custom = AvatarStorage.load(for: agentId) {
            Image(uiImage: custom)
                .resizable()
                .scaledToFill()
                .frame(width: size, height: size)
                .clipShape(Circle())
        } else if let avatar, !avatar.isEmpty, UIImage(named: avatar) != nil {
            Image(avatar)
                .resizable()
                .scaledToFill()
                .frame(width: size, height: size)
                .clipShape(Circle())
        } else if showsBackground {
            Image("clawos_svg_logo")
                .resizable()
                .renderingMode(.template)
                .scaledToFit()
                .frame(width: size * 0.68, height: size * 0.68)
                .foregroundStyle(theme.accent)
                .frame(width: size, height: size)
                .background(theme.softFill, in: Circle())
        } else {
            Image("clawos_svg_logo")
                .resizable()
                .renderingMode(.template)
                .scaledToFit()
                .frame(width: size, height: size)
                .foregroundStyle(theme.accent)
        }
    }
}

struct TypingBreathingDotsView: View {
    var color: Color = Color(.systemGray3)

    var body: some View {
        TimelineView(.animation) { context in
            let time = context.date.timeIntervalSinceReferenceDate * 3.2

            HStack(spacing: 6) {
                ForEach(0..<3, id: \.self) { index in
                    let phase = (sin(time - Double(index) * 0.55) + 1) / 2
                    Circle()
                        .fill(color.opacity(0.28 + phase * 0.62))
                        .frame(width: 7, height: 7)
                        .scaleEffect(0.82 + phase * 0.24)
                }
            }
        }
        .frame(height: 12)
    }
}

struct MessageBubbleItem: Identifiable {
    let id: String
    let role: MessageRole
    let text: String
    let reasoning: String?
    let attachments: [StoredMessageAttachment]
    let toolEvents: [ChatToolEvent]
    let isStreaming: Bool
    let isError: Bool

    init(
        id: String,
        role: MessageRole,
        text: String,
        reasoning: String?,
        attachments: [StoredMessageAttachment],
        toolEvents: [ChatToolEvent],
        isStreaming: Bool,
        isError: Bool
    ) {
        self.id = id
        self.role = role
        self.text = text
        self.reasoning = reasoning
        self.attachments = attachments
        self.toolEvents = toolEvents
        self.isStreaming = isStreaming
        self.isError = isError
    }

    init(chatMessage: ChatMessage) {
        id = chatMessage.id
        role = chatMessage.role
        text = chatMessage.text
        reasoning = chatMessage.reasoning
        attachments = []
        toolEvents = chatMessage.toolEvents
        isStreaming = chatMessage.isStreaming
        isError = chatMessage.isError
    }

    init(storedMessage: StoredMessage) {
        id = storedMessage.id
        role = storedMessage.role == .user ? .user : .assistant
        text = storedMessage.text
        reasoning = storedMessage.reasoning
        attachments = storedMessage.attachments
        toolEvents = []
        isStreaming = false
        isError = false
    }
}

struct MessageBubbleView: View {
    let item: MessageBubbleItem
    var theme: AppVisualTheme

    private let bubbleRadius: CGFloat = 22

    var body: some View {
        switch item.role {
        case .user:
            userBubble
        case .assistant:
            agentBubble
        }
    }

    private var userBubble: some View {
        HStack(alignment: .bottom) {
            Spacer(minLength: 64)

            VStack(alignment: .leading, spacing: 8) {
                if !item.attachments.isEmpty {
                    attachmentList(isUserBubble: true)
                }

                if !item.text.isEmpty {
                    Text(item.text)
                        .font(.body)
                        .lineSpacing(2)
                        .foregroundStyle(.white)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 11)
            .background(
                RoundedRectangle(cornerRadius: bubbleRadius, style: .continuous)
                    .fill(theme.accent)
            )
        }
        .padding(.horizontal, 16)
        .padding(.top, 12)
        .padding(.bottom, 4)
    }

    private var agentBubble: some View {
        HStack(alignment: .bottom) {
            VStack(alignment: .leading, spacing: 8) {
                if let reasoning = item.reasoning, !reasoning.isEmpty {
                    reasoningBlock(reasoning)
                }

                if !item.toolEvents.isEmpty {
                    toolEventsBlock
                }

                if !item.attachments.isEmpty {
                    attachmentList(isUserBubble: false)
                }

                if item.isStreaming && item.text.isEmpty {
                    TypingBreathingDotsView()
                        .padding(.vertical, 2)
                } else if !item.text.isEmpty {
                    Text(item.text)
                        .font(.body)
                        .lineSpacing(2)
                        .foregroundStyle(item.isError ? .red : .primary)
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 11)
            .background(
                RoundedRectangle(cornerRadius: bubbleRadius, style: .continuous)
                    .fill(Color(.systemGray5))
            )

            Spacer(minLength: 64)
        }
        .padding(.horizontal, 16)
        .padding(.top, 4)
        .padding(.bottom, 8)
    }

    private func reasoningBlock(_ text: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Label("思考过程", systemImage: "brain.head.profile")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)

            Text(text)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(6)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.systemBackground).opacity(0.55), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private var toolEventsBlock: some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(item.toolEvents) { event in
                HStack(spacing: 6) {
                    toolPhaseIcon(event.phase)
                    Text(event.label ?? event.tool)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.systemBackground).opacity(0.55), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private func attachmentList(isUserBubble: Bool) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(item.attachments) { attachment in
                HStack(spacing: 8) {
                    Image(systemName: attachment.iconName)
                        .font(.system(size: 13, weight: .semibold))
                    VStack(alignment: .leading, spacing: 2) {
                        Text(attachment.filename)
                            .font(.caption.weight(.semibold))
                            .lineLimit(1)
                        Text(attachment.displaySize)
                            .font(.caption2)
                            .opacity(0.78)
                    }
                    Spacer(minLength: 0)
                }
                .foregroundStyle(isUserBubble ? Color.white : Color.primary)
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(isUserBubble ? Color.white.opacity(0.18) : Color(.systemBackground).opacity(0.6))
                )
            }
        }
    }

    @ViewBuilder
    private func toolPhaseIcon(_ phase: ToolPhase) -> some View {
        switch phase {
        case .start, .progress:
            ProgressView()
                .controlSize(.mini)
        case .result:
            Image(systemName: "checkmark.circle.fill")
                .font(.caption2)
                .foregroundStyle(.green)
        case .error:
            Image(systemName: "xmark.circle.fill")
                .font(.caption2)
                .foregroundStyle(.red)
        }
    }
}

struct ChatMessageBubbleView: View {
    @Environment(AppState.self) private var appState
    let message: ChatMessage

    private var currentTheme: AppVisualTheme {
        appState.currentVisualTheme
    }

    var body: some View {
        MessageBubbleView(item: MessageBubbleItem(chatMessage: message), theme: currentTheme)
    }
}

struct StoredMessageBubbleView: View {
    let message: StoredMessage
    var theme: AppVisualTheme

    var body: some View {
        MessageBubbleView(item: MessageBubbleItem(storedMessage: message), theme: theme)
    }
}
