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
    private static let agentAvatarsKey = "clawos_agent_avatars"
    private static let agentTokensKey = "clawos_agent_tokens"
    private static let stripPrefix = "clawos_strip_"
    private static let messagePersistenceDebounceMilliseconds = 350
    private static let sessionPersistenceDebounceMilliseconds = 300
    private static let stripPersistenceDebounceMilliseconds = 300
    private static let tokenPersistenceDebounceMilliseconds = 1000

    var agents: [Agent] = []
    var gateways: [Gateway] = []
    var sessions: [Session] = [] {
        didSet {
            guard !isHydratingSessions else { return }
            schedulePersistSessions()
        }
    }
    var skills: [Skill] = []

    private(set) var messagesBySession: [String: [StoredMessage]] = [:]
    private var chatScrollAnchorsBySession: [String: String] = [:]
    private let messagePersistenceQueue = DispatchQueue(
        label: "clawos.message-persistence",
        qos: .utility
    )
    private var latestMessagesPersistenceRevision = 0
    private var pendingMessagePersistenceWorkItem: DispatchWorkItem?
    private var pendingSessionPersistenceWorkItem: DispatchWorkItem?
    private var pendingStripPersistenceWorkItem: DispatchWorkItem?
    private var pendingTokenPersistenceWorkItem: DispatchWorkItem?
    private var isHydratingSessions = false

    var selectedAgentId: String = ""
    var selectedGatewayId: String = ""
    var agentStripItems: [AgentStripItem] = [] {
        didSet { schedulePersistStripItems() }
    }
    var selectedStripItemId: String = ""
    private var preferredAgentByGroupId: [String: String] = [:]
    var selectedMoment: MockMoment?
    var selectedVisualThemeID: AppVisualThemeID = .eva00 {
        didSet {
            UserDefaults.standard.set(selectedVisualThemeID.rawValue, forKey: Self.themeKey)
        }
    }
    var colorScheme: ColorScheme = .light
    var showPairing = false

    let clawChatManager = ClawChatManager()

    init() {
        loadSessions()
        loadMessages()
        loadTheme()
    }

    func flushAllPendingPersistence() {
        flushPendingSessionPersistence()
        flushPendingMessagePersistence()
        flushPendingStripPersistence()
        flushPendingTokenPersistence()
    }

    var allAvailableModels: [String] {
        let models = agents.flatMap { $0.availableModels ?? [$0.model].compactMap { $0 } }
        return Array(Set(models.filter { !$0.isEmpty && $0 != "unknown" }))
    }

    var selectedAgent: Agent? {
        agents.first { $0.id == selectedAgentId }
    }

    var currentVisualTheme: AppVisualTheme {
        AppVisualTheme.theme(for: selectedVisualThemeID, colorScheme: colorScheme)
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
        loadStripItems()
        let visible = currentGatewayAgents
        if !visible.contains(where: { $0.id == selectedAgentId }),
           let first = visible.first {
            selectedAgentId = first.id
        }
    }

    var selectedAgentIds: [String] {
        guard !selectedStripItemId.isEmpty else {
            return currentGatewayAgents.map(\.id)
        }
        if let item = agentStripItems.first(where: { $0.id == selectedStripItemId }) {
            return item.containedAgentIds
        }
        return currentGatewayAgents.map(\.id)
    }

    func agent(for id: String) -> Agent? {
        agents.first { $0.id == id }
    }

    func sessions(for agentId: String) -> [Session] {
        sessions.filter { $0.agentId == agentId }
    }

    // MARK: - Agent Strip Management

    func selectStripItem(_ itemId: String) {
        selectedStripItemId = itemId
        if let item = agentStripItems.first(where: { $0.id == itemId }) {
            if case .single(let agentId) = item {
                selectedAgentId = agentId
            } else if case .group(let group) = item,
                      let resolved = resolvedAgentID(for: group, groupItemId: itemId) {
                selectedAgentId = resolved
            }
        }
    }

    func selectAgentInGroup(_ agentId: String, groupItemId: String) {
        guard let item = agentStripItems.first(where: { $0.id == groupItemId }),
              case .group(let group) = item,
              group.agentIds.contains(agentId) else { return }

        selectedStripItemId = groupItemId
        selectedAgentId = agentId
        preferredAgentByGroupId[groupItemId] = agentId
    }

    func preferredAgentInGroup(_ groupItemId: String) -> String? {
        guard let preferred = preferredAgentByGroupId[groupItemId],
              let item = agentStripItems.first(where: { $0.id == groupItemId }),
              case .group(let group) = item,
              group.agentIds.contains(preferred) else { return nil }
        return preferred
    }

    func moveStripItem(fromIndex: Int, toFinalIndex: Int) {
        guard agentStripItems.indices.contains(fromIndex),
              fromIndex != toFinalIndex else { return }

        let item = agentStripItems.remove(at: fromIndex)
        let insertAt = min(max(0, toFinalIndex), agentStripItems.count)
        agentStripItems.insert(item, at: insertAt)
    }

    func mergeStripItems(sourceId: String, targetId: String) {
        guard let srcIdx = agentStripItems.firstIndex(where: { $0.id == sourceId }),
              let tgtIdx = agentStripItems.firstIndex(where: { $0.id == targetId }),
              srcIdx != tgtIdx else { return }

        let sourceIds = agentStripItems[srcIdx].containedAgentIds
        let targetItem = agentStripItems[tgtIdx]

        switch targetItem {
        case .single(let targetAgentId):
            let group = AgentGroup(agentIds: [targetAgentId] + sourceIds)
            agentStripItems[tgtIdx] = .group(group)
        case .group(var group):
            group.agentIds.append(contentsOf: sourceIds)
            agentStripItems[tgtIdx] = .group(group)
        }

        agentStripItems.remove(at: srcIdx)
        cleanupPreferredAgents()
        selectedStripItemId = agentStripItems[min(tgtIdx, agentStripItems.count - 1)].id
    }

    func ungroupAgent(_ agentId: String, from groupId: String) {
        guard let idx = agentStripItems.firstIndex(where: { $0.id == groupId }),
              case .group(var group) = agentStripItems[idx] else { return }

        group.agentIds.removeAll { $0 == agentId }

        if group.agentIds.count <= 1 {
            if let remainingId = group.agentIds.first {
                agentStripItems[idx] = .single(agentId: remainingId)
            } else {
                agentStripItems.remove(at: idx)
            }
        } else {
            agentStripItems[idx] = .group(group)
        }

        agentStripItems.insert(.single(agentId: agentId), at: min(idx + 1, agentStripItems.count))
        cleanupPreferredAgents()
    }

    func dissolveGroup(_ groupId: String) {
        guard let idx = agentStripItems.firstIndex(where: { $0.id == groupId }),
              case .group(let group) = agentStripItems[idx] else { return }

        agentStripItems.remove(at: idx)
        for (offset, agentId) in group.agentIds.enumerated() {
            agentStripItems.insert(.single(agentId: agentId), at: min(idx + offset, agentStripItems.count))
        }
        cleanupPreferredAgents()
    }

    func renameGroup(_ groupId: String, to newName: String) {
        guard let idx = agentStripItems.firstIndex(where: { $0.id == groupId }),
              case .group(var group) = agentStripItems[idx] else { return }
        group.name = AgentGroup.normalizedName(newName)
        agentStripItems[idx] = .group(group)
    }

    func syncStripItems() {
        let gwAgentIds = Set(currentGatewayAgents.map(\.id))
        var knownIds = Set<String>()

        var cleaned = agentStripItems.compactMap { item -> AgentStripItem? in
            switch item {
            case .single(let agentId):
                guard gwAgentIds.contains(agentId) else { return nil }
                knownIds.insert(agentId)
                return item
            case .group(var group):
                group.name = AgentGroup.normalizedName(group.name)
                group.agentIds = group.agentIds.filter { gwAgentIds.contains($0) }
                group.agentIds.forEach { knownIds.insert($0) }
                if group.agentIds.isEmpty { return nil }
                if group.agentIds.count == 1 { return .single(agentId: group.agentIds[0]) }
                return .group(group)
            }
        }

        for agent in currentGatewayAgents where !knownIds.contains(agent.id) {
            cleaned.append(.single(agentId: agent.id))
        }

        agentStripItems = cleaned
        cleanupPreferredAgents()

        if !agentStripItems.contains(where: { $0.id == selectedStripItemId }),
           let first = agentStripItems.first {
            selectedStripItemId = first.id
        }
    }

    // MARK: - Populate from ClawChatManager

    func applyConnectionInfo(
        gatewayId: String,
        endpointUrl: String,
        agentIds: [String],
        agentsMeta: [String: AgentMeta]? = nil,
        connectionMethod: ConnectionMethod = .relay
    ) {
        let displayName = endpointUrl
            .replacingOccurrences(of: "wss://", with: "")
            .replacingOccurrences(of: "ws://", with: "")

        let gwType: GatewayType = connectionMethod == .direct ? .custom : .cloud
        let savedTokens = loadTokenUsage()

        let gateway = Gateway(
            id: gatewayId,
            name: displayName,
            url: endpointUrl,
            type: gwType,
            status: .online,
            connectionMethod: connectionMethod
        )

        if !gateways.contains(where: { $0.id == gatewayId }) {
            gateways.append(gateway)
        } else if let idx = gateways.firstIndex(where: { $0.id == gatewayId }) {
            gateways[idx].status = .online
            gateways[idx].connectionMethod = connectionMethod
        }

        selectedGatewayId = gatewayId

        // Skip agent updates when server returns empty list (gateway offline)
        guard !agentIds.isEmpty else { return }

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

            if let idx = agents.firstIndex(where: { $0.id == agentId }) {
                let resolvedModel = parsed.model ?? agents[idx].model
                let resolvedModels = parsed.availableModels ?? resolvedModel.map { [$0] } ?? agents[idx].availableModels
                agents[idx].name = agentName
                agents[idx].model = resolvedModel
                agents[idx].availableModels = resolvedModels
                agents[idx].status = .online
                if agents[idx].totalTokens == nil {
                    agents[idx].totalTokens = savedTokens[agentId]
                }
            } else {
                let savedAvatar = loadAgentAvatars()[agentId] ?? ""
                let agent = Agent(
                    id: agentId,
                    name: agentName,
                    avatar: savedAvatar,
                    status: .online,
                    unreadCount: 0,
                    gatewayId: gatewayId,
                    model: parsed.model,
                    availableModels: parsed.availableModels,
                    totalTokens: savedTokens[agentId]
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

        loadStripItems()
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
        schedulePersistMessages()
    }

    func togglePinSession(id: String) {
        if let index = sessions.firstIndex(where: { $0.id == id }) {
            sessions[index].isPinned.toggle()
        }
    }

    func updateAgentAvatar(id: String, avatar: String) {
        guard let idx = agents.firstIndex(where: { $0.id == id }) else { return }
        agents[idx].avatar = avatar
        persistAgentAvatars()
    }

    func updateAgentRuntimeModel(id: String, modelDisplayValue: String) {
        let trimmed = modelDisplayValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              let idx = agents.firstIndex(where: { $0.id == id }) else { return }

        agents[idx].model = trimmed

        var models = agents[idx].availableModels ?? []
        if !models.contains(trimmed) {
            models.insert(trimmed, at: 0)
        }
        agents[idx].availableModels = models
    }

    func addTokenUsage(agentId: String, tokens: Int) {
        guard tokens > 0,
              let idx = agents.firstIndex(where: { $0.id == agentId }) else { return }
        agents[idx].totalTokens = (agents[idx].totalTokens ?? 0) + tokens
        schedulePersistTokenUsage()
    }

    func deleteAgent(id: String) {
        AvatarStorage.remove(for: id)

        let relatedSessionIds = sessions.filter { $0.agentId == id }.map(\.id)
        for sessionId in relatedSessionIds {
            deleteSession(id: sessionId)
        }

        agents.removeAll { $0.id == id }
        persistAgentAvatars()

        agentStripItems.removeAll { item in
            switch item {
            case .single(let agentId): return agentId == id
            case .group(var group):
                group.agentIds.removeAll { $0 == id }
                return group.agentIds.isEmpty
            }
        }
        for idx in agentStripItems.indices {
            if case .group(var group) = agentStripItems[idx] {
                group.agentIds.removeAll { $0 == id }
                if group.agentIds.count == 1 {
                    agentStripItems[idx] = .single(agentId: group.agentIds[0])
                } else {
                    agentStripItems[idx] = .group(group)
                }
            }
        }
        flushPendingStripPersistence()

        if selectedAgentId == id {
            selectedAgentId = agents.first?.id ?? ""
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
        schedulePersistMessages()

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
        schedulePersistMessages()

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

    func flushPendingSessionPersistence() {
        pendingSessionPersistenceWorkItem?.cancel()
        pendingSessionPersistenceWorkItem = nil
        persistSessionsNow()
    }

    private func schedulePersistSessions() {
        pendingSessionPersistenceWorkItem?.cancel()

        let workItem = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.pendingSessionPersistenceWorkItem = nil
            self.persistSessionsNow()
        }
        pendingSessionPersistenceWorkItem = workItem

        DispatchQueue.main.asyncAfter(
            deadline: .now() + .milliseconds(Self.sessionPersistenceDebounceMilliseconds),
            execute: workItem
        )
    }

    private func persistSessionsNow() {
        if let data = try? JSONEncoder().encode(sessions) {
            UserDefaults.standard.set(data, forKey: Self.sessionsKey)
        }
    }

    private func loadSessions() {
        isHydratingSessions = true
        defer { isHydratingSessions = false }

        guard let data = UserDefaults.standard.data(forKey: Self.sessionsKey),
              let saved = try? JSONDecoder().decode([Session].self, from: data) else { return }
        sessions = saved
    }

    // MARK: - Message Persistence

    func flushPendingMessagePersistence() {
        pendingMessagePersistenceWorkItem?.cancel()
        pendingMessagePersistenceWorkItem = nil
        persistMessagesNow()
    }

    private func schedulePersistMessages() {
        pendingMessagePersistenceWorkItem?.cancel()

        let workItem = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.pendingMessagePersistenceWorkItem = nil
            self.persistMessagesNow()
        }
        pendingMessagePersistenceWorkItem = workItem

        DispatchQueue.main.asyncAfter(
            deadline: .now() + .milliseconds(Self.messagePersistenceDebounceMilliseconds),
            execute: workItem
        )
    }

    private func persistMessagesNow() {
        let snapshot = messagesBySession
        latestMessagesPersistenceRevision += 1
        let revision = latestMessagesPersistenceRevision

        messagePersistenceQueue.async {
            guard let data = try? JSONEncoder().encode(snapshot) else { return }

            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                guard self.latestMessagesPersistenceRevision == revision else { return }
                UserDefaults.standard.set(data, forKey: Self.messagesKey)
            }
        }
    }

    private func loadMessages() {
        guard let data = UserDefaults.standard.data(forKey: Self.messagesKey),
              let saved = try? JSONDecoder().decode([String: [StoredMessage]].self, from: data) else { return }
        messagesBySession = saved
    }

    // MARK: - Agent Avatar Persistence

    private func persistAgentAvatars() {
        let map = Dictionary(uniqueKeysWithValues: agents.map { ($0.id, $0.avatar) })
        if let data = try? JSONEncoder().encode(map) {
            UserDefaults.standard.set(data, forKey: Self.agentAvatarsKey)
        }
    }

    private func loadAgentAvatars() -> [String: String] {
        guard let data = UserDefaults.standard.data(forKey: Self.agentAvatarsKey),
              let map = try? JSONDecoder().decode([String: String].self, from: data) else { return [:] }
        return map
    }

    // MARK: - Token Usage Persistence

    func flushPendingTokenPersistence() {
        pendingTokenPersistenceWorkItem?.cancel()
        pendingTokenPersistenceWorkItem = nil
        persistTokenUsageNow()
    }

    private func schedulePersistTokenUsage() {
        pendingTokenPersistenceWorkItem?.cancel()

        let workItem = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.pendingTokenPersistenceWorkItem = nil
            self.persistTokenUsageNow()
        }
        pendingTokenPersistenceWorkItem = workItem

        DispatchQueue.main.asyncAfter(
            deadline: .now() + .milliseconds(Self.tokenPersistenceDebounceMilliseconds),
            execute: workItem
        )
    }

    private func persistTokenUsageNow() {
        let map = Dictionary(uniqueKeysWithValues: agents.compactMap { agent -> (String, Int)? in
            guard let tokens = agent.totalTokens, tokens > 0 else { return nil }
            return (agent.id, tokens)
        })
        if let data = try? JSONEncoder().encode(map) {
            UserDefaults.standard.set(data, forKey: Self.agentTokensKey)
        }
    }

    private func loadTokenUsage() -> [String: Int] {
        guard let data = UserDefaults.standard.data(forKey: Self.agentTokensKey),
              let map = try? JSONDecoder().decode([String: Int].self, from: data) else { return [:] }
        return map
    }

    // MARK: - Strip Persistence

    func flushPendingStripPersistence() {
        pendingStripPersistenceWorkItem?.cancel()
        pendingStripPersistenceWorkItem = nil
        persistStripItemsNow()
    }

    private func schedulePersistStripItems() {
        pendingStripPersistenceWorkItem?.cancel()

        let workItem = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.pendingStripPersistenceWorkItem = nil
            self.persistStripItemsNow()
        }
        pendingStripPersistenceWorkItem = workItem

        DispatchQueue.main.asyncAfter(
            deadline: .now() + .milliseconds(Self.stripPersistenceDebounceMilliseconds),
            execute: workItem
        )
    }

    private func persistStripItemsNow() {
        guard !selectedGatewayId.isEmpty else { return }
        let key = Self.stripPrefix + selectedGatewayId
        if let data = try? JSONEncoder().encode(agentStripItems) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }

    func loadStripItems() {
        guard !selectedGatewayId.isEmpty else { return }
        let key = Self.stripPrefix + selectedGatewayId
        if let data = UserDefaults.standard.data(forKey: key),
           let saved = try? JSONDecoder().decode([AgentStripItem].self, from: data) {
            agentStripItems = saved
        } else {
            agentStripItems = []
        }
        syncStripItems()
    }

    // MARK: - Theme Persistence

    private func loadTheme() {
        guard let raw = UserDefaults.standard.string(forKey: Self.themeKey),
              let theme = AppVisualThemeID(rawValue: raw) else { return }
        selectedVisualThemeID = theme
    }

    private func resolvedAgentID(for group: AgentGroup, groupItemId: String) -> String? {
        if let preferred = preferredAgentByGroupId[groupItemId], group.agentIds.contains(preferred) {
            return preferred
        }
        return group.agentIds.first
    }

    private func cleanupPreferredAgents() {
        preferredAgentByGroupId = preferredAgentByGroupId.filter { groupItemId, preferredAgentId in
            guard let item = agentStripItems.first(where: { $0.id == groupItemId }),
                  case .group(let group) = item else { return false }
            return group.agentIds.contains(preferredAgentId)
        }
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
