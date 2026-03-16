import Foundation

enum AgentStatus: String, Codable, CaseIterable {
    case online
    case idle
    case dnd
    case offline
}

struct Agent: Identifiable, Codable, Hashable {
    let id: String
    var name: String
    var avatar: String
    var status: AgentStatus
    var unreadCount: Int
    var gatewayId: String?
    var model: String?
    var availableModels: [String]?
    var theme: String?
}
