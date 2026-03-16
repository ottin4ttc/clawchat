import Foundation
import ClawChatKit

@Observable
final class ClawChatManager: @unchecked Sendable {

    enum LinkState: Equatable {
        case unpaired
        case connecting
        case connected
        case disconnected
        case error(String)
    }

    // MARK: - Observable state

    private(set) var linkState: LinkState = .unpaired
    private(set) var chatState: ChatState?
    private(set) var connectedGatewayId: String?
    private(set) var connectedRelayUrl: String?

    var isPaired: Bool {
        (try? credentialStore.load()) != nil
    }

    var isConnected: Bool {
        if case .connected = linkState { return true }
        return false
    }

    var liveMessages: [ChatMessage] {
        chatState?.messages ?? []
    }

    var isTyping: Bool {
        chatState?.isTyping ?? false
    }

    var gatewayOnline: Bool {
        chatState?.gatewayOnline ?? false
    }

    // MARK: - Internal

    private var webSocketClient: WebSocketClient?
    private var pairingManager: PairingManager?
    private let credentialStore = CredentialStore()

    weak var appState: AppState?

    // MARK: - Auto connect

    func autoConnect() async {
        guard let credentials = try? credentialStore.load() else {
            linkState = .unpaired
            return
        }
        await connect(relayUrl: credentials.relayUrl, deviceToken: credentials.deviceToken)
    }

    // MARK: - Pair

    func pair(relayUrl: String, code: String, deviceName: String) async throws {
        linkState = .connecting

        let client = WebSocketClient(relayUrl: relayUrl)
        webSocketClient = client
        await client.connect()

        let manager = PairingManager(client: client)
        pairingManager = manager

        do {
            let result = try await manager.pair(code: code, deviceName: deviceName)
            try credentialStore.save(
                deviceToken: result.deviceToken,
                relayUrl: relayUrl,
                gatewayId: result.gatewayId
            )
            connectedGatewayId = result.gatewayId
            connectedRelayUrl = relayUrl
            startChatState(client: client)
            chatState?.setGatewayOnline(true)
            linkState = .connected
            syncToAppState(
                gatewayId: result.gatewayId,
                relayUrl: relayUrl,
                agentIds: result.agents ?? ["default"]
            )
        } catch {
            linkState = .error(error.localizedDescription)
            throw error
        }
    }

    // MARK: - Reconnect

    func connect(relayUrl: String, deviceToken: String) async {
        linkState = .connecting

        let client = WebSocketClient(relayUrl: relayUrl)
        webSocketClient = client
        await client.connect()

        let manager = PairingManager(client: client)
        pairingManager = manager

        do {
            let result = try await manager.reconnect(deviceToken: deviceToken)

            if let newToken = result.newDeviceToken {
                try? credentialStore.save(
                    deviceToken: newToken,
                    relayUrl: relayUrl,
                    gatewayId: result.gatewayId
                )
            }

            connectedGatewayId = result.gatewayId
            connectedRelayUrl = relayUrl
            startChatState(client: client)
            chatState?.setGatewayOnline(result.gatewayOnline)
            linkState = .connected
            syncToAppState(
                gatewayId: result.gatewayId,
                relayUrl: relayUrl,
                agentIds: result.agents ?? ["default"]
            )
        } catch {
            linkState = .error(error.localizedDescription)
        }
    }

    // MARK: - Disconnect

    func disconnect() async {
        presenceObserverTask?.cancel()
        presenceObserverTask = nil
        chatState?.setGatewayOnline(false)
        chatState?.stop()
        chatState = nil
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
        connectedRelayUrl = nil
        linkState = .unpaired
    }

    // MARK: - Send

    func sendMessage(
        text: String,
        agentId: String = "default",
        attachments: [MessageAttachment] = []
    ) {
        chatState?.sendMessage(text: text, agentId: agentId, attachments: attachments)
    }

    @MainActor
    private func syncToAppState(gatewayId: String, relayUrl: String, agentIds: [String]) {
        appState?.applyConnectionInfo(
            gatewayId: gatewayId,
            relayUrl: relayUrl,
            agentIds: agentIds
        )
    }

    // MARK: - Helpers

    private func startChatState(client: WebSocketClient) {
        let state = ChatState(client: client)
        state.start()
        chatState = state

        Task {
            await client.setReconnectHandler { [weak self] in
                Task { @MainActor in
                    self?.handleWebSocketReconnect()
                }
            }
        }

        observeGatewayPresence()
    }

    private var presenceObserverTask: Task<Void, Never>?

    private func observeGatewayPresence() {
        presenceObserverTask?.cancel()
        presenceObserverTask = Task { @MainActor [weak self] in
            var wasOnline = self?.chatState?.gatewayOnline ?? false

            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(500))
                guard !Task.isCancelled, let self else { break }

                let isOnline = self.chatState?.gatewayOnline ?? false
                if isOnline && !wasOnline {
                    self.handleWebSocketReconnect()
                }
                wasOnline = isOnline
            }
        }
    }

    @MainActor
    private func handleWebSocketReconnect() {
        guard let credentials = try? credentialStore.load(),
              let client = webSocketClient else {
            print("[ClawChatManager] handleWebSocketReconnect: no credentials or client")
            return
        }
        print("[ClawChatManager] handleWebSocketReconnect: re-sending app.connect")

        linkState = .connecting
        let message = AppConnect(deviceToken: credentials.deviceToken)
        Task {
            await client.send(message)
            await MainActor.run { [weak self] in
                self?.linkState = .connected
            }
        }
    }
}
