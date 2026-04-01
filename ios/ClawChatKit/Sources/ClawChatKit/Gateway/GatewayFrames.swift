import Foundation

// MARK: - Gateway Protocol Constants

public enum GatewayProtocol {
    public static let version = 3
    public static let clientId = "openclaw-ios"
    public static let clientMode = "ui"
    public static let clientVersion = "1.0.0"
    public static let controlUiClientId = "openclaw-control-ui"
}

// MARK: - Request Frame (client → gateway)

public struct GatewayRequestFrame<P: Encodable & Sendable>: Encodable, Sendable {
    public let type = "req"
    public let id: String
    public let method: String
    public let params: P

    public init(method: String, params: P) {
        self.id = UUID().uuidString
        self.method = method
        self.params = params
    }
}

public struct GatewayEmptyParams: Encodable, Sendable {
    public init() {}
}

// MARK: - Connect Params

public struct GatewayConnectParams: Encodable, Sendable {
    public let minProtocol: Int
    public let maxProtocol: Int
    public let client: ClientInfo
    public let auth: AuthInfo?
    public let role: String?
    public let scopes: [String]?
    public let device: DeviceBlock?

    public struct ClientInfo: Encodable, Sendable {
        public let id: String
        public let version: String
        public let platform: String
        public let mode: String
        public let displayName: String?
        public let deviceFamily: String?
    }

    public struct AuthInfo: Encodable, Sendable {
        public let token: String?
        public let deviceToken: String?
    }

    public static let defaultRole = "operator"

    public static let defaultScopes: [String] = [
        "operator.read",
        "operator.write",
        "operator.approvals"
    ]

    public static func make(
        token: String? = nil,
        deviceToken: String? = nil,
        displayName: String? = nil,
        deviceFamily: String? = nil,
        device: DeviceBlock? = nil,
        nonce: String? = nil,
        identity: DeviceIdentity? = nil
    ) throws -> GatewayConnectParams {
        let resolvedDevice: DeviceBlock? = try device ?? {
            guard let identity, let nonce else { return nil }
            return try identity.signConnectRequest(
                clientId: GatewayProtocol.clientId,
                clientMode: GatewayProtocol.clientMode,
                role: defaultRole,
                scopes: defaultScopes,
                token: token ?? deviceToken,
                nonce: nonce,
                platform: "ios",
                deviceFamily: deviceFamily
            )
        }()

        let hasAuth = token != nil || deviceToken != nil
        return GatewayConnectParams(
            minProtocol: GatewayProtocol.version,
            maxProtocol: GatewayProtocol.version,
            client: ClientInfo(
                id: GatewayProtocol.clientId,
                version: GatewayProtocol.clientVersion,
                platform: "ios",
                mode: GatewayProtocol.clientMode,
                displayName: displayName,
                deviceFamily: deviceFamily
            ),
            auth: hasAuth
                ? AuthInfo(token: token, deviceToken: deviceToken)
                : nil,
            role: defaultRole,
            scopes: defaultScopes,
            device: resolvedDevice
        )
    }
}

// MARK: - Chat Send Params (protocol: chat.send)

public struct GatewayChatSendAttachment: Encodable, Sendable {
    public let type: String?
    public let mimeType: String?
    public let fileName: String?
    public let content: String?

    public init(type: String? = nil, mimeType: String? = nil, fileName: String? = nil, content: String? = nil) {
        self.type = type
        self.mimeType = mimeType
        self.fileName = fileName
        self.content = content
    }
}

public struct GatewayChatSendParams: Encodable, Sendable {
    public let sessionKey: String
    public let message: String
    public let idempotencyKey: String
    public let thinking: String?
    public let deliver: Bool?
    public let attachments: [GatewayChatSendAttachment]?
    public let timeoutMs: Int?

    public init(
        sessionKey: String,
        message: String,
        idempotencyKey: String = UUID().uuidString,
        thinking: String? = nil,
        deliver: Bool? = nil,
        attachments: [GatewayChatSendAttachment]? = nil,
        timeoutMs: Int? = nil
    ) {
        self.sessionKey = sessionKey
        self.message = message
        self.idempotencyKey = idempotencyKey
        self.thinking = thinking
        self.deliver = deliver
        self.attachments = attachments
        self.timeoutMs = timeoutMs
    }
}

public struct GatewayChatSendResult: Decodable, Sendable {
    public let runId: String
    public let status: String // started | in_flight | ok | error
}

public struct GatewayAgentWaitParams: Encodable, Sendable {
    public let runId: String
    public let timeoutMs: Int?

    public init(runId: String, timeoutMs: Int? = nil) {
        self.runId = runId
        self.timeoutMs = timeoutMs
    }
}

public struct GatewayAgentWaitResult: Decodable, Sendable {
    public let runId: String
    public let status: String
    public let error: String?
    public let usage: GatewayTokenUsage?
}

// MARK: - Token Usage

public struct GatewayTokenUsage: Decodable, Sendable, Equatable {
    public let inputTokens: Int?
    public let outputTokens: Int?
    public let cacheCreationInputTokens: Int?
    public let cacheReadInputTokens: Int?

    public var totalTokens: Int {
        (inputTokens ?? 0) + (outputTokens ?? 0)
    }

    public init(
        inputTokens: Int? = nil,
        outputTokens: Int? = nil,
        cacheCreationInputTokens: Int? = nil,
        cacheReadInputTokens: Int? = nil
    ) {
        self.inputTokens = inputTokens
        self.outputTokens = outputTokens
        self.cacheCreationInputTokens = cacheCreationInputTokens
        self.cacheReadInputTokens = cacheReadInputTokens
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: FlexCodingKey.self)
        self.inputTokens = try container.decodeIfPresent(Int.self, forKey: .init("input_tokens"))
            ?? container.decodeIfPresent(Int.self, forKey: .init("inputTokens"))
        self.outputTokens = try container.decodeIfPresent(Int.self, forKey: .init("output_tokens"))
            ?? container.decodeIfPresent(Int.self, forKey: .init("outputTokens"))
        self.cacheCreationInputTokens = try container.decodeIfPresent(Int.self, forKey: .init("cache_creation_input_tokens"))
            ?? container.decodeIfPresent(Int.self, forKey: .init("cacheCreationInputTokens"))
        self.cacheReadInputTokens = try container.decodeIfPresent(Int.self, forKey: .init("cache_read_input_tokens"))
            ?? container.decodeIfPresent(Int.self, forKey: .init("cacheReadInputTokens"))
    }

    private struct FlexCodingKey: CodingKey {
        var stringValue: String
        var intValue: Int?
        init(_ key: String) { self.stringValue = key }
        init?(stringValue: String) { self.stringValue = stringValue }
        init?(intValue: Int) { return nil }
    }

    public static func estimated(inputChars: Int, outputChars: Int) -> GatewayTokenUsage {
        GatewayTokenUsage(
            inputTokens: max(1, inputChars * 10 / 25),
            outputTokens: max(1, outputChars * 10 / 25)
        )
    }
}

public struct GatewayChatHistoryParams: Encodable, Sendable {
    public let sessionKey: String
    public let limit: Int?

    public init(sessionKey: String, limit: Int? = nil) {
        self.sessionKey = sessionKey
        self.limit = limit
    }
}

public struct GatewaySessionsDeleteParams: Encodable, Sendable {
    public let key: String
    public let deleteTranscript: Bool?

    public init(key: String, deleteTranscript: Bool? = nil) {
        self.key = key
        self.deleteTranscript = deleteTranscript
    }
}

// MARK: - Sessions Reset (protocol: sessions.reset)

public struct GatewaySessionsResetParams: Encodable, Sendable {
    public let key: String
    public let reason: String?              // reset | new

    public init(key: String, reason: String? = nil) {
        self.key = key
        self.reason = reason
    }
}

public struct GatewaySessionsResetResult: Decodable, Sendable {
    public let ok: Bool
    public let key: String
}

// MARK: - Sessions Patch (protocol: sessions.patch)

public struct GatewaySessionsPatchParams: Encodable, Sendable {
    public let key: String
    public let label: String?
    public let model: String?
    public let modelProvider: String?
    public let thinkingLevel: String?
    public let verboseLevel: String?

    public init(
        key: String,
        label: String? = nil,
        model: String? = nil,
        modelProvider: String? = nil,
        thinkingLevel: String? = nil,
        verboseLevel: String? = nil
    ) {
        self.key = key
        self.label = label
        self.model = model
        self.modelProvider = modelProvider
        self.thinkingLevel = thinkingLevel
        self.verboseLevel = verboseLevel
    }
}

// MARK: - Sessions Compact (protocol: sessions.compact)

public struct GatewaySessionsCompactParams: Encodable, Sendable {
    public let key: String
    public let maxLines: Int?

    public init(key: String, maxLines: Int? = nil) {
        self.key = key
        self.maxLines = maxLines
    }
}

// MARK: - Sessions Preview (protocol: sessions.preview)

public struct GatewaySessionsPreviewParams: Encodable, Sendable {
    public let keys: [String]
    public let limit: Int?
    public let maxChars: Int?

    public init(keys: [String], limit: Int? = nil, maxChars: Int? = nil) {
        self.keys = keys
        self.limit = limit
        self.maxChars = maxChars
    }
}

// MARK: - Chat Abort (protocol: chat.abort)

public struct GatewayChatAbortParams: Encodable, Sendable {
    public let sessionKey: String
    public let runId: String?

    public init(sessionKey: String, runId: String? = nil) {
        self.sessionKey = sessionKey
        self.runId = runId
    }
}

public struct GatewayChatAbortResult: Decodable, Sendable {
    public let ok: Bool
    public let aborted: Bool
    public let runIds: [String]
}

// MARK: - Chat Inject (protocol: chat.inject)

public struct GatewayChatInjectParams: Encodable, Sendable {
    public let sessionKey: String
    public let message: String
    public let label: String?

    public init(sessionKey: String, message: String, label: String? = nil) {
        self.sessionKey = sessionKey
        self.message = message
        self.label = label
    }
}

// MARK: - Sessions List (protocol: sessions.list)

public struct GatewaySessionsListParams: Encodable, Sendable {
    public let limit: Int?
    public let agentId: String?
    public let includeDerivedTitles: Bool?
    public let includeLastMessage: Bool?
    public let search: String?
    public let label: String?
    public let spawnedBy: String?
    public let activeMinutes: Int?
    public let includeGlobal: Bool?
    public let includeUnknown: Bool?

    public init(
        limit: Int? = nil,
        agentId: String? = nil,
        includeDerivedTitles: Bool? = nil,
        includeLastMessage: Bool? = nil,
        search: String? = nil,
        label: String? = nil,
        spawnedBy: String? = nil,
        activeMinutes: Int? = nil,
        includeGlobal: Bool? = nil,
        includeUnknown: Bool? = nil
    ) {
        self.limit = limit
        self.agentId = agentId
        self.includeDerivedTitles = includeDerivedTitles
        self.includeLastMessage = includeLastMessage
        self.search = search
        self.label = label
        self.spawnedBy = spawnedBy
        self.activeMinutes = activeMinutes
        self.includeGlobal = includeGlobal
        self.includeUnknown = includeUnknown
    }
}

// MARK: - Hello Ok (gateway → client after successful connect)

public struct GatewayHelloOk: Decodable, Sendable {
    public let type: String
    public let `protocol`: Int
    public let server: ServerInfo?
    public let auth: AuthResult?
    public let snapshot: Snapshot?

    public struct ServerInfo: Decodable, Sendable {
        public let version: String?
        public let connId: String?
    }

    public struct AuthResult: Decodable, Sendable {
        public let deviceToken: String
        public let role: String
        public let scopes: [String]?
    }

    public struct Snapshot: Decodable, Sendable {
        public let sessionDefaults: SessionDefaults?

        public struct SessionDefaults: Decodable, Sendable {
            public let defaultAgentId: String?
            public let mainKey: String?
            public let mainSessionKey: String?
        }
    }
}

// MARK: - Gateway Error

public struct GatewayErrorPayload: Decodable, Sendable {
    public let code: String
    public let message: String
}

// MARK: - Chat Event (gateway → client, streaming)

public struct GatewayChatEvent: Decodable, Sendable {
    public let runId: String
    public let sessionKey: String
    public let seq: Int
    public let state: String
    public let message: MessageContent?
    public let errorMessage: String?
    public let stopReason: String?
    public let usage: GatewayTokenUsage?

    public struct MessageContent: Decodable, Sendable {
        public let content: [ContentBlock]?
        public let timestamp: Int64?

        public struct ContentBlock: Decodable, Sendable {
            public let type: String?
            public let text: String?
        }
    }

    public var textContent: String? {
        message?.content?.first(where: { $0.type == "text" })?.text
    }
}

// MARK: - Chat History Message (protocol: chat.history → messages[])

public struct GatewayMessageProvenance: Decodable, Sendable {
    public let kind: String?                // inter_session | external_user | internal_system
    public let sourceSessionKey: String?
    public let sourceChannel: String?
    public let sourceTool: String?
}

public struct GatewayTranscriptMessage: Decodable, Sendable {
    public let role: String                 // user | assistant | system | tool | toolResult
    public let content: [GatewayChatEvent.MessageContent.ContentBlock]?
    public let timestamp: Int64?
    public let model: String?
    public let stopReason: String?
    public let errorMessage: String?
    public let provenance: GatewayMessageProvenance?

    public var textContent: String? {
        let text = content?
            .filter { $0.type == "text" }
            .compactMap(\.text)
            .joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard let text, !text.isEmpty else { return nil }
        return text
    }
}

public struct GatewayChatHistoryResult: Decodable, Sendable {
    public let sessionKey: String?
    public let sessionId: String?
    public let messages: [GatewayTranscriptMessage]
    public let thinkingLevel: String?
    public let fastMode: Bool?
    public let verboseLevel: String?

    public var latestAssistantText: String? {
        messages
            .reversed()
            .first(where: { $0.role == "assistant" && $0.textContent != nil })?
            .textContent
    }
}

// MARK: - Health Event (contains agent list)

public struct GatewayHealthEvent: Decodable, Sendable {
    public let ok: Bool?
    public let defaultAgentId: String?
    public let agents: [AgentInfo]?

    public struct AgentInfo: Decodable, Sendable {
        public let agentId: String
        public let isDefault: Bool?
    }
}

// MARK: - Models List (protocol: models.list)

public struct GatewayModelsListResult: Decodable, Sendable {
    public let models: [ModelEntry]

    public struct ModelEntry: Decodable, Sendable {
        public let id: String
        public let name: String
        public let provider: String
        public let contextWindow: Int?
        public let reasoning: Bool?
        public let input: [String]?
    }
}

// MARK: - Agents CRUD (protocol: agents.create/update/delete)

public struct GatewayAgentsCreateParams: Encodable, Sendable {
    public let name: String
    public let workspace: String?
    public let model: String?

    public init(name: String, workspace: String? = nil, model: String? = nil) {
        self.name = name
        self.workspace = workspace
        self.model = model
    }
}

public struct GatewayAgentsUpdateParams: Encodable, Sendable {
    public let id: String
    public let name: String?
    public let workspace: String?
    public let model: String?

    public init(id: String, name: String? = nil, workspace: String? = nil, model: String? = nil) {
        self.id = id
        self.name = name
        self.workspace = workspace
        self.model = model
    }
}

public struct GatewayAgentsDeleteParams: Encodable, Sendable {
    public let id: String
    public let deleteFiles: Bool?

    public init(id: String, deleteFiles: Bool? = nil) {
        self.id = id
        self.deleteFiles = deleteFiles
    }
}

// MARK: - Agent Files (protocol: agents.files.list/get/set)

public struct GatewayAgentFilesListParams: Encodable, Sendable {
    public let agentId: String

    public init(agentId: String) {
        self.agentId = agentId
    }
}

public struct GatewayAgentFileItem: Decodable, Sendable {
    public let name: String
    public let path: String
    public let missing: Bool
    public let size: Int?
    public let updatedAtMs: Int64?
}

public struct GatewayAgentFilesListResult: Decodable, Sendable {
    public let agentId: String
    public let workspace: String
    public let files: [GatewayAgentFileItem]
}

public struct GatewayAgentFilesGetParams: Encodable, Sendable {
    public let agentId: String
    public let name: String

    public init(agentId: String, name: String) {
        self.agentId = agentId
        self.name = name
    }
}

public struct GatewayAgentFileGetResult: Decodable, Sendable {
    public let agentId: String
    public let workspace: String
    public let file: FileWithContent

    public struct FileWithContent: Decodable, Sendable {
        public let name: String
        public let path: String
        public let missing: Bool
        public let size: Int?
        public let updatedAtMs: Int64?
        public let content: String
    }
}

public struct GatewayAgentFilesSetParams: Encodable, Sendable {
    public let agentId: String
    public let name: String
    public let content: String

    public init(agentId: String, name: String, content: String) {
        self.agentId = agentId
        self.name = name
        self.content = content
    }
}

// MARK: - Agents List (protocol: agents.list)

public struct GatewayAgentsListResult: Decodable, Sendable {
    public let defaultId: String
    public let mainKey: String
    public let scope: String
    public let agents: [AgentSummary]

    public struct AgentSummary: Decodable, Sendable {
        public let id: String
        public let name: String?
        public let identity: Identity?

        public struct Identity: Decodable, Sendable {
            public let name: String?
            public let theme: String?
            public let emoji: String?
            public let avatar: String?
            public let avatarUrl: String?
        }
    }

    public var agentIds: [String] {
        agents.map(\.id)
    }

    public var agentsMeta: [String: AgentMeta] {
        Dictionary(uniqueKeysWithValues: agents.map { agent in
            let resolvedName = agent.name ?? agent.identity?.name ?? agent.id
            let resolvedAvatar = agent.identity?.avatarUrl ?? agent.identity?.avatar
            return (
                agent.id,
                AgentMeta(
                    name: resolvedName,
                    model: nil,
                    avatar: resolvedAvatar
                )
            )
        })
    }
}

public struct GatewaySessionModelSelection: Sendable, Equatable {
    public let provider: String?
    public let model: String?

    public init(provider: String?, model: String?) {
        self.provider = provider
        self.model = model
    }

    public var displayValue: String? {
        let trimmedProvider = provider?.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedModel = model?.trimmingCharacters(in: .whitespacesAndNewlines)

        if let trimmedProvider, !trimmedProvider.isEmpty,
           let trimmedModel, !trimmedModel.isEmpty {
            return "\(trimmedProvider)/\(trimmedModel)"
        }
        if let trimmedModel, !trimmedModel.isEmpty {
            return trimmedModel
        }
        return nil
    }
}

public struct GatewaySessionsListResult: Decodable, Sendable {
    public let ts: Int64?
    public let path: String?
    public let count: Int?
    public let defaults: Defaults?
    public let sessions: [SessionEntry]

    public struct Defaults: Decodable, Sendable {
        public let modelProvider: String?
        public let model: String?
        public let contextTokens: Int?
    }

    public struct SessionOrigin: Decodable, Sendable {
        public let key: String?
        public let label: String?
        public let channel: String?
        public let sessionId: String?
    }

    public struct SessionDeliveryContext: Decodable, Sendable {
        public let channel: String?
        public let to: String?
        public let accountId: String?
        public let threadId: String?
    }

    public struct SessionEntry: Decodable, Sendable {
        // 核心
        public let key: String
        public let kind: String?                        // direct | group | global | unknown
        public let label: String?
        public let displayName: String?
        public let derivedTitle: String?
        public let lastMessagePreview: String?
        public let updatedAt: Int64?

        // 渠道与来源
        public let channel: String?
        public let subject: String?
        public let groupChannel: String?
        public let space: String?
        public let chatType: String?
        public let origin: SessionOrigin?

        // 状态
        public let sessionId: String?
        public let systemSent: Bool?
        public let abortedLastRun: Bool?
        public let sendPolicy: String?                  // allow | deny

        // 模型
        public let modelProvider: String?
        public let model: String?
        public let modelOverride: String?
        public let providerOverride: String?
        public let contextTokens: Int?

        // 思考/推理级别
        public let thinkingLevel: String?
        public let verboseLevel: String?
        public let reasoningLevel: String?
        public let elevatedLevel: String?

        // token 统计
        public let inputTokens: Int?
        public let outputTokens: Int?
        public let totalTokens: Int?
        public let totalTokensFresh: Bool?
        public let responseUsage: String?               // on | off | tokens | full

        // 交付上下文
        public let deliveryContext: SessionDeliveryContext?
        public let lastChannel: String?
        public let lastTo: String?
        public let lastAccountId: String?

        /// 解析 session 显示标题，与 Web 端优先级一致：displayName > label > derivedTitle
        public var displayTitle: String? {
            for candidate in [displayName, label, derivedTitle] {
                guard let val = candidate, !val.isEmpty else { continue }
                // 过滤掉明显不是正常标题的值（raw metadata / JSON）
                let trimmed = val.trimmingCharacters(in: .whitespacesAndNewlines)
                if trimmed.hasPrefix("{") || trimmed.hasPrefix("```") || trimmed.hasPrefix("Sender (") {
                    continue
                }
                return trimmed
            }
            return nil
        }

        /// 从 key 解析 agentId（格式 "agent:<agentId>:<rest>"）
        public var parsedAgentId: String? {
            let parts = key.split(separator: ":", maxSplits: 2, omittingEmptySubsequences: false)
            guard parts.count == 3, parts[0] == "agent" else { return nil }
            return String(parts[1])
        }
    }

    public func modelSelection(forSessionKey sessionKey: String) -> GatewaySessionModelSelection? {
        let normalizedTarget = Self.normalizedMatchKey(sessionKey)

        if let matching = sessions.first(where: {
            Self.normalizedMatchKey($0.key) == normalizedTarget
        }) {
            let provider = matching.modelProvider ?? matching.providerOverride
            let model = matching.model ?? matching.modelOverride
            if provider != nil || model != nil {
                return GatewaySessionModelSelection(provider: provider, model: model)
            }
        }

        if defaults?.modelProvider != nil || defaults?.model != nil {
            return GatewaySessionModelSelection(
                provider: defaults?.modelProvider,
                model: defaults?.model
            )
        }

        return nil
    }

    private static func normalizedMatchKey(_ key: String?) -> String? {
        guard let key else { return nil }
        let normalized = key.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !normalized.isEmpty else { return nil }
        return agentSessionRest(normalized) ?? normalized
    }

    private static func agentSessionRest(_ key: String) -> String? {
        let parts = key.split(separator: ":", maxSplits: 2, omittingEmptySubsequences: false)
        guard parts.count == 3, parts[0] == "agent" else { return nil }
        return String(parts[2])
    }
}

// MARK: - Agent Stream Event (protocol event: agent)

public struct GatewayAgentStreamEvent: Decodable, Sendable {
    public let stream: String?              // assistant | lifecycle | tool
    public let data: [String: AnyCodable]?

    /// 简化包装，只提取 JSON 原始值
    public struct AnyCodable: Decodable, Sendable {
        public let value: Any?

        public init(from decoder: Decoder) throws {
            let container = try decoder.singleValueContainer()
            if let s = try? container.decode(String.self) { value = s }
            else if let i = try? container.decode(Int.self) { value = i }
            else if let d = try? container.decode(Double.self) { value = d }
            else if let b = try? container.decode(Bool.self) { value = b }
            else { value = nil }
        }
    }
}

// MARK: - Presence Event (protocol event: presence)

public struct GatewayPresenceEvent: Decodable, Sendable {
    public let status: String?              // online | offline
    public let agentId: String?
}

// MARK: - Cron Event (protocol event: cron)

public struct GatewayCronEvent: Decodable, Sendable {
    public let jobId: String
    public let action: String               // added | updated | removed | started | finished
    public let status: String?              // ok | error | skipped
    public let error: String?
    public let summary: String?
    public let sessionKey: String?
    public let durationMs: Int?
    public let nextRunAtMs: Int64?
}

// MARK: - Shutdown Event (protocol event: shutdown)

public struct GatewayShutdownEvent: Decodable, Sendable {
    public let reason: String?
}

// MARK: - Decoded Gateway Message

public enum GatewayMessage: Sendable {
    case connectChallenge(nonce: String)
    case helloOk(GatewayHelloOk)
    case responseOk(id: String, payload: Data)
    case responseError(id: String, error: GatewayErrorPayload)
    case chatEvent(GatewayChatEvent)
    case healthEvent(GatewayHealthEvent)
    case agentStreamEvent(GatewayAgentStreamEvent)
    case presenceEvent(GatewayPresenceEvent)
    case cronEvent(GatewayCronEvent)
    case shutdownEvent(GatewayShutdownEvent)
    case tick
    case unknown(Data)

    public static func decode(from data: Data) -> GatewayMessage {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let frameType = json["type"] as? String else {
            return .unknown(data)
        }

        switch frameType {
        case "event":
            return decodeEvent(json: json, raw: data)
        case "res":
            return decodeResponse(json: json, raw: data)
        default:
            return .unknown(data)
        }
    }

    private static func decodeEvent(json: [String: Any], raw: Data) -> GatewayMessage {
        guard let eventName = json["event"] as? String else { return .unknown(raw) }

        switch eventName {
        case "connect.challenge":
            if let payload = json["payload"] as? [String: Any],
               let nonce = payload["nonce"] as? String {
                return .connectChallenge(nonce: nonce)
            }
            return .unknown(raw)

        case "chat":
            guard let payload = json["payload"],
                  let payloadData = try? JSONSerialization.data(withJSONObject: payload),
                  let event = try? JSONDecoder().decode(GatewayChatEvent.self, from: payloadData) else {
                return .unknown(raw)
            }
            return .chatEvent(event)

        case "tick":
            return .tick

        case "health":
            guard let payload = json["payload"],
                  let payloadData = try? JSONSerialization.data(withJSONObject: payload),
                  let health = try? JSONDecoder().decode(GatewayHealthEvent.self, from: payloadData) else {
                return .unknown(raw)
            }
            return .healthEvent(health)

        case "agent":
            guard let payload = json["payload"],
                  let payloadData = try? JSONSerialization.data(withJSONObject: payload),
                  let event = try? JSONDecoder().decode(GatewayAgentStreamEvent.self, from: payloadData) else {
                return .unknown(raw)
            }
            return .agentStreamEvent(event)

        case "presence":
            guard let payload = json["payload"],
                  let payloadData = try? JSONSerialization.data(withJSONObject: payload),
                  let event = try? JSONDecoder().decode(GatewayPresenceEvent.self, from: payloadData) else {
                return .unknown(raw)
            }
            return .presenceEvent(event)

        case "cron":
            guard let payload = json["payload"],
                  let payloadData = try? JSONSerialization.data(withJSONObject: payload),
                  let event = try? JSONDecoder().decode(GatewayCronEvent.self, from: payloadData) else {
                return .unknown(raw)
            }
            return .cronEvent(event)

        case "shutdown":
            guard let payload = json["payload"],
                  let payloadData = try? JSONSerialization.data(withJSONObject: payload),
                  let event = try? JSONDecoder().decode(GatewayShutdownEvent.self, from: payloadData) else {
                return .unknown(raw)
            }
            return .shutdownEvent(event)

        default:
            return .unknown(raw)
        }
    }

    private static func decodeResponse(json: [String: Any], raw: Data) -> GatewayMessage {
        let id = json["id"] as? String ?? ""
        let ok = json["ok"] as? Bool ?? false

        if ok, let payload = json["payload"] as? [String: Any] {
            if payload["type"] as? String == "hello-ok",
               let payloadData = try? JSONSerialization.data(withJSONObject: payload),
               let helloOk = try? JSONDecoder().decode(GatewayHelloOk.self, from: payloadData) {
                return .helloOk(helloOk)
            }
            let payloadData = (try? JSONSerialization.data(withJSONObject: payload)) ?? Data()
            return .responseOk(id: id, payload: payloadData)
        }

        if !ok, let errDict = json["error"] as? [String: Any],
           let errData = try? JSONSerialization.data(withJSONObject: errDict),
           let error = try? JSONDecoder().decode(GatewayErrorPayload.self, from: errData) {
            return .responseError(id: id, error: error)
        }

        return .unknown(raw)
    }
}

// MARK: - Gateway Protocol Error

public enum GatewayProtocolError: Error, LocalizedError, Sendable {
    case challengeTimeout
    case authFailed(String)
    case requestFailed(String)
    case protocolMismatch
    case connectionClosed
    case invalidResponse

    public var errorDescription: String? {
        switch self {
        case .challengeTimeout: "Gateway 连接超时，未收到 challenge"
        case .authFailed(let msg): "认证失败：\(msg)"
        case .requestFailed(let msg): "请求失败：\(msg)"
        case .protocolMismatch: "协议版本不匹配"
        case .connectionClosed: "连接已关闭"
        case .invalidResponse: "无效的服务端响应"
        }
    }
}
