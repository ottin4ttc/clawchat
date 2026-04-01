import Foundation

struct Session: Identifiable, Codable, Hashable {
    let id: String
    var agentId: String
    var sessionKey: String
    var title: String
    var category: String
    var lastMessage: String?
    var lastMessageTime: Date?
    var unreadCount: Int
    var isPinned: Bool = false

    init(
        id: String,
        agentId: String,
        sessionKey: String? = nil,
        title: String,
        category: String,
        lastMessage: String?,
        lastMessageTime: Date?,
        unreadCount: Int,
        isPinned: Bool = false
    ) {
        self.id = id
        self.agentId = agentId
        self.sessionKey = sessionKey ?? Self.generatedSessionKey(for: id)
        self.title = title
        self.category = category
        self.lastMessage = lastMessage
        self.lastMessageTime = lastMessageTime
        self.unreadCount = unreadCount
        self.isPinned = isPinned
    }

    enum CodingKeys: String, CodingKey {
        case id
        case agentId
        case sessionKey
        case title
        case category
        case lastMessage
        case lastMessageTime
        case unreadCount
        case isPinned
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        agentId = try container.decode(String.self, forKey: .agentId)
        sessionKey = try container.decodeIfPresent(String.self, forKey: .sessionKey) ?? Self.generatedSessionKey(for: id)
        title = try container.decode(String.self, forKey: .title)
        category = try container.decode(String.self, forKey: .category)
        lastMessage = try container.decodeIfPresent(String.self, forKey: .lastMessage)
        lastMessageTime = try container.decodeIfPresent(Date.self, forKey: .lastMessageTime)
        unreadCount = try container.decode(Int.self, forKey: .unreadCount)
        isPinned = try container.decodeIfPresent(Bool.self, forKey: .isPinned) ?? false
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(agentId, forKey: .agentId)
        try container.encode(sessionKey, forKey: .sessionKey)
        try container.encode(title, forKey: .title)
        try container.encode(category, forKey: .category)
        try container.encodeIfPresent(lastMessage, forKey: .lastMessage)
        try container.encodeIfPresent(lastMessageTime, forKey: .lastMessageTime)
        try container.encode(unreadCount, forKey: .unreadCount)
        try container.encode(isPinned, forKey: .isPinned)
    }

    private static func generatedSessionKey(for sessionId: String) -> String {
        "clawchat:ios:session:\(sessionId)"
    }

    var timeAgo: String {
        guard let time = lastMessageTime else { return "" }
        let interval = Date().timeIntervalSince(time)
        let minutes = Int(interval / 60)
        let hours = Int(interval / 3600)
        let days = Int(interval / 86400)

        if minutes < 1 { return "刚刚" }
        if minutes < 60 { return "\(String(minutes))分钟前" }
        if hours < 24 { return "\(String(hours))小时前" }
        if days == 1 { return "昨天" }
        if days < 7 { return "\(String(days))天前" }

        let formatter = DateFormatter()
        if days < 365 {
            formatter.dateFormat = "M/d"
        } else {
            formatter.dateFormat = "yyyy/M/d"
        }
        return formatter.string(from: time)
    }
}

// MARK: - Persistable Message

struct StoredMessage: Identifiable, Codable {
    let id: String
    let role: StoredMessageRole
    var text: String
    var reasoning: String?
    var attachments: [StoredMessageAttachment]
    let timestamp: Date

    init(
        id: String,
        role: StoredMessageRole,
        text: String,
        reasoning: String? = nil,
        attachments: [StoredMessageAttachment] = [],
        timestamp: Date
    ) {
        self.id = id
        self.role = role
        self.text = text
        self.reasoning = reasoning
        self.attachments = attachments
        self.timestamp = timestamp
    }

    enum CodingKeys: String, CodingKey {
        case id
        case role
        case text
        case reasoning
        case attachments
        case timestamp
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        role = try container.decode(StoredMessageRole.self, forKey: .role)
        text = try container.decode(String.self, forKey: .text)
        reasoning = try container.decodeIfPresent(String.self, forKey: .reasoning)
        attachments = try container.decodeIfPresent([StoredMessageAttachment].self, forKey: .attachments) ?? []
        timestamp = try container.decode(Date.self, forKey: .timestamp)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(role, forKey: .role)
        try container.encode(text, forKey: .text)
        try container.encodeIfPresent(reasoning, forKey: .reasoning)
        try container.encode(attachments, forKey: .attachments)
        try container.encode(timestamp, forKey: .timestamp)
    }

    var previewText: String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            return trimmed
        }

        guard !attachments.isEmpty else {
            return ""
        }

        if attachments.count == 1, let first = attachments.first {
            return "附件：\(first.filename)"
        }
        return "附件 \(attachments.count) 个"
    }

    enum StoredMessageRole: String, Codable {
        case user
        case assistant
    }
}
