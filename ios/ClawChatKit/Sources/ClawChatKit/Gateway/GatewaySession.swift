import Foundation
import Observation

/// Manages a direct WebSocket connection to an OpenClaw Gateway.
/// Handles the challenge→connect→hello-ok handshake and translates
/// gateway chat events into the same `ChatMessage` model used by ChatState.
@MainActor
@Observable
public final class GatewaySession {

    // MARK: - Observable state (mirrors ChatState interface)

    public private(set) var messages: [ChatMessage] = []
    public private(set) var connectionState: ConnectionState = .disconnected
    public private(set) var gatewayOnline: Bool = false
    public private(set) var isTyping: Bool = false

    public var onAuthSuccess: ((GatewayHelloOk) -> Void)?
    public var onFatalError: ((String) -> Void)?
    public var onAgentsDiscovered: (([String]) -> Void)?
    public var onAgentsCatalogLoaded: ((GatewayAgentsListResult) -> Void)?
    public var onSessionModelResolved: ((GatewaySessionModelSelection, String) -> Void)?
    public var onTokenUsageReported: ((GatewayTokenUsage, String) -> Void)?

    // MARK: - Connection result

    public private(set) var helloOk: GatewayHelloOk?
    public private(set) var defaultSessionKey: String = "main"
    public private(set) var defaultAgentId: String = "main"

    // MARK: - Private state

    private let gatewayUrl: String
    private let token: String?
    private let deviceToken: String?
    private let displayName: String
    private let skipDeviceIdentity: Bool

    private var session: URLSession
    private var webSocketTask: URLSessionWebSocketTask?
    private var receiveTask: Task<Void, Never>?
    private var closed = false
    private var thinkingTracker = GatewayThinkingTracker()
    private let handshakeTimeout: TimeInterval = 15
    private let identity: DeviceIdentity
    private var savedDeviceToken: String?
    private var reconnectAttempt = 0
    private let maxReconnectAttempts = 10
    private var reconnectTask: Task<Void, Never>?
    private var responseContinuations: [String: CheckedContinuation<Data, Error>] = [:]
    private var handshakeContinuation: CheckedContinuation<GatewayHelloOk, Error>?
    /// Run IDs for which `chat.event` already reported server-side token usage (per-run; avoids cross-talk between concurrent sends).
    private var runIdsWithReportedServerUsage: Set<String> = []

    private var isUsingDeviceAuth: Bool {
        savedDeviceToken != nil || deviceToken != nil
    }

    // MARK: - Init

    public init(
        gatewayUrl: String,
        token: String? = nil,
        deviceToken: String? = nil,
        displayName: String = "iPhone",
        skipDeviceIdentity: Bool = false
    ) throws {
        let url = gatewayUrl.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        self.gatewayUrl = url
        self.token = token
        self.deviceToken = deviceToken
        self.displayName = displayName
        self.skipDeviceIdentity = skipDeviceIdentity
        self.session = URLSession(configuration: .default)
        self.identity = try DeviceIdentity.loadOrCreate()
    }

    // MARK: - Lifecycle

    public func connect() async throws -> GatewayHelloOk {
        guard !closed else { throw GatewayProtocolError.connectionClosed }
        setConnectionState(.connecting)

        guard let url = URL(string: gatewayUrl) else {
            throw GatewayProtocolError.authFailed("Invalid URL: \(gatewayUrl)")
        }

        var request = URLRequest(url: url)
        // When using control-ui client ID (skipDeviceIdentity mode), gateway checks Origin.
        // Set Origin to the tunnel's HTTPS origin so it matches allowedOrigins.
        if skipDeviceIdentity {
            let httpOrigin = gatewayUrl
                .replacingOccurrences(of: "wss://", with: "https://")
                .replacingOccurrences(of: "ws://", with: "http://")
            if let originUrl = URL(string: httpOrigin) {
                let origin = "\(originUrl.scheme ?? "https")://\(originUrl.host ?? "")"
                request.setValue(origin, forHTTPHeaderField: "Origin")
            }
        }
        let task = session.webSocketTask(with: request)
        self.webSocketTask = task
        task.resume()

        startReceiveLoop()

        do {
            return try await performHandshake()
        } catch {
            reconnectTask?.cancel()
            reconnectTask = nil
            receiveTask?.cancel()
            receiveTask = nil
            resetConnectionState(with: error)
            throw error
        }
    }

    @MainActor
    public func stop() {
        closed = true
        receiveTask?.cancel()
        receiveTask = nil
        reconnectTask?.cancel()
        reconnectTask = nil
        resumeHandshake(with: .failure(GatewayProtocolError.connectionClosed))
        webSocketTask?.cancel(with: .goingAway, reason: nil)
        webSocketTask = nil
        failPendingRequests(with: GatewayProtocolError.connectionClosed)
        thinkingTracker.clear()
        runIdsWithReportedServerUsage.removeAll()
        isTyping = false
        setConnectionState(.disconnected)
        gatewayOnline = false
    }

    // MARK: - Send Chat

    @MainActor
    public func sendMessage(text: String, sessionKey: String? = nil, agentId: String? = nil) {
        let resolvedKey = sessionKey ?? defaultSessionKey
        let userMessage = ChatMessage(role: .user, text: text, agentId: agentId, sessionKey: resolvedKey)
        messages.append(userMessage)

        let runId = UUID().uuidString
        let params = GatewayChatSendParams(
            sessionKey: resolvedKey,
            message: text,
            idempotencyKey: runId
        )

        Task { @MainActor [weak self] in
            guard let self else { return }
            var gotServerUsage = false
            do {
                let result: GatewayChatSendResult = try await request(
                    method: "chat.send",
                    params: params,
                    as: GatewayChatSendResult.self
                )
                beginThinking(
                    runId: result.runId,
                    route: ChatRoute(agentId: agentId ?? self.defaultAgentId, sessionKey: resolvedKey)
                )
                gotServerUsage = await awaitRunCompletionAndHydrate(
                    runId: result.runId,
                    sessionKey: resolvedKey
                )
                await refreshSessionModel(
                    sessionKey: resolvedKey,
                    agentId: agentId ?? self.defaultAgentId
                )
            } catch {
                markRunFailed(
                    runId: runId,
                    sessionKey: resolvedKey,
                    errorMessage: error.localizedDescription
                )
            }

            if !gotServerUsage {
                let assistantText = messages.last(where: { $0.role == .assistant && !$0.text.isEmpty })?.text ?? ""
                let estimated = GatewayTokenUsage.estimated(
                    inputChars: text.count,
                    outputChars: assistantText.count
                )
                if estimated.totalTokens > 0 {
                    reportUsage(estimated)
                }
            }
        }
    }

    @MainActor
    public func clearCompletedMessages(persistedIds: Set<String>) {
        messages.removeAll { msg in
            !msg.isStreaming && persistedIds.contains(msg.id)
        }
    }

    @MainActor
    public func liveMessages(for agentId: String, sessionKey: String?) -> [ChatMessage] {
        messages.filter { $0.route.matches(targetAgentId: agentId, targetSessionKey: sessionKey) }
    }

    @MainActor
    public func isTyping(for agentId: String, sessionKey: String?) -> Bool {
        thinkingTracker.isThinking(for: agentId, sessionKey: sessionKey)
    }

    // MARK: - Handshake

    private func performHandshake() async throws -> GatewayHelloOk {
        let timeoutNanoseconds = UInt64(handshakeTimeout * 1_000_000_000)

        return try await withThrowingTaskGroup(of: GatewayHelloOk.self) { group in
            group.addTask { @Sendable in
                try await Task.sleep(nanoseconds: timeoutNanoseconds)
                throw GatewayProtocolError.challengeTimeout
            }

            group.addTask { @Sendable [weak self] in
                guard let self else { throw GatewayProtocolError.connectionClosed }
                return try await self.awaitHandshakeCompletion()
            }

            guard let result = try await group.next() else {
                throw GatewayProtocolError.connectionClosed
            }
            group.cancelAll()
            return result
        }
    }

    private func awaitHandshakeCompletion() async throws -> GatewayHelloOk {
        try await withCheckedThrowingContinuation { continuation in
            self.handshakeContinuation = continuation
        }
    }

    private func handleChallenge(nonce: String) {
        let resolvedToken = savedDeviceToken != nil ? nil : token
        let resolvedDeviceToken = savedDeviceToken ?? deviceToken

        do {
            // When skipDeviceIdentity is true, don't send device block in connect request.
            // This allows shared token auth to bypass device pairing entirely —
            // gateway treats the client as a trusted operator without requiring approve.
            let resolvedIdentity: DeviceIdentity? = skipDeviceIdentity ? nil : identity
            let params = try GatewayConnectParams.make(
                token: resolvedToken,
                deviceToken: resolvedDeviceToken,
                displayName: displayName,
                deviceFamily: "iPhone",
                nonce: skipDeviceIdentity ? nil : nonce,
                identity: resolvedIdentity,
                useControlUiClientId: skipDeviceIdentity
            )
            let frame = GatewayRequestFrame(method: "connect", params: params)
            sendFrame(frame)
            print("[GatewaySession] sent connect (skipDevice=\(skipDeviceIdentity) device=\(identity.deviceId.prefix(12))… useDeviceToken=\(savedDeviceToken != nil))")
        } catch {
            let authError = GatewayProtocolError.authFailed("设备签名失败：\(error.localizedDescription)")
            resumeHandshake(with: .failure(authError))
        }
    }

    private func handleHelloOk(_ helloOk: GatewayHelloOk) {
        self.helloOk = helloOk

        if let newDeviceToken = helloOk.auth?.deviceToken {
            self.savedDeviceToken = newDeviceToken
        }

        if let defaults = helloOk.snapshot?.sessionDefaults {
            self.defaultSessionKey = defaults.mainSessionKey ?? defaults.mainKey ?? "main"
            self.defaultAgentId = defaults.defaultAgentId ?? self.defaultAgentId
        }

        reconnectAttempt = 0
        setConnectionState(.connected)
        gatewayOnline = true
        onAuthSuccess?(helloOk)
        resumeHandshake(with: .success(helloOk))

        Task { [weak self] in
            await self?.refreshAgentsCatalog()
        }

        print("[GatewaySession] connected, protocol=\(helloOk.protocol), server=\(helloOk.server?.version ?? "?")")
    }

    private func handleAuthError(_ error: GatewayErrorPayload) {
        let err = GatewayProtocolError.authFailed(error.message)
        resumeHandshake(with: .failure(err))
    }

    // MARK: - Receive Loop

    private func startReceiveLoop() {
        receiveTask?.cancel()
        receiveTask = Task { [weak self] in
            await self?.runReceiveLoop()
        }
    }

    private func runReceiveLoop() async {
        defer { receiveTask = nil }

        while !Task.isCancelled {
            guard let task = webSocketTask else { break }
            do {
                let wsMessage = try await task.receive()
                reconnectAttempt = 0
                handleReceived(wsMessage)
            } catch {
                if !Task.isCancelled && !closed {
                    resetConnectionState(with: GatewayProtocolError.requestFailed("连接中断"))
                    scheduleReconnect()
                }
                break
            }
        }
    }

    private func scheduleReconnect() {
        guard !closed else { return }
        guard reconnectAttempt < maxReconnectAttempts else {
            onFatalError?("Gateway 重连失败，已超过最大重试次数")
            return
        }

        let delay = min(pow(2.0, Double(reconnectAttempt)), 60.0)
        reconnectAttempt += 1
        print("[GatewaySession] reconnect in \(delay)s (attempt \(reconnectAttempt))")

        reconnectTask?.cancel()
        reconnectTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            guard let self, !Task.isCancelled else { return }
            await self.performReconnect()
        }
    }

    private func performReconnect() async {
        guard !closed, let url = URL(string: gatewayUrl) else { return }
        setConnectionState(.connecting)

        let task = session.webSocketTask(with: url)
        webSocketTask = task
        task.resume()
        startReceiveLoop()

        do {
            _ = try await performHandshake()
        } catch {
            receiveTask?.cancel()
            receiveTask = nil
            resetConnectionState(with: error)

            if case GatewayProtocolError.authFailed = error, isUsingDeviceAuth {
                onFatalError?(error.localizedDescription)
            } else {
                scheduleReconnect()
            }
        }
    }

    @MainActor
    private func handleReceived(_ wsMessage: URLSessionWebSocketTask.Message) {
        let data: Data
        switch wsMessage {
        case .string(let text):
            print("[GatewaySession] recv:", text.prefix(300))
            guard let d = text.data(using: .utf8) else { return }
            data = d
        case .data(let d):
            data = d
        @unknown default:
            return
        }

        let message = GatewayMessage.decode(from: data)
        dispatch(message)
    }

    @MainActor
    private func dispatch(_ message: GatewayMessage) {
        switch message {
        case .connectChallenge(let nonce):
            handleChallenge(nonce: nonce)

        case .helloOk(let ok):
            handleHelloOk(ok)

        case .responseError(let id, let error):
            if resolvePendingResponseError(error, id: id) {
                break
            }

            if handshakeContinuation != nil {
                handleAuthError(error)
            } else {
                let errorMsg = ChatMessage(
                    role: .assistant,
                    text: error.message,
                    isError: true
                )
                messages.append(errorMsg)
            }

        case .chatEvent(let event):
            handleChatEvent(event)

        case .healthEvent(let health):
            handleHealthEvent(health)

        case .responseOk(let id, let payload):
            resolvePendingResponseOK(id: id, payload: payload)

        case .tick:
            break

        case .unknown:
            break
        }
    }

    // MARK: - Health Event → Agent Discovery

    @MainActor
    private func handleHealthEvent(_ health: GatewayHealthEvent) {
        if let agentId = health.defaultAgentId {
            defaultAgentId = agentId
        }
        if let agents = health.agents, !agents.isEmpty {
            let agentIds = agents.map(\.agentId)
            onAgentsDiscovered?(agentIds)

            Task { @MainActor [weak self] in
                guard let self else { return }
                await self.refreshAgentsCatalog()
            }
        }
    }

    // MARK: - Chat Event → ChatMessage

    @MainActor
    private func handleChatEvent(_ event: GatewayChatEvent) {
        endThinking(runId: event.runId)
        messages = GatewayMessageReducer.applying(event, to: messages)
        if let usage = event.usage, usage.totalTokens > 0 {
            runIdsWithReportedServerUsage.insert(event.runId)
            reportUsage(usage)
        }
    }

    @discardableResult
    @MainActor
    private func awaitRunCompletionAndHydrate(runId: String, sessionKey: String) async -> Bool {
        defer { endThinking(runId: runId) }
        var gotUsageFromWait = false
        do {
            let waitResult: GatewayAgentWaitResult = try await request(
                method: "agent.wait",
                params: GatewayAgentWaitParams(runId: runId, timeoutMs: 90_000),
                as: GatewayAgentWaitResult.self
            )

            if let usage = waitResult.usage, usage.totalTokens > 0 {
                gotUsageFromWait = true
                runIdsWithReportedServerUsage.remove(runId)
                reportUsage(usage)
            }

            switch waitResult.status {
            case "ok":
                await hydrateRunFromHistory(runId: runId, sessionKey: sessionKey)

            case "error":
                await hydrateRunFromHistory(runId: runId, sessionKey: sessionKey)
                if let idx = messages.firstIndex(where: { $0.id == runId }),
                   messages[idx].text.isEmpty {
                    messages[idx].isError = true
                    messages[idx].text = waitResult.error ?? "Agent 运行失败"
                } else if messages.contains(where: { $0.id == runId }) == false {
                    markRunFailed(
                        runId: runId,
                        sessionKey: sessionKey,
                        errorMessage: waitResult.error ?? "Agent 运行失败"
                    )
                }

            case "timeout":
                markRunFailed(
                    runId: runId,
                    sessionKey: sessionKey,
                    errorMessage: "等待回复超时"
                )

            default:
                await hydrateRunFromHistory(runId: runId, sessionKey: sessionKey)
            }
        } catch {
            if messages.contains(where: { $0.id == runId }) == false {
                markRunFailed(
                    runId: runId,
                    sessionKey: sessionKey,
                    errorMessage: error.localizedDescription
                )
            }
        }
        let gotUsageFromStream = runIdsWithReportedServerUsage.remove(runId) != nil
        return gotUsageFromWait || gotUsageFromStream
    }

    @MainActor
    private func hydrateRunFromHistory(runId: String, sessionKey: String) async {
        do {
            let history: GatewayChatHistoryResult = try await request(
                method: "chat.history",
                params: GatewayChatHistoryParams(sessionKey: sessionKey, limit: 20),
                as: GatewayChatHistoryResult.self
            )
            messages = GatewayMessageReducer.hydrating(
                runId: runId,
                sessionKey: sessionKey,
                with: history,
                in: messages
            )
        } catch {
            print("[GatewaySession] chat.history failed: \(error.localizedDescription)")
        }
    }

    @MainActor
    private func refreshAgentsCatalog() async {
        do {
            let catalog: GatewayAgentsListResult = try await request(
                method: "agents.list",
                params: GatewayEmptyParams(),
                as: GatewayAgentsListResult.self
            )
            defaultAgentId = catalog.defaultId
            onAgentsCatalogLoaded?(catalog)
            onAgentsDiscovered?(catalog.agentIds)
        } catch {
            print("[GatewaySession] agents.list failed: \(error.localizedDescription)")
        }
    }

    @MainActor
    public func refreshSessionModel(sessionKey: String? = nil, agentId: String? = nil) async {
        let resolvedSessionKey = sessionKey ?? defaultSessionKey
        let resolvedAgentId = agentId ?? defaultAgentId

        do {
            let result: GatewaySessionsListResult = try await request(
                method: "sessions.list",
                params: GatewaySessionsListParams(
                    includeGlobal: false,
                    includeUnknown: false,
                    agentId: resolvedAgentId
                ),
                as: GatewaySessionsListResult.self
            )

            guard let selection = result.modelSelection(forSessionKey: resolvedSessionKey) else { return }

            onSessionModelResolved?(selection, resolvedAgentId)
        } catch {
            print("[GatewaySession] sessions.list failed: \(error.localizedDescription)")
        }
    }

    // MARK: - Send Helper

    private func sendFrame<P: Encodable & Sendable>(_ frame: GatewayRequestFrame<P>) {
        guard let task = webSocketTask, task.state == .running else {
            print("[GatewaySession] send dropped: no active connection")
            return
        }
        do {
            let data = try JSONEncoder().encode(frame)
            guard let text = String(data: data, encoding: .utf8) else { return }
            task.send(.string(text)) { error in
                if let error {
                    print("[GatewaySession] send error: \(error.localizedDescription)")
                }
            }
        } catch {
            print("[GatewaySession] encode error: \(error)")
        }
    }

    @MainActor
    private func request<P: Encodable & Sendable, R: Decodable>(
        method: String,
        params: P,
        as type: R.Type
    ) async throws -> R {
        let payload = try await request(method: method, params: params)
        guard let decoded = try? JSONDecoder().decode(R.self, from: payload) else {
            throw GatewayProtocolError.invalidResponse
        }
        return decoded
    }

    @MainActor
    private func request<P: Encodable & Sendable>(method: String, params: P) async throws -> Data {
        let frame = GatewayRequestFrame(method: method, params: params)

        guard let task = webSocketTask, task.state == .running else {
            throw GatewayProtocolError.connectionClosed
        }

        let data = try JSONEncoder().encode(frame)
        guard let text = String(data: data, encoding: .utf8) else {
            throw GatewayProtocolError.invalidResponse
        }
        let requestID = frame.id

        return try await withCheckedThrowingContinuation { continuation in
            responseContinuations[requestID] = continuation
            task.send(.string(text)) { [weak self] error in
                guard let error else { return }
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    let pending = self.responseContinuations.removeValue(forKey: requestID)
                    pending?.resume(throwing: GatewayProtocolError.requestFailed(error.localizedDescription))
                }
            }
        }
    }

    @MainActor
    private func markRunFailed(runId: String, sessionKey: String, errorMessage: String) {
        endThinking(runId: runId)
        if let idx = messages.firstIndex(where: { $0.id == runId }) {
            messages[idx].isError = true
            messages[idx].isStreaming = false
            if messages[idx].text.isEmpty {
                messages[idx].text = errorMessage
            }
            messages[idx].sessionKey = sessionKey
            return
        }

        messages.append(
            ChatMessage(
                id: runId,
                role: .assistant,
                text: errorMessage,
                isError: true,
                sessionKey: sessionKey
            )
        )
    }

    @MainActor
    private func resolvePendingResponseOK(id: String, payload: Data) {
        let continuation = responseContinuations.removeValue(forKey: id)
        continuation?.resume(returning: payload)
    }

    @MainActor
    private func resolvePendingResponseError(_ error: GatewayErrorPayload, id: String) -> Bool {
        guard let continuation = responseContinuations.removeValue(forKey: id) else {
            return false
        }
        continuation.resume(throwing: GatewayProtocolError.requestFailed(error.message))
        return true
    }

    @MainActor
    private func failPendingRequests(with error: Error) {
        let continuations = Array(responseContinuations.values)
        responseContinuations.removeAll()
        continuations.forEach { $0.resume(throwing: error) }
    }

    @MainActor
    private func beginThinking(runId: String, route: ChatRoute) {
        thinkingTracker.begin(runId: runId, route: route)
        refreshTypingState()
    }

    @MainActor
    private func endThinking(runId: String) {
        thinkingTracker.end(runId: runId)
        refreshTypingState()
    }

    @MainActor
    private func refreshTypingState() {
        isTyping = thinkingTracker.hasActiveRuns
    }

    @MainActor
    private func reportUsage(_ usage: GatewayTokenUsage) {
        onTokenUsageReported?(usage, defaultAgentId)
    }

    // MARK: - Helpers

    private func resumeHandshake(with result: Result<GatewayHelloOk, Error>) {
        guard let continuation = handshakeContinuation else { return }
        handshakeContinuation = nil

        switch result {
        case .success(let helloOk):
            continuation.resume(returning: helloOk)
        case .failure(let error):
            continuation.resume(throwing: error)
        }
    }

    private func resetConnectionState(with error: Error) {
        resumeHandshake(with: .failure(error))
        webSocketTask?.cancel(with: .goingAway, reason: nil)
        webSocketTask = nil
        failPendingRequests(with: error)
        thinkingTracker.clear()
        runIdsWithReportedServerUsage.removeAll()
        isTyping = false
        gatewayOnline = false
        setConnectionState(.disconnected)
    }

    private func setConnectionState(_ state: ConnectionState) {
        connectionState = state
    }
}
