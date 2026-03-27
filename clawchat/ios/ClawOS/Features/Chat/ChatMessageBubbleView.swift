import SwiftUI
import ClawChatKit
import MessagingUI

struct AgentAvatarView: View {
    var agentId: String?
    var avatar: String?
    var theme: AppVisualTheme
    var size: CGFloat = 28
    var showsBackground: Bool = true

    @State private var diskImage: UIImage?

    var body: some View {
        avatarContent
            .frame(width: size, height: size)
            .clipShape(Circle())
            .task(id: agentId) {
                guard let agentId else { return }
                if AvatarStorage.loadCached(for: agentId) != nil {
                    diskImage = AvatarStorage.loadCached(for: agentId)
                    return
                }
                if let loaded = await AvatarStorage.loadFromDisk(for: agentId) {
                    AvatarStorage.cacheInMemory(loaded, for: agentId)
                    diskImage = loaded
                }
            }
    }

    @ViewBuilder
    private var avatarContent: some View {
        if let diskImage {
            Image(uiImage: diskImage)
                .resizable()
                .scaledToFill()
        } else if let avatar, !avatar.isEmpty, UIImage(named: avatar) != nil {
            Image(avatar)
                .resizable()
                .scaledToFill()
        } else {
            Image("default_agent_avatar")
                .resizable()
                .scaledToFill()
        }
    }
}

struct TypingBreathingDotsView: View {
    var color: Color = Color(.systemGray3)

    var body: some View {
        HStack(spacing: 6) {
            ForEach(0..<3, id: \.self) { index in
                Circle()
                    .fill(color)
                    .frame(width: 7, height: 7)
                    .phaseAnimator([false, true]) { content, isExpanded in
                        content
                            .opacity(isExpanded ? 0.9 : 0.28)
                            .scaleEffect(isExpanded ? 1.06 : 0.82)
                    } animation: { _ in
                        .easeInOut(duration: 0.6)
                            .delay(Double(index) * 0.12)
                            .repeatForever(autoreverses: true)
                    }
            }
        }
        .frame(height: 12)
    }
}

@MainActor
enum MessageBubbleTimeFormatter {
    static let sharedFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        return formatter
    }()

    static func string(from date: Date) -> String {
        sharedFormatter.string(from: date)
    }
}

struct MessageBubbleItem: Identifiable, Equatable {
    let id: String
    let role: MessageRole
    let text: String
    let reasoning: String?
    let attachments: [StoredMessageAttachment]
    let toolEvents: [ChatToolEvent]
    let isStreaming: Bool
    let isError: Bool
    let timestamp: Date

    init(
        id: String,
        role: MessageRole,
        text: String,
        reasoning: String?,
        attachments: [StoredMessageAttachment],
        toolEvents: [ChatToolEvent],
        isStreaming: Bool,
        isError: Bool,
        timestamp: Date
    ) {
        self.id = id
        self.role = role
        self.text = text
        self.reasoning = reasoning
        self.attachments = attachments
        self.toolEvents = toolEvents
        self.isStreaming = isStreaming
        self.isError = isError
        self.timestamp = timestamp
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
        timestamp = chatMessage.timestamp
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
        timestamp = storedMessage.timestamp
    }

    static func == (lhs: MessageBubbleItem, rhs: MessageBubbleItem) -> Bool {
        lhs.id == rhs.id &&
        rolesEqual(lhs.role, rhs.role) &&
        lhs.text == rhs.text &&
        lhs.reasoning == rhs.reasoning &&
        lhs.attachments == rhs.attachments &&
        lhs.isStreaming == rhs.isStreaming &&
        lhs.isError == rhs.isError &&
        lhs.timestamp == rhs.timestamp &&
        toolEventsEqual(lhs.toolEvents, rhs.toolEvents)
    }

    private static func rolesEqual(_ lhs: MessageRole, _ rhs: MessageRole) -> Bool {
        switch (lhs, rhs) {
        case (.user, .user), (.assistant, .assistant):
            true
        default:
            false
        }
    }

    private static func toolEventsEqual(_ lhs: [ChatToolEvent], _ rhs: [ChatToolEvent]) -> Bool {
        guard lhs.count == rhs.count else { return false }
        return zip(lhs, rhs).allSatisfy { left, right in
            left.id == right.id &&
            left.tool == right.tool &&
            left.phase.rawValue == right.phase.rawValue &&
            left.label == right.label
        }
    }
}

struct MessageBubbleView: View {
    let item: MessageBubbleItem
    var theme: AppVisualTheme

    private let bubbleRadius: CGFloat = 22
    private var isUser: Bool { item.role == .user }

    private var timeString: String {
        MessageBubbleTimeFormatter.string(from: item.timestamp)
    }

    var body: some View {
        HStack(alignment: .bottom) {
            if isUser { Spacer(minLength: 64) }

            VStack(alignment: isUser ? .trailing : .leading, spacing: 8) {
                if let reasoning = item.reasoning, !reasoning.isEmpty, !isUser {
                    reasoningBlock(reasoning)
                }

                if !item.toolEvents.isEmpty, !isUser {
                    toolEventsBlock
                }

                if !item.attachments.isEmpty {
                    attachmentList(isUserBubble: isUser)
                }

                if !isUser && item.isStreaming && item.text.isEmpty {
                    TypingBreathingDotsView()
                        .padding(.vertical, 2)
                } else if !item.text.isEmpty {
                    Text(item.text)
                        .font(.body)
                        .lineSpacing(2)
                        .foregroundStyle(isUser ? .white : (item.isError ? .red : .primary))
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Text(timeString)
                    .font(.caption2)
                    .foregroundStyle(isUser ? Color.white.opacity(0.7) : .secondary)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 11)
            .background(
                RoundedRectangle(cornerRadius: bubbleRadius, style: .continuous)
                    .fill(isUser ? theme.accent : Color(.systemGray5))
            )

            if !isUser { Spacer(minLength: 64) }
        }
        .padding(.horizontal, 16)
        .padding(.top, isUser ? 12 : 4)
        .padding(.bottom, isUser ? 4 : 8)
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

struct EquatableMessageBubbleRow: View, Equatable {
    let item: MessageBubbleItem
    let theme: AppVisualTheme
    let themeKey: String

    static func == (lhs: EquatableMessageBubbleRow, rhs: EquatableMessageBubbleRow) -> Bool {
        lhs.item == rhs.item && lhs.themeKey == rhs.themeKey
    }

    var body: some View {
        MessageBubbleView(item: item, theme: theme)
    }
}

struct MessageBubbleTiledCell: TiledCellContent {
    typealias StateValue = Void
    let item: MessageBubbleItem
    let theme: AppVisualTheme

    func body(context: CellContext<Void>) -> some View {
        MessageBubbleView(item: item, theme: theme)
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
