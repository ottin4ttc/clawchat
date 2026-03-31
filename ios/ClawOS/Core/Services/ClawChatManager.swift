import Foundation
import UIKit
import ClawChatKit

@MainActor
@Observable
final class ClawChatManager {

    enum LinkState: Equatable {
        case unpaired
        case connecting
        case connected
        case disconnected
        case error(String)
    }

    // MARK: - Observable state

    private(set) var linkState: LinkState = .unpaired
    private(set) var connectedGatewayId: String?
    private(set) var connectedEndpointUrl: String?
    private(set) var connectedMethod: ConnectionMethod?

    // Relay path
    private(set) var chatState: ChatState?
    // Gateway direct path
    private(set) var gatewaySession: GatewaySession?

    var hasSavedConnection: Bool {
        (try? credentialStore.load()) != nil
    }

    var savedConnectionMethod: ConnectionMethod? {
        try? credentialStore.load()?.method
    }

    var isConnected: Bool {
        if case .connected = linkState { return true }
        return false
    }

    var liveMessages: [ChatMessage] {
        gatewaySession?.messages ?? chatState?.messages ?? []
    }

    var isTyping: Bool {
        gatewaySession?.isTyping ?? chatState?.isTyping ?? false
    }

    func liveMessages(for agentId: String, sessionKey: String?) -> [ChatMessage] {
        if let gw = gatewaySession {
            return gw.liveMessages(for: agentId, sessionKey: sessionKey)
        }
        return chatState?.liveMessages(for: agentId, sessionKey: sessionKey) ?? []
    }

    func isTyping(for agentId: String, sessionKey: String?) -> Bool {
        if let gw = gatewaySession {
            return gw.isTyping(for: agentId, sessionKey: sessionKey)
        }
        return chatState?.isTyping(for: agentId, sessionKey: sessionKey) ?? false
    }

    var gatewayOnline: Bool {
        gatewaySession?.gatewayOnline ?? chatState?.gatewayOnline ?? false
    }

    // MARK: - Internal

    private var webSocketClient: WebSocketClient?
    private var pairingManager: PairingManager?
    private let credentialStore = CredentialStore()

    weak var appState: AppState?

    // MARK: - Auto connect (unified)

    func autoConnect() async {
        guard let profile = try? credentialStore.load() else {
            linkState = .unpaired
            return
        }

        switch profile.method {
        case .relay:
            await reconnectRelay(
                endpointUrl: profile.endpointUrl,
                deviceToken: profile.deviceToken
            )
        case .direct:
            await reconnectGateway(
                endpointUrl: profile.endpointUrl,
                deviceToken: profile.deviceToken
            )
        }
    }

    // MARK: - Relay Pair (existing flow)

    func pair(relayUrl: String, code: String, deviceName: String) async throws {
        linkState = .connecting

        let client = WebSocketClient(relayUrl: relayUrl)
        webSocketClient = client
        await client.connect()

        let manager = PairingManager(client: client)
        pairingManager = manager

        do {
            let result = try await manager.pair(code: code, deviceName: deviceName)
            try credentialStore.saveRelay(
                deviceToken: result.deviceToken,
                relayUrl: relayUrl,
                gatewayId: result.gatewayId
            )
            connectedGatewayId = result.gatewayId
            connectedEndpointUrl = relayUrl
            connectedMethod = .relay
            startChatState(client: client)
            chatState?.setGatewayOnline(true)
            linkState = .connected
            syncToAppState(
                gatewayId: result.gatewayId,
                endpointUrl: relayUrl,
                agentIds: result.agents ?? ["default"],
                method: .relay
            )
            await client.send(StatusRequest())
        } catch {
            linkState = .error(error.localizedDescription)
            throw error
        }
    }

    // MARK: - Gateway Direct Connect (native protocol)

    func connectGateway(url: String, token: String, bootstrapToken: String? = nil) async throws {
        linkState = .connecting

        let session = try GatewaySession(
            gatewayUrl: url,
            token: token,
            bootstrapToken: bootstrapToken,
            displayName: UIDevice.current.name
        )

        do {
            setupGatewaySessionCallbacks(session)
            let helloOk = try await session.connect()

            let deviceToken = helloOk.auth?.deviceToken ?? token
            let gatewayId = helloOk.server?.connId ?? "gateway"

            try credentialStore.saveDirect(
                deviceToken: deviceToken,
                gatewayUrl: url,
                gatewayId: gatewayId
            )

            connectedGatewayId = gatewayId
            connectedEndpointUrl = url
            connectedMethod = .direct
            gatewaySession = session
            linkState = .connected

            let agentId = helloOk.snapshot?.sessionDefaults?.defaultAgentId ?? "default"
            syncToAppState(
                gatewayId: gatewayId,
                endpointUrl: url,
                agentIds: [agentId],
                method: .direct
            )
            Task { @MainActor [weak session] in
                await session?.refreshSessionModel(sessionKey: session?.defaultSessionKey, agentId: agentId)
            }
        } catch {
            linkState = .error(error.localizedDescription)
            throw error
        }
    }

    // MARK: - Relay Reconnect

    private func reconnectRelay(endpointUrl: String, deviceToken: String) async {
        linkState = .connecting

        let client = WebSocketClient(relayUrl: endpointUrl)
        webSocketClient = client
        await client.connect()

        let manager = PairingManager(client: client)
        pairingManager = manager

        do {
            let result = try await manager.reconnect(deviceToken: deviceToken)

            if let newToken = result.newDeviceToken {
                try? credentialStore.save(profile: ConnectionProfile(
                    method: .relay,
                    endpointUrl: endpointUrl,
                    gatewayId: result.gatewayId,
                    deviceToken: newToken
                ))
            }

            connectedGatewayId = result.gatewayId
            connectedEndpointUrl = endpointUrl
            connectedMethod = .relay
            startChatState(client: client)
            chatState?.setGatewayOnline(result.gatewayOnline)
            linkState = .connected
            syncToAppState(
                gatewayId: result.gatewayId,
                endpointUrl: endpointUrl,
                agentIds: result.agents ?? ["default"],
                method: .relay
            )
            await client.send(StatusRequest())
        } catch {
            linkState = .disconnected
            print("[ClawChatManager] relay reconnect failed: \(error.localizedDescription)")
        }
    }

    // MARK: - Gateway Reconnect (uses deviceToken via native protocol)

    private func reconnectGateway(endpointUrl: String, deviceToken: String) async {
        linkState = .connecting

        do {
            let session = try GatewaySession(
                gatewayUrl: endpointUrl,
                deviceToken: deviceToken,
                displayName: UIDevice.current.name
            )
            setupGatewaySessionCallbacks(session)
            let helloOk = try await session.connect()

            if let newToken = helloOk.auth?.deviceToken, newToken != deviceToken {
                let gatewayId = helloOk.server?.connId ?? "gateway"
                try? credentialStore.save(profile: ConnectionProfile(
                    method: .direct,
                    endpointUrl: endpointUrl,
                    gatewayId: gatewayId,
                    deviceToken: newToken
                ))
            }

            let gatewayId = helloOk.server?.connId ?? connectedGatewayId ?? "gateway"
            connectedGatewayId = gatewayId
            connectedEndpointUrl = endpointUrl
            connectedMethod = .direct
            gatewaySession = session
            linkState = .connected

            let agentId = helloOk.snapshot?.sessionDefaults?.defaultAgentId ?? "default"
            syncToAppState(
                gatewayId: gatewayId,
                endpointUrl: endpointUrl,
                agentIds: [agentId],
                method: .direct
            )
            Task { @MainActor [weak session] in
                await session?.refreshSessionModel(sessionKey: session?.defaultSessionKey, agentId: agentId)
            }
        } catch {
            linkState = .disconnected
            print("[ClawChatManager] gateway reconnect failed: \(error.localizedDescription)")
        }
    }

    // MARK: - Disconnect

    func disconnect() async {
        presenceObserverTask?.cancel()
        presenceObserverTask = nil

        chatState?.setGatewayOnline(false)
        chatState?.stop()
        chatState = nil

        gatewaySession?.stop()
        gatewaySession = nil

        await webSocketClient?.close()
        webSocketClient = nil
        linkState = .disconnected

        if let gid = connectedGatewayId {
            appState?.markGatewayOffline(gid)
        }
    }

    func unpair() async {
        await disconnect()
        try? credentialStore.clear()
        connectedGatewayId = nil
        connectedEndpointUrl = nil
        connectedMethod = nil
        linkState = .unpaired
    }

    // MARK: - Send

    func sendMessage(
        text: String,
        agentId: String = "default",
        sessionKey: String? = nil,
        attachments: [MessageAttachment] = []
    ) {
        if let gw = gatewaySession {
            gw.sendMessage(text: text, sessionKey: sessionKey, agentId: agentId)
            return
        }

        if case .disconnected = linkState {
            Task { await webSocketClient?.reconnectIfNeeded() }
        } else if case .error = linkState {
            Task { await webSocketClient?.reconnectIfNeeded() }
        }
        chatState?.sendMessage(text: text, agentId: agentId, sessionKey: sessionKey, attachments: attachments)
    }

    @MainActor
    private func syncToAppState(
        gatewayId: String,
        endpointUrl: String,
        agentIds: [String],
        agentsMeta: [String: AgentMeta]? = nil,
        method: ConnectionMethod = .relay
    ) {
        appState?.applyConnectionInfo(
            gatewayId: gatewayId,
            endpointUrl: endpointUrl,
            agentIds: agentIds,
            agentsMeta: agentsMeta,
            connectionMethod: method
        )
    }

    // MARK: - Relay Chat State Setup

    private func startChatState(client: WebSocketClient) {
        let state = ChatState(client: client)
        state.start()
        chatState = state

        state.onAppConnected = { [weak self] connected in
            Task { @MainActor [weak self] in
                guard let self else { return }
                if let newToken = connected.newDeviceToken,
                   let endpointUrl = self.connectedEndpointUrl,
                   let method = self.connectedMethod {
                    try? self.credentialStore.save(profile: ConnectionProfile(
                        method: method,
                        endpointUrl: endpointUrl,
                        gatewayId: connected.gatewayId,
                        deviceToken: newToken
                    ))
                    print("[ClawChatManager] token rotated and saved")
                }
                self.chatState?.setGatewayOnline(connected.gatewayOnline ?? false)
                self.linkState = .connected

                if let agents = connected.agents, !agents.isEmpty,
                   let endpointUrl = self.connectedEndpointUrl {
                    self.syncToAppState(
                        gatewayId: connected.gatewayId,
                        endpointUrl: endpointUrl,
                        agentIds: agents,
                        method: self.connectedMethod ?? .relay
                    )
                }
            }
        }

        state.onStatusResponse = { [weak self] status in
            Task { @MainActor [weak self] in
                guard let self,
                      let gatewayId = self.connectedGatewayId,
                      let endpointUrl = self.connectedEndpointUrl else { return }
                self.syncToAppState(
                    gatewayId: gatewayId,
                    endpointUrl: endpointUrl,
                    agentIds: status.agents ?? [],
                    agentsMeta: status.agentsMeta,
                    method: self.connectedMethod ?? .relay
                )
                print("[ClawChatManager] agents refreshed: \(status.agents?.count ?? 0) agents")
            }
        }

        state.onFatalError = { [weak self] error in
            print("[ClawChatManager] fatal error: \(error.code) — \(error.message)")
            Task { [weak self] in
                await self?.unpair()
            }
        }

        Task {
            await client.setReconnectHandler { [weak self] in
                Task { [weak self] in
                    await self?.handleRelayReconnect()
                }
            }
        }

        observeRelayPresence()
    }

    // MARK: - Gateway Session Callbacks

    private func setupGatewaySessionCallbacks(_ session: GatewaySession) {
        session.onFatalError = { [weak self] message in
            print("[ClawChatManager] gateway fatal: \(message)")
            Task { [weak self] in
                await self?.unpair()
            }
        }

        session.onAgentsDiscovered = { [weak self] agentIds in
            Task { @MainActor [weak self] in
                guard let self,
                      let gatewayId = self.connectedGatewayId,
                      let endpointUrl = self.connectedEndpointUrl else { return }
                self.syncToAppState(
                    gatewayId: gatewayId,
                    endpointUrl: endpointUrl,
                    agentIds: agentIds,
                    method: .direct
                )
                print("[ClawChatManager] gateway agents discovered: \(agentIds)")
            }
        }

        session.onAgentsCatalogLoaded = { [weak self] catalog in
            Task { @MainActor [weak self] in
                guard let self,
                      let gatewayId = self.connectedGatewayId,
                      let endpointUrl = self.connectedEndpointUrl else { return }
                self.syncToAppState(
                    gatewayId: gatewayId,
                    endpointUrl: endpointUrl,
                    agentIds: catalog.agentIds,
                    agentsMeta: catalog.agentsMeta,
                    method: .direct
                )
                print("[ClawChatManager] gateway catalog loaded: \(catalog.agentIds)")
            }
        }

        session.onSessionModelResolved = { [weak self] selection, agentId in
            Task { @MainActor [weak self] in
                guard let self,
                      let displayValue = selection.displayValue else { return }
                self.appState?.updateAgentRuntimeModel(id: agentId, modelDisplayValue: displayValue)
                print("[ClawChatManager] gateway session model resolved: \(agentId) -> \(displayValue)")
            }
        }

        session.onTokenUsageReported = { [weak self] usage, agentId in
            Task { @MainActor [weak self] in
                self?.appState?.addTokenUsage(agentId: agentId, tokens: usage.totalTokens)
            }
        }
    }

    // MARK: - Relay Presence & Reconnect

    private var presenceObserverTask: Task<Void, Never>?

    private func observeRelayPresence() {
        presenceObserverTask?.cancel()
        presenceObserverTask = Task { @MainActor [weak self] in
            var wasOnline = self?.chatState?.gatewayOnline ?? false

            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(500))
                guard !Task.isCancelled, let self else { break }

                let isOnline = self.chatState?.gatewayOnline ?? false
                if isOnline && !wasOnline {
                    self.handleRelayReconnect()
                }
                wasOnline = isOnline
            }
        }
    }

    @MainActor
    private func handleRelayReconnect() {
        guard let profile = try? credentialStore.load(),
              profile.method == .relay,
              let client = webSocketClient else {
            return
        }
        print("[ClawChatManager] relay reconnect: re-sending app.connect")

        linkState = .connecting
        let message = AppConnect(deviceToken: profile.deviceToken)
        Task {
            await client.send(message)
        }
    }
}
