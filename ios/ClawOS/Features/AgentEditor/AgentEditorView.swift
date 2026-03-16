import SwiftUI

struct AgentEditorView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss

    var existingAgent: Agent?

    @State private var name = ""
    @State private var selectedModel = ""

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
                .glassEffect(.regular, in: .rect(cornerRadius: AppTheme.Radius.md))
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
                .glassEffect(.regular, in: .rect(cornerRadius: AppTheme.Radius.md))
            }
        }
    }

    private var actionButton: some View {
        Button {
            if isEditing {
                // update agent
            } else {
                let newAgent = Agent(
                    id: UUID().uuidString,
                    name: name,
                    avatar: "avatar_eva01",
                    status: .online,
                    unreadCount: 0,
                    model: selectedModel,
                    availableModels: [selectedModel]
                )
                appState.agents.append(newAgent)
            }
            dismiss()
        } label: {
            Text(isEditing ? "保存" : "创建 Agent")
                .fontWeight(.semibold)
                .frame(maxWidth: .infinity)
                .frame(height: 50)
        }
        .buttonStyle(.glass)
        .tint(.primary)
        .disabled(name.isEmpty)
    }
}
