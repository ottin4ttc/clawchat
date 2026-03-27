import SwiftUI
import ClawChatKit

// MARK: - Deep Link Parser

enum PairingDeepLink {
    enum ParsedLink {
        case relay(relay: String, code: String)
        case gateway(url: String, token: String)
    }

    static func parse(_ url: URL) -> ParsedLink? {
        guard url.scheme == "clawchat" else { return nil }
        let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        let items = components?.queryItems ?? []

        switch url.host {
        case "pair":
            guard let relay = items.first(where: { $0.name == "relay" })?.value,
                  let code = items.first(where: { $0.name == "code" })?.value else { return nil }
            return .relay(relay: relay, code: code)

        case "gateway":
            guard let gatewayUrl = items.first(where: { $0.name == "url" })?.value,
                  let token = items.first(where: { $0.name == "token" })?.value else { return nil }
            return .gateway(url: gatewayUrl, token: token)

        default:
            return nil
        }
    }
}

// MARK: - Floating Card Overlay (used at app root)

struct PairingOverlay: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        Color.clear
            .sheet(isPresented: Bindable(appState).showPairing) {
                ConnectionCardView()
                    .environment(appState)
                    .presentationDetents([.medium, .large])
                    .presentationDragIndicator(.visible)
                    .presentationBackground(Color(.systemGroupedBackground))
            }
    }
}

// MARK: - Connection Card (dual-mode)

struct ConnectionCardView: View {
    @Environment(AppState.self) private var appState

    @State private var selectedMode: ConnectionMethod = .direct
    @State private var isConnecting = false
    @State private var errorMessage: String?
    @State private var showScanner = false

    // Gateway direct fields
    @State private var gatewayUrl = ""
    @State private var gatewayToken = ""
    @State private var showToken = false

    // Relay pairing fields
    @State private var relayUrl = PairingDefaults.relayUrl
    @State private var pairingCode = ""

    private var accent: Color {
        appState.currentVisualTheme.accent
    }

    private var rawCode: String {
        pairingCode.replacingOccurrences(of: "-", with: "")
    }

    private var isFormValid: Bool {
        switch selectedMode {
        case .direct:
            return !gatewayUrl.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                && !gatewayToken.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        case .relay:
            return !relayUrl.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                && rawCode.count >= 6
        }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                ScrollView {
                    VStack(spacing: 0) { // Changed to 0 to control spacing exactly
                        // Header
                        VStack(spacing: 16) {
                            Image("clawos_svg_logo")
                                .resizable()
                                .renderingMode(.template)
                                .scaledToFit()
                                .frame(width: 64, height: 64)
                                .foregroundStyle(accent)

                            Text("连接 Gateway")
                                .font(.title2.weight(.bold))
                        }
                        .padding(.top, 40)
                        .padding(.bottom, 32) // Explicit spacing below header

                        modePicker
                            .padding(.bottom, 40) // Explicitly move form down by adding more space here

                        formArea

                        if let errorMessage {
                            errorBanner(errorMessage)
                                .padding(.top, 24)
                        }
                    }
                    .padding(.horizontal, 24)
                    .padding(.bottom, 24)
                }
                .scrollDismissesKeyboard(.interactively)

                Spacer(minLength: 0)

                // Bottom Actions
                buttonArea
                    .padding(.horizontal, 24)
                    .padding(.top, 16)
                    .padding(.bottom, 32) // Increased bottom padding to avoid hugging the keyboard
            }
            .background(Color(.systemGroupedBackground))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    if appState.clawChatManager.hasSavedConnection || !appState.gateways.isEmpty {
                        Button {
                            appState.showPairing = false
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.title3)
                                .symbolRenderingMode(.hierarchical)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .sheet(isPresented: $showScanner) {
                QRScannerSheet { parsed in
                    handleScannedLink(parsed)
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: .clawChatDeepLink)) { notification in
                if let relay = notification.userInfo?["relay"] as? String,
                   let code = notification.userInfo?["code"] as? String {
                    handleRelayDeepLink(relay, code)
                } else if let url = notification.userInfo?["gatewayUrl"] as? String,
                          let token = notification.userInfo?["gatewayToken"] as? String {
                    handleGatewayDeepLink(url, token)
                }
            }
        }
    }

    // MARK: - Mode Picker

    private var modePicker: some View {
        Picker("连接方式", selection: $selectedMode) {
            Text("Gateway 直连").tag(ConnectionMethod.direct)
            Text("Relay 配对").tag(ConnectionMethod.relay)
        }
        .pickerStyle(.segmented)
        .onChange(of: selectedMode) { _, _ in
            errorMessage = nil
        }
    }

    // MARK: - Form

    @ViewBuilder
    private var formArea: some View {
        switch selectedMode {
        case .direct:
            gatewayForm
        case .relay:
            relayForm
        }
    }

    private var gatewayForm: some View {
        VStack(spacing: 0) {
            TextField("Gateway URL", text: $gatewayUrl)
                .keyboardType(.URL)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
                .padding(.horizontal, 16)
                .frame(height: 54)

            Divider()
                .padding(.leading, 16)

            HStack {
                Group {
                    if showToken {
                        TextField("Token", text: $gatewayToken)
                    } else {
                        SecureField("Token", text: $gatewayToken)
                    }
                }
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)

                Button {
                    showToken.toggle()
                } label: {
                    Image(systemName: showToken ? "eye.slash" : "eye")
                        .foregroundStyle(.secondary)
                        .frame(width: 32, height: 32)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 16)
            .frame(height: 54)
        }
        .background(Color(uiColor: .systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(Color(uiColor: .separator).opacity(0.5), lineWidth: 0.5)
        )
    }

    private var relayForm: some View {
        VStack(spacing: 0) {
            TextField("Relay URL", text: $relayUrl)
                .keyboardType(.URL)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
                .padding(.horizontal, 16)
                .frame(height: 54)

            Divider()
                .padding(.leading, 16)

            TextField("配对码", text: $pairingCode)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.characters)
                .padding(.horizontal, 16)
                .frame(height: 54)
                .onChange(of: pairingCode) { _, newValue in
                    let cleaned = newValue.replacingOccurrences(of: "-", with: "")
                    let capped = String(cleaned.prefix(6)).uppercased()
                    if capped.count > 3 {
                        pairingCode = String(capped.prefix(3)) + "-" + String(capped.dropFirst(3))
                    } else {
                        pairingCode = capped
                    }
                }
        }
        .background(Color(uiColor: .systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(Color(uiColor: .separator).opacity(0.5), lineWidth: 0.5)
        )
    }

    // MARK: - Actions

    private var buttonArea: some View {
        HStack(spacing: 12) {
            Button {
                hideKeyboard()
                showScanner = true
            } label: {
                Image(systemName: "qrcode.viewfinder")
                    .font(.title3)
                    .frame(width: 50, height: 50)
                    .foregroundStyle(accent)
                    .background(
                        Color(.secondarySystemGroupedBackground),
                        in: RoundedRectangle(cornerRadius: 14, style: .continuous)
                    )
            }
            .buttonStyle(.plain)
            .disabled(isConnecting)

            Button {
                hideKeyboard()
                Task { await startConnection() }
            } label: {
                Group {
                    if isConnecting {
                        ProgressView()
                            .tint(.white)
                    } else {
                        Text("连接")
                            .font(.headline.weight(.semibold))
                    }
                }
                .frame(maxWidth: .infinity)
                .frame(height: 50)
                .foregroundStyle(.white)
                .background(
                    isFormValid ? accent : Color.gray.opacity(0.35),
                    in: RoundedRectangle(cornerRadius: 14, style: .continuous)
                )
            }
            .buttonStyle(.plain)
            .disabled(!isFormValid || isConnecting)
        }
    }

    // MARK: - Error

    private func errorBanner(_ message: String) -> some View {
        Label(message, systemImage: "exclamationmark.triangle.fill")
            .font(.subheadline)
            .foregroundStyle(.red)
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.red.opacity(0.1), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    // MARK: - Connection Logic

    private func startConnection() async {
        errorMessage = nil
        isConnecting = true

        do {
            switch selectedMode {
            case .direct:
                var url = gatewayUrl.trimmingCharacters(in: .whitespacesAndNewlines)
                if !url.hasPrefix("ws://") && !url.hasPrefix("wss://") {
                    url = "wss://\(url)"
                }
                try await appState.clawChatManager.connectGateway(
                    url: url,
                    token: gatewayToken.trimmingCharacters(in: .whitespacesAndNewlines)
                )

            case .relay:
                var url = relayUrl.trimmingCharacters(in: .whitespacesAndNewlines)
                if !url.hasPrefix("ws://") && !url.hasPrefix("wss://") {
                    url = "wss://\(url)"
                }
                try await appState.clawChatManager.pair(
                    relayUrl: url,
                    code: rawCode.trimmingCharacters(in: .whitespacesAndNewlines),
                    deviceName: UIDevice.current.name
                )
            }
        } catch {
            errorMessage = error.localizedDescription
        }

        isConnecting = false
    }

    // MARK: - Deep Link Handlers

    private func handleRelayDeepLink(_ relay: String, _ code: String) {
        selectedMode = .relay
        relayUrl = relay
        let cleaned = code.replacingOccurrences(of: "-", with: "").prefix(6).uppercased()
        if cleaned.count > 3 {
            pairingCode = String(cleaned.prefix(3)) + "-" + String(cleaned.dropFirst(3))
        } else {
            pairingCode = String(cleaned)
        }
        Task { await startConnection() }
    }

    private func handleGatewayDeepLink(_ url: String, _ token: String) {
        selectedMode = .direct
        gatewayUrl = url
        gatewayToken = token
    }

    private func handleScannedLink(_ parsed: PairingDeepLink.ParsedLink) {
        switch parsed {
        case .relay(let relay, let code):
            handleRelayDeepLink(relay, code)
        case .gateway(let url, let token):
            handleGatewayDeepLink(url, token)
        }
    }
}

enum PairingDefaults {
    static let relayUrl = ""
}

// MARK: - QR Scanner Sheet

private struct QRScannerSheet: View {
    let onParsed: (PairingDeepLink.ParsedLink) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            ZStack {
                QRScannerView { scannedValue in
                    handleScanned(scannedValue)
                }
                .ignoresSafeArea()

                VStack {
                    Spacer()

                    if let errorMessage {
                        Text(errorMessage)
                            .font(.caption.weight(.medium))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 10)
                            .background(.red.opacity(0.8), in: Capsule())
                            .padding(.bottom, 40)
                    }
                }
            }
            .navigationTitle("扫描二维码")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
            }
        }
    }

    private func handleScanned(_ value: String) {
        guard let url = URL(string: value),
              let parsed = PairingDeepLink.parse(url) else {
            errorMessage = "无效的二维码"
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                errorMessage = nil
            }
            return
        }
        dismiss()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            onParsed(parsed)
        }
    }
}

// MARK: - Helpers

extension View {
    func hideKeyboard() {
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }
}
