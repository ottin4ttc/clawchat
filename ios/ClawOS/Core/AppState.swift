import SwiftUI
import ClawChatKit

@Observable
final class AppState {
    private struct ParsedAgentDescriptor {
        let id: String
        let name: String
        let model: String?
        let availableModels: [String]?
    }

    private static let sessionsKey = "clawos_sessions"
    private static let messagesKey = "clawos_messages"
    private static let themeKey = "clawos_theme"

    var agents: [Agent] = []
    var gateways: [Gateway] = []
    var sessions: [Session] = [] {
        didSet { persistSessions() }
    }
    var skills: [Skill] = []

    private(set) var messagesBySession: [String: [StoredMessage]] = [:]
    private var chatScrollAnchorsBySession: [String: String] = [:]

    var selectedAgentId: String = ""
    var selectedGatewayId: String = ""
    var selectedVisualThemeID: AppVisualThemeID = .eva00 {
        didSet {
            UserDefaults.standard.set(selectedVisualThemeID.rawValue, forKey: Self.themeKey)
        }
    }
    var showPairing = false

    let clawChatManager = ClawChatManager()

    init() {
        loadSessions()
        loadMessages()
        loadTheme()
    }

    var allAvailableModels: [String] {
        let models = agents.flatMap { $0.availableModels ?? [$0.model].compactMap { $0 } }
        return Array(Set(models.filter { !$0.isEmpty && $0 != "unknown" }))
    }

    var selectedAgent: Agent? {
        agents.first { $0.id == selectedAgentId }
    }

    var currentVisualTheme: AppVisualTheme {
        AppVisualTheme.theme(for: selectedVisualThemeID)
    }

    var currentGateway: Gateway? {
        gateways.first { $0.id == selectedGatewayId }
    }

    var currentGatewayType: GatewayType {
        currentGateway?.type ?? .local
    }

    var currentGatewayAgents: [Agent] {
        agents.filter { $0.gatewayId == selectedGatewayId }
    }

    func selectGateway(_ id: String) {
        selectedGatewayId = id
        let visible = currentGatewayAgents
        if !visible.contains(where: { $0.id == selectedAgentId }),
           let first = visible.first {
            selectedAgentId = first.id
        }
    }

    func agent(for id: String) -> Agent? {
        agents.first { $0.id == id }
    }

    func sessions(for agentId: String) -> [Session] {
        sessions.filter { $0.agentId == agentId }
    }

    // MARK: - Populate from ClawChatManager

    func applyConnectionInfo(
        gatewayId: String,
        relayUrl: String,
        agentIds: [String],
        agentsMeta: [String: AgentMeta]? = nil
    ) {
        let gateway = Gateway(
            id: gatewayId,
            name: relayUrl
                .replacingOccurrences(of: "wss://", with: "")
                .replacingOccurrences(of: "ws://", with: ""),
            url: relayUrl,
            type: .cloud,
            status: .online
        )

        if !gateways.contains(where: { $0.id == gatewayId }) {
            gateways.append(gateway)
        } else if let idx = gateways.firstIndex(where: { $0.id == gatewayId }) {
            gateways[idx].status = .online
        }

        selectedGatewayId = gatewayId

        let parsedAgents = agentIds.map { rawAgentId in
            parseAgentDescriptor(rawAgentId, meta: agentsMeta?[rawAgentId])
        }
        let resolvedIds = Set(parsedAgents.map(\.id))
        let staleIds = Set(
            agents
                .filter { $0.gatewayId == gatewayId && !resolvedIds.contains($0.id) }
                .map(\.id)
        )

        if parsedAgents.count == 1, let canonicalId = parsedAgents.first?.id {
            for index in sessions.indices where staleIds.contains(sessions[index].agentId) {
                sessions[index].agentId = canonicalId
            }
        }

        agents.removeAll { agent in
            agent.gatewayId == gatewayId && !resolvedIds.contains(agent.id)
        }

        for parsed in parsedAgents {
            let agentId = parsed.id
            let agentName = parsed.name
            let agentModel = parsed.model ?? "unknown"
            let availableModels = parsed.availableModels ?? [agentModel]

            if let idx = agents.firstIndex(where: { $0.id == agentId }) {
                agents[idx].name = agentName
                agents[idx].model = agentModel
                agents[idx].availableModels = availableModels
                agents[idx].status = .online
            } else {
                let agent = Agent(
                    id: agentId,
                    name: agentName,
                    avatar: "",
                    status: .online,
                    unreadCount: 0,
                    gatewayId: gatewayId,
                    model: agentModel,
                    availableModels: availableModels
                )
                agents.append(agent)
            }
        }

        let gatewayAgents = agents.filter { $0.gatewayId == gatewayId }
        if !resolvedIds.contains(selectedAgentId), let first = gatewayAgents.first {
            selectedAgentId = first.id
        } else if selectedAgentId.isEmpty, let first = gatewayAgents.first {
            selectedAgentId = first.id
        }
    }

    func createSession(for agentId: String, title: String = "新对话") -> Session {
        let session = Session(
            id: UUID().uuidString,
            agentId: agentId,
            title: title,
            category: "对话",
            lastMessage: nil,
            lastMessageTime: Date(),
            unreadCount: 0
        )
        sessions.insert(session, at: 0)
        return session
    }

    @discardableResult
    func startNewSession(title: String = "新对话") -> Session? {
        let resolvedAgentId: String

        if let selected = selectedAgent {
            resolvedAgentId = selected.id
        } else if let first = currentGatewayAgents.first {
            selectedAgentId = first.id
            resolvedAgentId = first.id
        } else if let first = agents.first {
            selectedAgentId = first.id
            resolvedAgentId = first.id
        } else {
            return nil
        }

        return createSession(for: resolvedAgentId, title: title)
    }

    func deleteSession(id: String) {
        sessions.removeAll { $0.id == id }
        messagesBySession.removeValue(forKey: id)
        chatScrollAnchorsBySession.removeValue(forKey: id)
        persistMessages()
    }

    func togglePinSession(id: String) {
        if let index = sessions.firstIndex(where: { $0.id == id }) {
            sessions[index].isPinned.toggle()
        }
    }

    func markGatewayOffline(_ gatewayId: String) {
        if let idx = gateways.firstIndex(where: { $0.id == gatewayId }) {
            gateways[idx].status = .offline
        }
        for i in agents.indices where agents[i].gatewayId == gatewayId {
            agents[i].status = .offline
        }
    }

    // MARK: - Message Store

    func messages(for sessionId: String) -> [StoredMessage] {
        messagesBySession[sessionId] ?? []
    }

    func appendMessage(to sessionId: String, message: StoredMessage) {
        messagesBySession[sessionId, default: []].append(message)
        persistMessages()

        if let idx = sessions.firstIndex(where: { $0.id == sessionId }) {
            sessions[idx].lastMessage = message.previewText
            sessions[idx].lastMessageTime = message.timestamp
        }
    }

    func updateMessage(in sessionId: String, messageId: String, text: String) {
        guard var msgs = messagesBySession[sessionId],
              let idx = msgs.firstIndex(where: { $0.id == messageId }) else { return }
        msgs[idx].text = text
        messagesBySession[sessionId] = msgs
        persistMessages()

        if sessions.first(where: { $0.id == sessionId }) != nil,
           idx == msgs.count - 1 {
            if let sIdx = sessions.firstIndex(where: { $0.id == sessionId }) {
                sessions[sIdx].lastMessage = msgs[idx].previewText
            }
        }
    }

    func chatScrollAnchor(for sessionId: String) -> String? {
        chatScrollAnchorsBySession[sessionId]
    }

    func setChatScrollAnchor(_ messageId: String?, for sessionId: String) {
        guard let messageId, !messageId.isEmpty else {
            chatScrollAnchorsBySession.removeValue(forKey: sessionId)
            return
        }

        chatScrollAnchorsBySession[sessionId] = messageId
    }

    // MARK: - Session Persistence

    private func persistSessions() {
        if let data = try? JSONEncoder().encode(sessions) {
            UserDefaults.standard.set(data, forKey: Self.sessionsKey)
        }
    }

    private func loadSessions() {
        guard let data = UserDefaults.standard.data(forKey: Self.sessionsKey),
              let saved = try? JSONDecoder().decode([Session].self, from: data) else { return }
        sessions = saved
    }

    // MARK: - Message Persistence

    private func persistMessages() {
        if let data = try? JSONEncoder().encode(messagesBySession) {
            UserDefaults.standard.set(data, forKey: Self.messagesKey)
        }
    }

    private func loadMessages() {
        guard let data = UserDefaults.standard.data(forKey: Self.messagesKey),
              let saved = try? JSONDecoder().decode([String: [StoredMessage]].self, from: data) else { return }
        messagesBySession = saved
    }

    // MARK: - Theme Persistence

    private func loadTheme() {
        guard let raw = UserDefaults.standard.string(forKey: Self.themeKey),
              let theme = AppVisualThemeID(rawValue: raw) else { return }
        selectedVisualThemeID = theme
    }

    private func parseAgentDescriptor(_ rawValue: String, meta: AgentMeta?) -> ParsedAgentDescriptor {
        let fallbackName = meta?.name ?? rawValue
        let fallbackModel = meta?.model

        let parts = rawValue.components(separatedBy: "::")
        if parts.count >= 3 {
            let id = parts[0].isEmpty ? parts[1] : parts[0]
            let name = parts[1].isEmpty ? fallbackName : parts[1]
            let model = parts.dropFirst(2).joined(separator: "::")
            let resolvedModel: String
            let availableModels: [String]?

            if parts.count >= 4 {
                resolvedModel = parts[2].isEmpty ? (fallbackModel ?? "unknown") : parts[2]
                let options = parts[3]
                    .split(separator: "|", omittingEmptySubsequences: true)
                    .map(String.init)
                availableModels = options.isEmpty ? [resolvedModel] : options
            } else {
                resolvedModel = model.isEmpty ? (fallbackModel ?? "unknown") : model
                availableModels = [resolvedModel]
            }

            return ParsedAgentDescriptor(
                id: id,
                name: name,
                model: resolvedModel,
                availableModels: availableModels
            )
        }

        return ParsedAgentDescriptor(
            id: rawValue,
            name: fallbackName,
            model: fallbackModel,
            availableModels: fallbackModel.map { [$0] }
        )
    }
}
