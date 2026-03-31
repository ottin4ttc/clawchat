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
        public let bootstrapToken: String?
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
        bootstrapToken: String? = nil,
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

        let hasAuth = token != nil || deviceToken != nil || bootstrapToken != nil
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
                ? AuthInfo(token: token, deviceToken: deviceToken, bootstrapToken: bootstrapToken)
                : nil,
            role: defaultRole,
            scopes: defaultScopes,
            device: resolvedDevice
        )
    }
}

// MARK: - Chat Send Params

public struct GatewayChatSendParams: Encodable, Sendable {
    public let sessionKey: String
    public let message: String
    public let idempotencyKey: String

    public init(sessionKey: String, message: String, idempotencyKey: String = UUID().uuidString) {
        self.sessionKey = sessionKey
        self.message = message
        self.idempotencyKey = idempotencyKey
    }
}

public struct GatewayChatSendResult: Decodable, Sendable {
    public let runId: String
    public let status: String
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

public struct GatewaySessionsListParams: Encodable, Sendable {
    public let limit: Int?
    public let activeMinutes: Int?
    public let includeGlobal: Bool?
    public let includeUnknown: Bool?
    public let includeDerivedTitles: Bool?
    public let includeLastMessage: Bool?
    public let agentId: String?
    public let search: String?

    public init(
        limit: Int? = nil,
        activeMinutes: Int? = nil,
        includeGlobal: Bool? = nil,
        includeUnknown: Bool? = nil,
        includeDerivedTitles: Bool? = nil,
        includeLastMessage: Bool? = nil,
        agentId: String? = nil,
        search: String? = nil
    ) {
        self.limit = limit
        self.activeMinutes = activeMinutes
        self.includeGlobal = includeGlobal
        self.includeUnknown = includeUnknown
        self.includeDerivedTitles = includeDerivedTitles
        self.includeLastMessage = includeLastMessage
        self.agentId = agentId
        self.search = search
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

public struct GatewayTranscriptMessage: Decodable, Sendable {
    public let role: String
    public let content: [GatewayChatEvent.MessageContent.ContentBlock]?
    public let timestamp: Int64?
    public let stopReason: String?

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

    public struct SessionEntry: Decodable, Sendable {
        public let key: String
        public let modelProvider: String?
        public let model: String?
        public let modelOverride: String?
        public let providerOverride: String?
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

// MARK: - Decoded Gateway Message

public enum GatewayMessage: Sendable {
    case connectChallenge(nonce: String)
    case helloOk(GatewayHelloOk)
    case responseOk(id: String, payload: Data)
    case responseError(id: String, error: GatewayErrorPayload)
    case chatEvent(GatewayChatEvent)
    case healthEvent(GatewayHealthEvent)
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
