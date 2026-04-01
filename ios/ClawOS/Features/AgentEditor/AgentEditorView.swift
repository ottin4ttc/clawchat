import SwiftUI
import ClawChatKit

struct AgentEditorView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss

    var existingAgent: Agent?

    @State private var name = ""
    @State private var selectedModel = ""
    @State private var isSaving = false

    private var isEditing: Bool { existingAgent != nil }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: AppTheme.Spacing.xl) {
                    nameField
                    modelField
                    actionButton
                }
                .padding(AppTheme.Spacing.xl)
            }
            .navigationTitle(isEditing ? "编辑 Agent" : "新建 Agent")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
            }
            .onAppear {
                if let agent = existingAgent {
                    name = agent.name
                    selectedModel = agent.model ?? appState.allAvailableModels.first ?? ""
                } else if selectedModel.isEmpty {
                    selectedModel = appState.allAvailableModels.first ?? ""
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    private var nameField: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("名称")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            TextField("Agent 名称", text: $name)
                .textFieldStyle(.plain)
                .padding(12)
                .frame(height: 48)
                .adaptiveGlass(in: .rect(cornerRadius: AppTheme.Radius.md))
        }
    }

    private var modelField: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("默认模型")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Menu {
                ForEach(appState.allAvailableModels, id: \.self) { model in
                    Button {
                        selectedModel = model
                    } label: {
                        if model == selectedModel {
                            Label(model, systemImage: "checkmark")
                        } else {
                            Text(model)
                        }
                    }
                }
            } label: {
                HStack {
                    Text(selectedModel)
                        .foregroundStyle(.primary)
                    Spacer()
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 12)
                .frame(height: 48)
                .adaptiveGlass(in: .rect(cornerRadius: AppTheme.Radius.md))
            }
        }
    }

    private var actionButton: some View {
        Button {
            isSaving = true
            Task {
                await saveAgent()
                isSaving = false
                dismiss()
            }
        } label: {
            if isSaving {
                ProgressView()
                    .frame(maxWidth: .infinity)
                    .frame(height: 50)
            } else {
                Text(isEditing ? "保存" : "创建 Agent")
                    .fontWeight(.semibold)
                    .frame(maxWidth: .infinity)
                    .frame(height: 50)
            }
        }
        .adaptiveGlassButtonStyle()
        .tint(.primary)
        .disabled(name.isEmpty || isSaving)
    }

    private func saveAgent() async {
        guard let gw = appState.clawChatManager.gatewaySession else {
            // 无网关连接时仅本地保存
            if isEditing {
                if let idx = appState.agents.firstIndex(where: { $0.id == existingAgent?.id }) {
                    appState.agents[idx].name = name
                    appState.agents[idx].model = selectedModel
                }
            } else {
                let newAgent = Agent(
                    id: UUID().uuidString,
                    name: name,
                    avatar: "",
                    status: .online,
                    unreadCount: 0,
                    model: selectedModel,
                    availableModels: [selectedModel]
                )
                appState.agents.append(newAgent)
            }
            return
        }

        if isEditing, let agent = existingAgent {
            await gw.updateAgent(id: agent.id, name: name, model: selectedModel)
        } else {
            await gw.createAgent(name: name, model: selectedModel)
        }

        // 刷新 agent 列表
        let catalog: GatewayAgentsListResult? = try? await gw.fetchAgentsCatalog()
        if let catalog {
            let meta = catalog.agentsMeta
            appState.applyConnectionInfo(
                gatewayId: appState.selectedGatewayId,
                endpointUrl: appState.currentGateway?.url ?? "",
                agentIds: catalog.agentIds,
                agentsMeta: meta,
                connectionMethod: appState.currentGateway?.connectionMethod ?? .direct
            )
        }
    }
}
