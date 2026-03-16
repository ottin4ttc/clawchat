import Foundation

struct Session: Identifiable, Codable, Hashable {
    let id: String
    var agentId: String
    var title: String
    var category: String
    var lastMessage: String?
    var lastMessageTime: Date?
    var unreadCount: Int
    var isPinned: Bool = false

    var timeAgo: String {
        guard let time = lastMessageTime else { return "" }
        let interval = Date().timeIntervalSince(time)
        let days = Int(interval / 86400)
        if days == 0 { return "今天" }
        if days == 1 { return "昨天" }
        return "\(days)天"
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
