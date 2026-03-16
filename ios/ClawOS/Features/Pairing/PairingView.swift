import SwiftUI

// MARK: - Floating Card Overlay (used at app root)

struct PairingOverlay: View {
    @Environment(AppState.self) private var appState
    @Namespace private var glassNS

    private var shouldShow: Bool {
        appState.showPairing
    }

    var body: some View {
        ZStack {
            if shouldShow {
                Color.black.opacity(0.4)
                    .ignoresSafeArea()
                    .transition(.opacity)
                    .onTapGesture {
                        hideKeyboard()
                    }

                PairingCardView()
                    .environment(appState)
                    .transition(.scale(scale: 0.92).combined(with: .opacity))
                    .padding(.horizontal, 24)
            }
        }
        .animation(.spring(response: 0.45, dampingFraction: 0.85), value: shouldShow)
    }
}

// MARK: - Pairing Card

struct PairingCardView: View {
    @Environment(AppState.self) private var appState
    @State private var relayUrl = ""
    @State private var pairingCode = ""
    @State private var isPairing = false
    @State private var errorMessage: String?
    @FocusState private var focusedField: Field?

    private enum Field: Hashable { case relay, code }

    private var isFormValid: Bool {
        !relayUrl.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        && rawCode.count >= 6
    }

    private var rawCode: String {
        pairingCode.replacingOccurrences(of: "-", with: "")
    }

    private var accent: Color {
        appState.currentVisualTheme.accent
    }

    var body: some View {
        VStack(spacing: 0) {
            headerArea
                .padding(.top, 32)
                .padding(.bottom, 28)

            formArea
                .padding(.horizontal, 24)

            if let errorMessage {
                errorBanner(errorMessage)
                    .padding(.horizontal, 24)
                    .padding(.top, 16)
            }

            pairButton
                .padding(.horizontal, 24)
                .padding(.top, 32)
                .padding(.bottom, 12)

            if appState.clawChatManager.isPaired {
                cancelButton
                    .padding(.bottom, 8)
            }
        }
        .padding(.bottom, 20)
        .background(
            RoundedRectangle(cornerRadius: 36, style: .continuous)
                .fill(.regularMaterial)
        )
        .glassEffect(.regular, in: .rect(cornerRadius: 36))
        .overlay(
            RoundedRectangle(cornerRadius: 36, style: .continuous)
                .stroke(Color.white.opacity(0.4), lineWidth: 0.5)
                .blendMode(.overlay)
        )
        .shadow(color: .black.opacity(0.15), radius: 40, y: 20)
        .shadow(color: .black.opacity(0.08), radius: 15, y: 8)
        .onTapGesture {
            hideKeyboard()
        }
    }

    // MARK: - Header

    private var headerArea: some View {
        VStack(spacing: 16) {
            Image("clawos_svg_logo")
                .resizable()
                .renderingMode(.template)
                .scaledToFit()
                .frame(width: 56, height: 56)
                .foregroundStyle(accent)

            VStack(spacing: 6) {
                Text("配对 Gateway")
                    .font(.title3.weight(.bold))

                Text("输入 Relay 地址与配对码")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Form

    private var formArea: some View {
        VStack(spacing: 16) {
            fieldRow(
                label: "Relay 地址",
                placeholder: "wss://relay.clawchat.dev",
                text: $relayUrl,
                keyboard: .URL,
                field: .relay,
                monospaced: false
            )

            fieldRow(
                label: "配对码",
                placeholder: "ABC-123",
                text: $pairingCode,
                keyboard: .asciiCapable,
                field: .code,
                monospaced: true
            )
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
    }

    private func fieldRow(
        label: String,
        placeholder: String,
        text: Binding<String>,
        keyboard: UIKeyboardType,
        field: Field,
        monospaced: Bool
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(label)
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
                .padding(.leading, 4)

            HStack {
                TextField(placeholder, text: text)
                    .textFieldStyle(.plain)
                    .font(monospaced ? .system(.body, design: .monospaced, weight: .semibold) : .body)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(monospaced ? .characters : .never)
                    .keyboardType(keyboard)
                    .focused($focusedField, equals: field)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color(.systemBackground).opacity(0.5))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(Color.white.opacity(0.3), lineWidth: 0.5)
                    .blendMode(.overlay)
            )
            .contentShape(Rectangle())
            .onTapGesture {
                focusedField = field
            }
        }
    }

    // MARK: - Actions

    private var pairButton: some View {
        Button {
            hideKeyboard()
            Task { await startPairing() }
        } label: {
            Group {
                if isPairing {
                    ProgressView()
                        .tint(.white)
                } else {
                    Label("开始配对", systemImage: "link")
                        .font(.headline.weight(.semibold))
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: 52)
            .foregroundStyle(.white)
            .background(
                isFormValid ? accent : Color.gray.opacity(0.4),
                in: RoundedRectangle(cornerRadius: 18, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(Color.white.opacity(0.2), lineWidth: 1)
                    .blendMode(.overlay)
            )
        }
        .disabled(!isFormValid || isPairing)
        .shadow(color: isFormValid ? accent.opacity(0.3) : .clear, radius: 10, y: 4)
    }

    private var cancelButton: some View {
        Button {
            hideKeyboard()
            withAnimation { appState.showPairing = false }
        } label: {
            Text("取消")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity)
                .frame(height: 40)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Error

    private func errorBanner(_ message: String) -> some View {
        Label(message, systemImage: "exclamationmark.triangle.fill")
            .font(.caption.weight(.medium))
            .foregroundStyle(.red)
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.red.opacity(0.1), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(.red.opacity(0.2), lineWidth: 1)
            )
    }

    // MARK: - Pairing Logic

    private func startPairing() async {
        errorMessage = nil
        isPairing = true

        var url = relayUrl.trimmingCharacters(in: .whitespacesAndNewlines)
        if !url.hasPrefix("ws://") && !url.hasPrefix("wss://") {
            url = "wss://\(url)"
        }

        let code = rawCode.trimmingCharacters(in: .whitespacesAndNewlines)

        do {
            try await appState.clawChatManager.pair(
                relayUrl: url,
                code: code,
                deviceName: UIDevice.current.name
            )
        } catch {
            errorMessage = error.localizedDescription
        }

        isPairing = false
    }
}

// MARK: - Helpers

extension View {
    func hideKeyboard() {
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }
}
